// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../Orbit.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title OfficialBadgeRegistry
 * @notice Protocol-controlled soulbound badges for official identities
 * @dev Non-transferable NFTs for KYC, team members, treasuries, etc.
 */
contract OfficialBadgeRegistry is Initializable, ERC721Upgradeable, OwnableUpgradeable, UUPSUpgradeable {
    
    // Badge categories
    enum BadgeType {
        KYC_VERIFIED,           // KYC verified user
        OFFICIAL_TEAM,          // Official team member
        MARKETING_WALLET,       // Marketing wallet
        TREASURY_WALLET,        // Treasury wallet
        FOUNDER_WALLET,         // Founder wallet
        MULTISIG_WALLET,        // Multi-sig wallet
        PROTOCOL_CONTRACT,      // Protocol smart contract
        PARTNER_PROJECT,        // Partner project
        VERIFIED_DEVELOPER,     // Verified developer
        AUDITOR                 // Security auditor
    }
    
    struct Badge {
        BadgeType badgeType;
        string organization;     // e.g., "FFS", "VVS", "CRONOS"
        string role;            // e.g., "Founder", "Marketing Lead"
        string metadata;        // Additional JSON metadata
        uint256 issuedAt;
        uint256 expiresAt;      // 0 for permanent
        bool isActive;
        address issuer;         // Who issued this badge
    }
    
    struct KYCData {
        bytes32 kycHash;        // Hash of KYC documents
        string provider;        // KYC provider name
        uint256 verifiedAt;
        uint256 level;          // KYC level (1-3)
        string country;         // Country code
    }
    
    // Storage
    mapping(uint256 => Badge) public badges;
    mapping(uint256 => KYCData) public kycData;
    mapping(address => uint256[]) public addressBadges;
    mapping(string => mapping(BadgeType => uint256)) public organizationBadges;
    
    // Badge ID counter
    uint256 private _badgeIdCounter;
    
    // Protocol-controlled TLDs
    Orbit public orbit;
    bytes32 public kycNode;      // .kyc TLD
    bytes32 public officialNode;  // .official TLD
    
    // Events
    event BadgeIssued(
        uint256 indexed badgeId,
        address indexed recipient,
        BadgeType badgeType,
        string organization,
        string role
    );
    
    event KYCVerified(
        uint256 indexed badgeId,
        address indexed user,
        string provider,
        uint256 level
    );
    
    event BadgeRevoked(
        uint256 indexed badgeId,
        address indexed holder,
        string reason
    );
    
    event BadgeMetadataUpdated(
        uint256 indexed badgeId,
        string newMetadata
    );
    
    function initialize(
        Orbit _orbit,
        bytes32 _kycNode,
        bytes32 _officialNode
    ) public initializer {
        __ERC721_init("Orbit Official Badge", "BADGE");
        __Ownable_init(msg.sender);
        orbit = _orbit;
        kycNode = _kycNode;
        officialNode = _officialNode;
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyOwner
        override
    {}
    
    /**
     * @notice Issue an official badge (protocol only)
     */
    function issueBadge(
        address recipient,
        BadgeType badgeType,
        string memory organization,
        string memory role,
        string memory metadata,
        uint256 expiresAt
    ) public onlyOwner returns (uint256) {
        uint256 badgeId = ++_badgeIdCounter;
        
        badges[badgeId] = Badge({
            badgeType: badgeType,
            organization: organization,
            role: role,
            metadata: metadata,
            issuedAt: block.timestamp,
            expiresAt: expiresAt,
            isActive: true,
            issuer: msg.sender
        });
        
        // Mint soulbound NFT
        _safeMint(recipient, badgeId);
        addressBadges[recipient].push(badgeId);
        
        // Register subdomain if applicable
        _registerBadgeDomain(recipient, badgeType, organization, role);
        
        emit BadgeIssued(badgeId, recipient, badgeType, organization, role);
        
        return badgeId;
    }
    
    /**
     * @notice Issue KYC verification badge
     */
    function issueKYCBadge(
        address user,
        bytes32 _kycHash,
        string memory provider,
        uint256 level,
        string memory country
    ) external onlyOwner returns (uint256) {
        require(level >= 1 && level <= 3, "Invalid KYC level");
        
        uint256 badgeId = issueBadge(
            user,
            BadgeType.KYC_VERIFIED,
            provider,
            string(abi.encodePacked("KYC Level ", _toString(level))),
            "",
            0 // Permanent unless revoked
        );
        
        kycData[badgeId] = KYCData({
            kycHash: _kycHash,
            provider: provider,
            verifiedAt: block.timestamp,
            level: level,
            country: country
        });
        
        // Register user.kyc domain
        _registerKYCDomain(user);
        
        emit KYCVerified(badgeId, user, provider, level);
        
        return badgeId;
    }
    
    /**
     * @notice Batch issue team badges
     */
    function issueTeamBadges(
        address[] memory recipients,
        string memory organization,
        string[] memory roles,
        BadgeType badgeType
    ) external onlyOwner {
        require(recipients.length == roles.length, "Mismatched arrays");
        
        for (uint i = 0; i < recipients.length; i++) {
            issueBadge(
                recipients[i],
                badgeType,
                organization,
                roles[i],
                "",
                0 // Permanent
            );
        }
    }
    
    /**
     * @notice Revoke a badge
     */
    function revokeBadge(uint256 badgeId, string memory reason) external onlyOwner {
        require(_ownerOf(badgeId) != address(0), "Badge does not exist");
        
        Badge storage badge = badges[badgeId];
        badge.isActive = false;
        
        address holder = ownerOf(badgeId);
        emit BadgeRevoked(badgeId, holder, reason);
    }
    
    /**
     * @notice Update badge metadata
     */
    function updateBadgeMetadata(
        uint256 badgeId,
        string memory newMetadata
    ) external onlyOwner {
        require(_ownerOf(badgeId) != address(0), "Badge does not exist");
        badges[badgeId].metadata = newMetadata;
        emit BadgeMetadataUpdated(badgeId, newMetadata);
    }
    
    /**
     * @notice Check if address has specific badge type
     */
    function hasBadgeType(address user, BadgeType badgeType) 
        public 
        view 
        returns (bool) 
    {
        uint256[] memory userBadges = addressBadges[user];
        for (uint i = 0; i < userBadges.length; i++) {
            Badge memory badge = badges[userBadges[i]];
            if (badge.badgeType == badgeType && badge.isActive) {
                if (badge.expiresAt == 0 || badge.expiresAt > block.timestamp) {
                    return true;
                }
            }
        }
        return false;
    }
    
    /**
     * @notice Get all badges for an address
     */
    function getBadges(address user) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return addressBadges[user];
    }
    
    /**
     * @notice Get active badges for an address
     */
    function getActiveBadges(address user) 
        external 
        view 
        returns (uint256[] memory) 
    {
        uint256[] memory userBadges = addressBadges[user];
        uint256 activeCount = 0;
        
        // Count active badges
        for (uint i = 0; i < userBadges.length; i++) {
            Badge memory badge = badges[userBadges[i]];
            if (badge.isActive && 
                (badge.expiresAt == 0 || badge.expiresAt > block.timestamp)) {
                activeCount++;
            }
        }
        
        // Create array of active badges
        uint256[] memory activeBadges = new uint256[](activeCount);
        uint256 index = 0;
        for (uint i = 0; i < userBadges.length; i++) {
            Badge memory badge = badges[userBadges[i]];
            if (badge.isActive && 
                (badge.expiresAt == 0 || badge.expiresAt > block.timestamp)) {
                activeBadges[index++] = userBadges[i];
            }
        }
        
        return activeBadges;
    }
    
    /**
     * @notice Get KYC level for user
     */
    function getKYCLevel(address user) external view returns (uint256) {
        uint256[] memory userBadges = addressBadges[user];
        for (uint i = 0; i < userBadges.length; i++) {
            Badge memory badge = badges[userBadges[i]];
            if (badge.badgeType == BadgeType.KYC_VERIFIED && badge.isActive) {
                return kycData[userBadges[i]].level;
            }
        }
        return 0; // Not KYC verified
    }
    
    /**
     * @notice Register badge domain under .official
     */
    function _registerBadgeDomain(
        address recipient,
        BadgeType badgeType,
        string memory organization,
        string memory role
    ) internal {
        if (badgeType == BadgeType.OFFICIAL_TEAM ||
            badgeType == BadgeType.FOUNDER_WALLET ||
            badgeType == BadgeType.TREASURY_WALLET ||
            badgeType == BadgeType.MARKETING_WALLET) {
            
            // Create organization-role.official domain
            string memory subdomain = string(abi.encodePacked(
                _toLowerCase(organization),
                "-",
                _toLowerCase(role)
            ));
            
            // Note: subnode calculation for reference but not used in this simplified version
            // bytes32 subnode = keccak256(abi.encodePacked(officialNode, keccak256(bytes(subdomain))));
            
            // Register subdomain pointing to recipient
            orbit.setSubnodeOwner(officialNode, keccak256(bytes(subdomain)), recipient);
        }
    }
    
    /**
     * @notice Register KYC domain
     */
    function _registerKYCDomain(address user) internal {
        // Generate unique KYC identifier
        string memory kycId = _addressToString(user);
        // Note: subnode calculation for reference but not used in this simplified version
        // bytes32 subnode = keccak256(abi.encodePacked(kycNode, keccak256(bytes(kycId))));
        
        // Register user.kyc domain
        orbit.setSubnodeOwner(kycNode, keccak256(bytes(kycId)), user);
    }
    
    /**
     * @notice Override transfer functions to make badges soulbound
     */
    function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address) {
        address from = super._update(to, tokenId, auth);
        require(
            from == address(0) || to == address(0),
            "Badges are soulbound and cannot be transferred"
        );
        return from;
    }
    
    /**
     * @notice Badge metadata URI
     */
    function tokenURI(uint256 badgeId) 
        public 
        view 
        override 
        returns (string memory) 
    {
        require(_ownerOf(badgeId) != address(0), "Badge does not exist");
        
        Badge memory badge = badges[badgeId];
        
        // Construct on-chain metadata
        string memory json = string(abi.encodePacked(
            '{"name":"',
            badge.organization,
            ' - ',
            badge.role,
            '","description":"Official Badge","attributes":[',
            '{"trait_type":"Type","value":"',
            _badgeTypeToString(badge.badgeType),
            '"},{"trait_type":"Organization","value":"',
            badge.organization,
            '"},{"trait_type":"Role","value":"',
            badge.role,
            '"},{"trait_type":"Active","value":"',
            badge.isActive ? 'true' : 'false',
            '"}]}'
        ));
        
        return string(abi.encodePacked(
            "data:application/json;base64,",
            _base64Encode(bytes(json))
        ));
    }
    
    // Utility functions
    function _badgeTypeToString(BadgeType badgeType) internal pure returns (string memory) {
        if (badgeType == BadgeType.KYC_VERIFIED) return "KYC Verified";
        if (badgeType == BadgeType.OFFICIAL_TEAM) return "Official Team";
        if (badgeType == BadgeType.MARKETING_WALLET) return "Marketing Wallet";
        if (badgeType == BadgeType.TREASURY_WALLET) return "Treasury Wallet";
        if (badgeType == BadgeType.FOUNDER_WALLET) return "Founder Wallet";
        if (badgeType == BadgeType.MULTISIG_WALLET) return "Multi-sig Wallet";
        if (badgeType == BadgeType.PROTOCOL_CONTRACT) return "Protocol Contract";
        if (badgeType == BadgeType.PARTNER_PROJECT) return "Partner Project";
        if (badgeType == BadgeType.VERIFIED_DEVELOPER) return "Verified Developer";
        if (badgeType == BadgeType.AUDITOR) return "Security Auditor";
        return "Unknown";
    }
    
    function _toLowerCase(string memory str) internal pure returns (string memory) {
        bytes memory bStr = bytes(str);
        bytes memory bLower = new bytes(bStr.length);
        for (uint i = 0; i < bStr.length; i++) {
            if ((bStr[i] >= 0x41) && (bStr[i] <= 0x5A)) {
                bLower[i] = bytes1(uint8(bStr[i]) + 32);
            } else {
                bLower[i] = bStr[i];
            }
        }
        return string(bLower);
    }
    
    function _addressToString(address addr) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory data = abi.encodePacked(addr);
        bytes memory str = new bytes(2 + data.length * 2);
        str[0] = "0";
        str[1] = "x";
        for (uint i = 0; i < data.length; i++) {
            str[2+i*2] = alphabet[uint(uint8(data[i] >> 4))];
            str[3+i*2] = alphabet[uint(uint8(data[i] & 0x0f))];
        }
        return string(str);
    }
    
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
    
    function _base64Encode(bytes memory data) internal pure returns (string memory) {
        if (data.length == 0) return "";

        bytes memory table = bytes("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/");
        uint256 encodedLen = 4 * ((data.length + 2) / 3);
        bytes memory result = new bytes(encodedLen + 2);
        result[0] = "d";
        result[1] = "a";
        
        uint256 i = 0;
        uint256 j = 2;
        while (i < data.length) {
            uint256 val = uint256(uint8(data[i]));
            i++;
            if (i < data.length) {
                val = (val << 8) | uint256(uint8(data[i]));
                i++;
                if (i < data.length) {
                    val = (val << 8) | uint256(uint8(data[i]));
                    i++;
                    result[j+3] = table[val & 0x3F];
                    val >>= 6;
                    result[j+2] = table[val & 0x3F];
                    val >>= 6;
                    result[j+1] = table[val & 0x3F];
                    val >>= 6;
                    result[j] = table[val & 0x3F];
                } else {
                    result[j+3] = "=";
                    result[j+2] = table[val & 0x3F];
                    val >>= 6;
                    result[j+1] = table[val & 0x3F];
                    val >>= 6;
                    result[j] = table[val & 0x3F];
                }
            } else {
                result[j+3] = "=";
                result[j+2] = "=";
                result[j+1] = table[val & 0x3F];
                val >>= 6;
                result[j] = table[val & 0x3F];
            }
            j += 4;
        }
        return string(result);
    }
}
