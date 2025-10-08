// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../utils/Ownable.sol";
import "./structs.sol";

/**
 * @title TLDStorage
 * @notice Centralized storage for TLD data
 * @dev Separate storage contract to reduce main contract size
 */
contract TLDStorage is Ownable {
    // Core mappings
    mapping(uint256 => TLD) public tlds;
    mapping(string => uint256) public nameToTokenId;
    mapping(address => uint256[]) public ownerTLDs;
    mapping(uint256 => uint256) public tldExpiries;
    mapping(uint256 => bool) public tldInGracePeriod;

    // Reserved TLD tracking
    mapping(string => bool) public reservedTLDs;
    mapping(string => address) public reservedFor;

    // Access control
    mapping(address => bool) public authorized;

    modifier onlyAuthorized() {
        require(
            authorized[msg.sender] || msg.sender == owner(),
            "Not authorized"
        );
        _;
    }

    constructor() {}

    // Authorization management
    function authorize(address account) external onlyOwner {
        authorized[account] = true;
    }

    function unauthorize(address account) external onlyOwner {
        authorized[account] = false;
    }

    // TLD data management
    function createTLD(
        uint256 tokenId,
        string calldata name,
        address tldOwner,
        address registrar,
        uint256 registrationFee,
        uint256 ownerSharePercentage,
        uint256 expirationTime,
        uint256 renewalFee
    ) external onlyAuthorized {
        TLD storage tld = tlds[tokenId];
        tld.name = stringToBytes32(name);
        tld.owner = tldOwner;
        tld.registrar = registrar;
        tld.creationTime = block.timestamp;
        tld.registrationFee = registrationFee;
        tld.ownerSharePercentage = ownerSharePercentage;
        tld.expirationTime = expirationTime;
        tld.renewalFee = renewalFee;
        tld.isActive = true;

        nameToTokenId[name] = tokenId;
        ownerTLDs[tldOwner].push(tokenId);
        tldExpiries[tokenId] = expirationTime;
    }

    function updateTLDOwner(
        uint256 tokenId,
        address newOwner
    ) external onlyAuthorized {
        address oldOwner = tlds[tokenId].owner;

        // Remove from old owner's list
        uint256[] storage oldOwnerTLDs = ownerTLDs[oldOwner];
        for (uint256 i = 0; i < oldOwnerTLDs.length; i++) {
            if (oldOwnerTLDs[i] == tokenId) {
                oldOwnerTLDs[i] = oldOwnerTLDs[oldOwnerTLDs.length - 1];
                oldOwnerTLDs.pop();
                break;
            }
        }

        // Add to new owner's list
        ownerTLDs[newOwner].push(tokenId);
        tlds[tokenId].owner = newOwner;
    }

    function updateTLDRevenue(
        uint256 tokenId,
        uint256 amount
    ) external onlyAuthorized {
        tlds[tokenId].totalRevenue += amount;
        tlds[tokenId].totalRegistrations++;
    }

    function updateTLDExpiration(
        uint256 tokenId,
        uint256 newExpiration
    ) external onlyAuthorized {
        tlds[tokenId].expirationTime = newExpiration;
        tldExpiries[tokenId] = newExpiration;
        tldInGracePeriod[tokenId] = false;
    }

    function setTLDGracePeriod(
        uint256 tokenId,
        bool inGrace
    ) external onlyAuthorized {
        tldInGracePeriod[tokenId] = inGrace;
    }

    function setTLDActive(
        uint256 tokenId,
        bool active
    ) external onlyAuthorized {
        tlds[tokenId].isActive = active;
    }

    function updateTLDFees(
        uint256 tokenId,
        uint256 registrationFee,
        uint256 renewalFee
    ) external onlyAuthorized {
        tlds[tokenId].registrationFee = registrationFee;
        tlds[tokenId].renewalFee = renewalFee;
    }

    // Reserved TLD management
    function setReservedTLD(
        string calldata name,
        bool reserved
    ) external onlyAuthorized {
        reservedTLDs[name] = reserved;
    }

    function setReservedFor(
        string calldata name,
        address account
    ) external onlyAuthorized {
        reservedFor[name] = account;
    }

    // View functions
    function getTLD(uint256 tokenId) external view returns (TLD memory) {
        return tlds[tokenId];
    }

    function getOwnerTLDs(
        address owner
    ) external view returns (uint256[] memory) {
        return ownerTLDs[owner];
    }

    function isNameAvailable(
        string calldata name
    ) external view returns (bool) {
        return nameToTokenId[name] == 0 && !reservedTLDs[name];
    }

    function isNameReservedFor(
        string calldata name,
        address account
    ) external view returns (bool) {
        return reservedTLDs[name] && reservedFor[name] == account;
    }

    function stringToBytes32(
        string memory source
    ) internal pure returns (bytes32 result) {
        bytes memory temp = bytes(source);
        if (temp.length == 0) {
            return 0x0;
        }

        assembly {
            result := mload(add(source, 32))
        }
    }
}
