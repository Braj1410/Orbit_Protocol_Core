// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/**
 * @title ISoulboundRegistrar
 * @notice Interface for soulbound (non-transferable) domain registration
 * @dev Soulbound domains cannot be transferred once minted
 */
interface ISoulboundRegistrar {
    
    // Events
    event SoulboundDomainMinted(
        uint256 indexed tokenId,
        address indexed owner,
        string name,
        uint256 timestamp
    );
    
    event SoulboundDomainBurned(
        uint256 indexed tokenId,
        address indexed owner,
        string name,
        uint256 timestamp
    );
    
    event ReputationUpdated(
        uint256 indexed tokenId,
        uint256 oldScore,
        uint256 newScore,
        string reason
    );
    
    event VerificationAdded(
        uint256 indexed tokenId,
        string verificationType,
        address verifier,
        uint256 timestamp
    );
    
    // Core functions
    function mintSoulbound(
        string calldata name,
        address owner,
        address resolver
    ) external returns (uint256);
    
    function burnSoulbound(uint256 tokenId) external;
    
    function isSoulbound(uint256 tokenId) external view returns (bool);
    
    // Reputation functions
    function getReputation(uint256 tokenId) external view returns (uint256);
    
    function incrementReputation(
        uint256 tokenId,
        uint256 amount,
        string calldata reason
    ) external;
    
    function decrementReputation(
        uint256 tokenId,
        uint256 amount,
        string calldata reason
    ) external;
    
    // Verification functions
    function addVerification(
        uint256 tokenId,
        string calldata verificationType,
        bytes calldata proof
    ) external;
    
    function hasVerification(
        uint256 tokenId,
        string calldata verificationType
    ) external view returns (bool);
    
    function getVerifications(uint256 tokenId) 
        external 
        view 
        returns (string[] memory);
    
    // Recovery functions (for lost private keys)
    function initiateRecovery(uint256 tokenId, address newOwner) external;
    
    function completeRecovery(uint256 tokenId) external;
    
    function cancelRecovery(uint256 tokenId) external;
    
    // View functions
    function tokenByOwner(address owner) external view returns (uint256);
    
    function hasSoulboundDomain(address owner) external view returns (bool);
    
    function getMetadata(uint256 tokenId) 
        external 
        view 
        returns (
            string memory name,
            address owner,
            uint256 reputation,
            uint256 mintTime,
            bool isActive
        );
}