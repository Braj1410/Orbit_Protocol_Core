// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../utils/Ownable.sol";
import "./TLDStorage.sol";

/**
 * @title TLDRevenueModule
 * @notice Handles revenue distribution for TLDs
 * @dev Separate module for revenue management
 */
contract TLDRevenueModule is Ownable {
    TLDStorage public immutable storage_;
    address public factory;
    address public protocolTreasury;

    // Revenue tracking
    mapping(address => uint256) public pendingWithdrawals;
    mapping(uint256 => uint256) public tldProtocolRevenue;
    mapping(uint256 => uint256) public tldOwnerRevenue;

    uint256 public totalProtocolRevenue;
    uint256 public defaultOwnerShare = 50; // 50%
    uint256 public protocolShare = 50; // 50%

    // Events
    event RevenueDistributed(
        uint256 indexed tokenId,
        uint256 ownerAmount,
        uint256 protocolAmount
    );

    event Withdrawal(address indexed recipient, uint256 amount);

    event SharesUpdated(uint256 ownerShare, uint256 protocolShare);

    event TreasuryUpdated(address newTreasury);

    modifier onlyFactory() {
        require(msg.sender == factory, "Only factory");
        _;
    }

    constructor(address _storage, address _treasury) {
        storage_ = TLDStorage(_storage);
        protocolTreasury = _treasury;
    }

    function setFactory(address _factory) external onlyOwner {
        factory = _factory;
    }

    function setProtocolTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid treasury");
        protocolTreasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }

    function updateShares(
        uint256 _ownerShare,
        uint256 _protocolShare
    ) external onlyOwner {
        require(_ownerShare + _protocolShare == 100, "Must equal 100");
        defaultOwnerShare = _ownerShare;
        protocolShare = _protocolShare;
        emit SharesUpdated(_ownerShare, _protocolShare);
    }

    /**
     * @notice Distribute revenue from a domain registration
     */
    function distributeRevenue(
        uint256 tokenId,
        uint256 amount
    ) external payable onlyFactory {
        require(msg.value == amount, "Incorrect value");

        TLD memory tld = storage_.getTLD(tokenId);
        require(tld.owner != address(0), "Invalid TLD");

        uint256 ownerShare = tld.ownerSharePercentage > 0
            ? tld.ownerSharePercentage
            : defaultOwnerShare;
        uint256 ownerAmount = (amount * ownerShare) / 100;
        uint256 protocolAmount = amount - ownerAmount;

        // Track revenue
        tldOwnerRevenue[tokenId] += ownerAmount;
        tldProtocolRevenue[tokenId] += protocolAmount;
        totalProtocolRevenue += protocolAmount;

        // Add to pending withdrawals
        pendingWithdrawals[tld.owner] += ownerAmount;
        pendingWithdrawals[protocolTreasury] += protocolAmount;

        // Update TLD revenue in storage
        storage_.updateTLDRevenue(tokenId, amount);

        emit RevenueDistributed(tokenId, ownerAmount, protocolAmount);
    }

    /**
     * @notice Process TLD renewal fee
     */
    function processRenewalFee(uint256 tokenId) external payable onlyFactory {
        TLD memory tld = storage_.getTLD(tokenId);
        require(msg.value == tld.renewalFee, "Incorrect fee");

        // All renewal fees go to protocol
        pendingWithdrawals[protocolTreasury] += msg.value;
        totalProtocolRevenue += msg.value;
    }

    /**
     * @notice Process TLD creation fee
     */
    function processCreationFee(uint256 fee) external payable onlyFactory {
        require(msg.value == fee, "Incorrect fee");
        pendingWithdrawals[protocolTreasury] += msg.value;
        totalProtocolRevenue += msg.value;
    }

    /**
     * @notice Withdraw pending revenue
     */
    function withdraw() external {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "Nothing to withdraw");

        pendingWithdrawals[msg.sender] = 0;

        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");

        emit Withdrawal(msg.sender, amount);
    }

    /**
     * @notice Batch withdraw for multiple addresses
     */
    function batchWithdraw(address[] calldata recipients) external onlyOwner {
        for (uint256 i = 0; i < recipients.length; i++) {
            address recipient = recipients[i];
            uint256 amount = pendingWithdrawals[recipient];

            if (amount > 0) {
                pendingWithdrawals[recipient] = 0;
                (bool success, ) = recipient.call{value: amount}("");
                if (success) {
                    emit Withdrawal(recipient, amount);
                } else {
                    // Restore balance if transfer fails
                    pendingWithdrawals[recipient] = amount;
                }
            }
        }
    }

    /**
     * @notice Get TLD revenue statistics
     */
    function getTLDRevenue(
        uint256 tokenId
    )
        external
        view
        returns (
            uint256 ownerRevenue,
            uint256 protocolRevenue,
            uint256 totalRevenue
        )
    {
        ownerRevenue = tldOwnerRevenue[tokenId];
        protocolRevenue = tldProtocolRevenue[tokenId];
        totalRevenue = ownerRevenue + protocolRevenue;
    }

    /**
     * @notice Get pending withdrawal amount
     */
    function getPendingWithdrawal(
        address account
    ) external view returns (uint256) {
        return pendingWithdrawals[account];
    }

    /**
     * @notice Emergency withdraw (owner only)
     */
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance");

        (bool success, ) = protocolTreasury.call{value: balance}("");
        require(success, "Transfer failed");
    }
}
