// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../Orbit.sol";
import "./ISoulboundRegistrar.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../utils/ControllableUpgradeable.sol";

/**
 * @title SoulboundRegistrar
 * @notice Manages soulbound (non-transferable) domain registrations
 * @dev Extends ERC721 but overrides transfer functions to prevent transfers
 */
contract SoulboundRegistrar is Initializable, ERC721Upgradeable, OwnableUpgradeable, UUPSUpgradeable, ISoulboundRegistrar, ControllableUpgradeable {
    
    struct SoulboundDomain {
        string name;
        address originalOwner;
        uint256 reputation;
        uint256 mintTime;
        bool isActive;
        mapping(string => bool) verifications;
        string[] verificationTypes;
    }
    
    struct RecoveryRequest {
        address newOwner;
        uint256 initiatedAt;
        bool pending;
    }
    
    // State variables
    Orbit public orbit;
    bytes32 public baseNode;
    
    mapping(uint256 => SoulboundDomain) public domains;
    mapping(address => uint256) public ownerToDomain;
    mapping(uint256 => RecoveryRequest) public recoveryRequests;
    mapping(address => bool) public verifiers;
    
    uint256 public constant RECOVERY_DELAY = 7 days;
    uint256 public constant MAX_REPUTATION = 10000;
    uint256 private tokenIdCounter;
    
    // Modifiers
    modifier onlyVerifier() {
        require(verifiers[msg.sender], "Not a verifier");
        _;
    }
    
    modifier onlyTokenOwner(uint256 tokenId) {
        require(ownerOf(tokenId) == msg.sender, "Not token owner");
        _;
    }
    
    function initialize(
        Orbit _orbit,
        bytes32 _baseNode
    ) public initializer {
        __ERC721_init("Orbit Soulbound Domain", "SOUL");
        __Ownable_init(msg.sender);
        orbit = _orbit;
        baseNode = _baseNode;
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyOwner
        override
    {}
    
    /**
     * @notice Mint a new soulbound domain
     * @dev Only one soulbound domain per address
     */
    function mintSoulbound(
        string calldata name,
        address owner,
        address resolver
    ) external override onlyController returns (uint256) {
        require(ownerToDomain[owner] == 0, "Already has soulbound domain");
        require(bytes(name).length >= 3, "Name too short");
        
        uint256 tokenId = uint256(keccak256(abi.encodePacked(name, "soulbound")));
        
        // Mint the NFT
        _mint(owner, tokenId);
        
        // Initialize domain data
        SoulboundDomain storage domain = domains[tokenId];
        domain.name = name;
        domain.originalOwner = owner;
        domain.reputation = 100; // Starting reputation
        domain.mintTime = block.timestamp;
        domain.isActive = true;
        
        // Register in Orbit registry
        bytes32 label = keccak256(bytes(name));
        orbit.setSubnodeRecord(baseNode, label, owner, resolver, 0);
        
        // Track owner
        ownerToDomain[owner] = tokenId;
        
        emit SoulboundDomainMinted(tokenId, owner, name, block.timestamp);
        
        return tokenId;
    }
    
    /**
     * @notice Burn a soulbound domain (permanent)
     * @dev Only the owner can burn their domain
     */
    function burnSoulbound(uint256 tokenId) 
        external 
        override 
        onlyTokenOwner(tokenId) 
    {
        address owner = ownerOf(tokenId);
        string memory name = domains[tokenId].name;
        
        // Clear ownership tracking
        ownerToDomain[owner] = 0;
        
        // Mark as inactive
        domains[tokenId].isActive = false;
        
        // Burn the NFT
        _burn(tokenId);
        
        // Remove from registry
        bytes32 label = keccak256(bytes(name));
        orbit.setSubnodeOwner(baseNode, label, address(0));
        
        emit SoulboundDomainBurned(tokenId, owner, name, block.timestamp);
    }
    
    /**
     * @notice Check if a token is soulbound
     */
    function isSoulbound(uint256 tokenId) 
        external 
        view 
        override 
        returns (bool) 
    {
        return _ownerOf(tokenId) != address(0);
    }
    
    /**
     * @notice Get reputation score for a domain
     */
    function getReputation(uint256 tokenId) 
        external 
        view 
        override 
        returns (uint256) 
    {
        return domains[tokenId].reputation;
    }
    
    /**
     * @notice Increase reputation (only controllers/verifiers)
     */
    function incrementReputation(
        uint256 tokenId,
        uint256 amount,
        string calldata reason
    ) external override onlyController {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        
        uint256 oldScore = domains[tokenId].reputation;
        uint256 newScore = oldScore + amount;
        
        if (newScore > MAX_REPUTATION) {
            newScore = MAX_REPUTATION;
        }
        
        domains[tokenId].reputation = newScore;
        
        emit ReputationUpdated(tokenId, oldScore, newScore, reason);
    }
    
    /**
     * @notice Decrease reputation (only controllers/verifiers)
     */
    function decrementReputation(
        uint256 tokenId,
        uint256 amount,
        string calldata reason
    ) external override onlyController {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        
        uint256 oldScore = domains[tokenId].reputation;
        uint256 newScore = oldScore > amount ? oldScore - amount : 0;
        
        domains[tokenId].reputation = newScore;
        
        emit ReputationUpdated(tokenId, oldScore, newScore, reason);
    }
    
    /**
     * @notice Add verification badge to domain
     */
    function addVerification(
        uint256 tokenId,
        string calldata verificationType,
        bytes calldata // proof - reserved for future use
    ) external override onlyVerifier {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        require(!domains[tokenId].verifications[verificationType], "Already verified");
        
        domains[tokenId].verifications[verificationType] = true;
        domains[tokenId].verificationTypes.push(verificationType);
        
        emit VerificationAdded(tokenId, verificationType, msg.sender, block.timestamp);
    }
    
    /**
     * @notice Check if domain has specific verification
     */
    function hasVerification(
        uint256 tokenId,
        string calldata verificationType
    ) external view override returns (bool) {
        return domains[tokenId].verifications[verificationType];
    }
    
    /**
     * @notice Get all verifications for a domain
     */
    function getVerifications(uint256 tokenId) 
        external 
        view 
        override 
        returns (string[] memory) 
    {
        return domains[tokenId].verificationTypes;
    }
    
    /**
     * @notice Initiate recovery process (for lost keys)
     * @dev Requires multi-sig or DAO approval in production
     */
    function initiateRecovery(uint256 tokenId, address newOwner) 
        external 
        override 
        onlyOwner 
    {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        require(!recoveryRequests[tokenId].pending, "Recovery already pending");
        
        recoveryRequests[tokenId] = RecoveryRequest({
            newOwner: newOwner,
            initiatedAt: block.timestamp,
            pending: true
        });
    }
    
    /**
     * @notice Complete recovery after delay period
     */
    function completeRecovery(uint256 tokenId) external override onlyOwner {
        RecoveryRequest memory request = recoveryRequests[tokenId];
        require(request.pending, "No pending recovery");
        require(
            block.timestamp >= request.initiatedAt + RECOVERY_DELAY,
            "Recovery delay not met"
        );
        
        address oldOwner = ownerOf(tokenId);
        
        // Update ownership tracking
        ownerToDomain[oldOwner] = 0;
        ownerToDomain[request.newOwner] = tokenId;
        
        // Force transfer (bypassing soulbound restriction for recovery)
        _transfer(oldOwner, request.newOwner, tokenId);
        
        // Update registry
        string memory name = domains[tokenId].name;
        bytes32 label = keccak256(bytes(name));
        orbit.setSubnodeOwner(baseNode, label, request.newOwner);
        
        // Clear recovery request
        delete recoveryRequests[tokenId];
    }
    
    /**
     * @notice Cancel recovery request
     */
    function cancelRecovery(uint256 tokenId) external override onlyOwner {
        require(recoveryRequests[tokenId].pending, "No pending recovery");
        delete recoveryRequests[tokenId];
    }
    
    /**
     * @notice Get token ID for an owner
     */
    function tokenByOwner(address owner) 
        external 
        view 
        override 
        returns (uint256) 
    {
        return ownerToDomain[owner];
    }
    
    /**
     * @notice Check if address has soulbound domain
     */
    function hasSoulboundDomain(address owner) 
        external 
        view 
        override 
        returns (bool) 
    {
        return ownerToDomain[owner] != 0;
    }
    
    /**
     * @notice Get complete metadata for a domain
     */
    function getMetadata(uint256 tokenId) 
        external 
        view 
        override 
        returns (
            string memory name,
            address owner,
            uint256 reputation,
            uint256 mintTime,
            bool isActive
        ) 
    {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        SoulboundDomain storage domain = domains[tokenId];
        
        return (
            domain.name,
            ownerOf(tokenId),
            domain.reputation,
            domain.mintTime,
            domain.isActive
        );
    }
    
    /**
     * @notice Set verifier status
     */
    function setVerifier(address verifier, bool status) external onlyOwner {
        verifiers[verifier] = status;
    }
    
    // Override transfer functions to prevent transfers
    function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address) {
        address from = super._update(to, tokenId, auth);
        
        // Allow minting and burning
        if (from == address(0) || to == address(0)) {
            return from;
        }
        
        // Check if this is a recovery transfer
        if (recoveryRequests[tokenId].pending && 
            recoveryRequests[tokenId].newOwner == to) {
            return from;
        }
        
        // Otherwise, prevent all transfers
        revert("Soulbound: transfers disabled");
    }
    
    /**
     * @notice Override to prevent approvals
     */
    function approve(address, uint256) public virtual override {
        revert("Soulbound: approvals disabled");
    }
    
    /**
     * @notice Override to prevent operator approvals
     */
    function setApprovalForAll(address, bool) public virtual override {
        revert("Soulbound: approvals disabled");
    }
}
