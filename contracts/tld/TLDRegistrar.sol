// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../Orbit.sol";
import "../registrars/BaseRegistrar.sol";
import "./ITLDFactory.sol";

/**
 * @title TLDRegistrar
 * @notice Registrar for a specific TLD, manages domain registrations
 * @dev Created by TLDFactory for each TLD
 */
contract TLDRegistrar is BaseRegistrar {
    address public tldFactory;
    uint256 public tldTokenId;
    uint256 public registrationFee;

    // Protocol protection - minimum 1 CRO per registration
    uint256 public constant MIN_PROTOCOL_FEE = 1 ether; // 1 CRO minimum

    mapping(string => bool) public reserved;
    mapping(address => uint256) public discounts; // Address-specific discounts

    event DomainRegistered(
        string name,
        address indexed owner,
        uint256 duration,
        uint256 fee
    );

    event DomainRenewed(string name, uint256 duration, uint256 fee);

    modifier onlyFactory() {
        require(msg.sender == tldFactory, "Only factory");
        _;
    }

    function initialize(
        Orbit _orbit,
        bytes32 _baseNode,
        address _factory,
        address _owner
    ) public initializer {
        tldFactory = _factory;
        super.initialize(_orbit, _baseNode, _owner);
    }

    /**
     * @notice Register a domain under this TLD
     */
    function registerDomain(
        string calldata name,
        address owner,
        uint256 duration
    ) external payable returns (uint256) {
        require(duration >= 365 days, "Minimum 1 year");

        // CRITICAL: Normalize domain name to lowercase to prevent case variations
        string memory normalizedName = _toLowerCase(name);
        require(!reserved[normalizedName], "Name reserved");

        uint256 fee = calculateFee(normalizedName, duration, msg.sender);
        require(msg.value >= fee, "Insufficient payment");

        // Register the domain using normalized name
        uint256 tokenId = uint256(
            keccak256(abi.encodePacked(baseNode, normalizedName))
        );
        _register(tokenId, owner, duration, true);

        // Send revenue to factory for distribution with duration
        if (fee > 0) {
            ITLDFactory(tldFactory).distributeRevenue{value: fee}(
                tldTokenId,
                duration
            );
        }

        // Refund excess
        if (msg.value > fee) {
            (bool success, ) = payable(msg.sender).call{value: msg.value - fee}(
                ""
            );
            require(success, "TLDRegistrar: Refund failed");
        }

        emit DomainRegistered(name, owner, duration, fee);

        return tokenId;
    }

    /**
     * @notice Renew a domain
     */
    function renewDomain(
        string calldata name,
        uint256 duration
    ) external payable {
        require(duration >= 365 days, "Minimum 1 year");

        // CRITICAL: Normalize domain name to lowercase for consistency
        string memory normalizedName = _toLowerCase(name);
        uint256 tokenId = uint256(
            keccak256(abi.encodePacked(baseNode, normalizedName))
        );
        uint256 fee = calculateFee(normalizedName, duration, msg.sender);
        require(msg.value >= fee, "Insufficient payment");

        // Renew the domain
        expiries[tokenId] = expiries[tokenId] + duration;

        // Send revenue to factory with duration
        if (fee > 0) {
            ITLDFactory(tldFactory).distributeRevenue{value: fee}(
                tldTokenId,
                duration
            );
        }

        // Refund excess
        if (msg.value > fee) {
            (bool success, ) = payable(msg.sender).call{value: msg.value - fee}(
                ""
            );
            require(success, "TLDRegistrar: Refund failed");
        }

        emit DomainRenewed(normalizedName, duration, fee);
    }

    /**
     * @notice Calculate registration/renewal fee with protocol minimum protection
     */
    function calculateFee(
        string memory name,
        uint256 duration,
        address registrant
    ) public view returns (uint256) {
        // Get base fee from factory
        (, , , uint256 baseFee, , , , , , , ) = ITLDFactory(tldFactory).getTLD(
            tldTokenId
        );

        // Calculate user fee based on duration
        uint256 userFee = (baseFee * duration) / 365 days;

        // Apply length-based pricing to user fee
        uint256 length = bytes(name).length;
        if (length <= 2) {
            userFee = userFee * 10; // 10x for 1-2 char names
        } else if (length == 3) {
            userFee = userFee * 5; // 5x for 3 char names
        } else if (length == 4) {
            userFee = userFee * 2; // 2x for 4 char names
        }

        // Apply discounts to user fee only
        uint256 discount = discounts[registrant];
        if (discount > 0) {
            userFee = (userFee * (100 - discount)) / 100;
        }

        // Calculate protocol minimum fee based on duration
        uint256 protocolMinimum = (MIN_PROTOCOL_FEE * duration) / 365 days;

        // Total fee = user fee + protocol minimum
        return userFee + protocolMinimum;
    }

    /**
     * @notice Get fee breakdown for transparency
     */
    function getFeeBreakdown(
        string calldata name,
        uint256 duration,
        address registrant
    )
        external
        view
        returns (uint256 userFee, uint256 protocolFee, uint256 totalFee)
    {
        // Get base fee from factory
        (, , , uint256 baseFee, , , , , , , ) = ITLDFactory(tldFactory).getTLD(
            tldTokenId
        );

        // Calculate user fee
        userFee = (baseFee * duration) / 365 days;

        // Apply length-based pricing
        uint256 length = bytes(name).length;
        if (length <= 2) {
            userFee = userFee * 10;
        } else if (length == 3) {
            userFee = userFee * 5;
        } else if (length == 4) {
            userFee = userFee * 2;
        }

        // Apply discounts to user fee only
        uint256 discount = discounts[registrant];
        if (discount > 0) {
            userFee = (userFee * (100 - discount)) / 100;
        }

        // Protocol fee is always minimum based on duration
        protocolFee = (MIN_PROTOCOL_FEE * duration) / 365 days;

        // Total fee
        totalFee = userFee + protocolFee;
    }

    /**
     * @notice Reserve names (only TLD owner)
     */
    function reserveNames(string[] calldata names) external onlyOwner {
        for (uint256 i = 0; i < names.length; i++) {
            string memory normalizedName = _toLowerCase(names[i]);
            reserved[normalizedName] = true;
        }
    }

    /**
     * @notice Unreserve names (only TLD owner)
     */
    function unreserveNames(string[] calldata names) external onlyOwner {
        for (uint256 i = 0; i < names.length; i++) {
            string memory normalizedName = _toLowerCase(names[i]);
            reserved[normalizedName] = false;
        }
    }

    /**
     * @notice Set discount for specific address (max 50% to protect protocol revenue)
     */
    function setDiscount(
        address user,
        uint256 discountPercentage
    ) external onlyOwner {
        require(discountPercentage <= 50, "Maximum 50% discount allowed");
        discounts[user] = discountPercentage;
    }

    /**
     * @notice Update TLD token ID (only factory)
     */
    function setTLDTokenId(uint256 _tokenId) external onlyFactory {
        tldTokenId = _tokenId;
    }

    /**
     * @notice Check if name is available
     */
    function isAvailable(string calldata name) external view returns (bool) {
        string memory normalizedName = _toLowerCase(name);
        if (reserved[normalizedName]) return false;

        uint256 tokenId = uint256(
            keccak256(abi.encodePacked(baseNode, normalizedName))
        );
        return super.available(tokenId);
    }

    /**
     * @notice Convert string to lowercase to prevent case variation conflicts
     * @dev Prevents duplicate domains like Joey.roo and joey.roo
     */
    function _toLowerCase(
        string calldata str
    ) private pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        bytes memory lowerBytes = new bytes(strBytes.length);

        for (uint256 i = 0; i < strBytes.length; i++) {
            // Convert A-Z to a-z
            if (strBytes[i] >= 0x41 && strBytes[i] <= 0x5A) {
                lowerBytes[i] = bytes1(uint8(strBytes[i]) + 32);
            } else {
                lowerBytes[i] = strBytes[i];
            }
        }

        return string(lowerBytes);
    }
}
