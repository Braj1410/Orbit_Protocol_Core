// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./Orbit.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title SubdomainRegistrar
 * @notice Allows domain owners to create and manage subdomains
 * @dev Enables alice.orbit to create bob.alice.orbit, dao.alice.orbit, etc.
 */
contract SubdomainRegistrar is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    
    Orbit public orbit;
    
    struct Subdomain {
        string name;
        address owner;
        address resolver;
        uint256 price;          // Price to register (0 = free)
        bool isForSale;
        uint256 expiresAt;      // 0 = permanent
        bytes32 parentNode;
        bool exists;
    }
    
    struct SubdomainConfig {
        bool publicRegistration;  // Anyone can register
        uint256 defaultPrice;     // Default price for subdomains
        uint256 defaultDuration;  // Default duration (0 = permanent)
        address paymentReceiver;  // Where payments go
        bool requiresApproval;    // Owner must approve each registration
        uint256 maxSubdomains;    // Maximum allowed (0 = unlimited)
        uint256 currentCount;     // Current subdomain count
    }
    
    // Mapping from parent node to subdomain configurations
    mapping(bytes32 => SubdomainConfig) public subdomainConfigs;
    
    // Mapping from subdomain node to subdomain info
    mapping(bytes32 => Subdomain) public subdomains;
    
    
    // Pending registrations (for approval-based systems)
    mapping(bytes32 => mapping(string => address)) public pendingRegistrations;
    
    // Revenue tracking
    mapping(address => uint256) public pendingWithdrawals;
    address public protocolFeeWallet;
    uint256 public protocolFeePercent;
    
    // Events
    event SubdomainConfigured(
        bytes32 indexed parentNode,
        bool publicRegistration,
        uint256 price,
        uint256 duration
    );
    
    event SubdomainRegistered(
        bytes32 indexed parentNode,
        bytes32 indexed subNode,
        string label,
        address indexed owner,
        uint256 price,
        uint256 expiresAt
    );
    
    event SubdomainTransferred(
        bytes32 indexed subNode,
        address indexed from,
        address indexed to
    );
    
    event SubdomainDeleted(
        bytes32 indexed parentNode,
        bytes32 indexed subNode,
        string label
    );
    
    event SubdomainRenewed(
        bytes32 indexed subNode,
        uint256 newExpiry
    );
    
    event SubdomainListed(
        bytes32 indexed subNode,
        uint256 price
    );
    
    event RegistrationRequested(
        bytes32 indexed parentNode,
        string label,
        address indexed requester
    );
    
    event RegistrationApproved(
        bytes32 indexed parentNode,
        string label,
        address indexed owner
    );
    
    modifier onlyDomainOwner(bytes32 node) {
        require(
            orbit.owner(node) == msg.sender,
            "Not domain owner"
        );
        _;
    }
    
    modifier onlySubdomainOwner(bytes32 subNode) {
        require(
            subdomains[subNode].owner == msg.sender,
            "Not subdomain owner"
        );
        _;
    }
    
    function initialize(Orbit _orbit) public initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        orbit = _orbit;
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyOwner
        override
    {}
    
    /**
     * @notice Configure subdomain settings for a domain
     * @param parentNode The parent domain node
     * @param publicRegistration Allow public registration
     * @param defaultPrice Price for subdomain registration
     * @param defaultDuration Duration for subdomains (0 = permanent)
     * @param requiresApproval Require owner approval for each registration
     * @param maxSubdomains Maximum number of subdomains (0 = unlimited)
     */
    function configureSubdomains(
        bytes32 parentNode,
        bool publicRegistration,
        uint256 defaultPrice,
        uint256 defaultDuration,
        bool requiresApproval,
        uint256 maxSubdomains
    ) external onlyDomainOwner(parentNode) {
        SubdomainConfig storage config = subdomainConfigs[parentNode];
        
        config.publicRegistration = publicRegistration;
        config.defaultPrice = defaultPrice;
        config.defaultDuration = defaultDuration;
        config.paymentReceiver = msg.sender;
        config.requiresApproval = requiresApproval;
        config.maxSubdomains = maxSubdomains;
        
        emit SubdomainConfigured(
            parentNode,
            publicRegistration,
            defaultPrice,
            defaultDuration
        );
    }
    
    /**
     * @notice Register a subdomain
     * @param parentNode The parent domain node
     * @param label The subdomain label (e.g., "alice" for alice.example.orbit)
     * @param owner The owner of the subdomain
     * @param resolver The resolver address
     */
    function registerSubdomain(
        bytes32 parentNode,
        string calldata label,
        address owner,
        address resolver
    ) external payable nonReentrant {
        // Input validation
        require(bytes(label).length >= 3, "Label too short");
        require(bytes(label).length <= 63, "Label too long");
        require(_isValidLabel(label), "Invalid label characters");
        require(owner != address(0), "Invalid owner address");
        
        SubdomainConfig storage config = subdomainConfigs[parentNode];
        
        // Check if registration is allowed
        if (!config.publicRegistration) {
            require(
                orbit.owner(parentNode) == msg.sender,
                "Registration not public"
            );
        }
        
        // Check max subdomains limit
        if (config.maxSubdomains > 0) {
            require(
                config.currentCount < config.maxSubdomains,
                "Max subdomains reached"
            );
        }
        
        // Check payment
        if (config.defaultPrice > 0 && msg.sender != orbit.owner(parentNode)) {
            require(msg.value >= config.defaultPrice, "Insufficient payment");
            
            uint256 protocolFee = (config.defaultPrice * protocolFeePercent) / 100;
            uint256 ownerShare = config.defaultPrice - protocolFee;
            
            pendingWithdrawals[config.paymentReceiver] += ownerShare;
            pendingWithdrawals[protocolFeeWallet] += protocolFee;
            
            // Refund excess safely
            if (msg.value > config.defaultPrice) {
                uint256 refund = msg.value - config.defaultPrice;
                (bool success, ) = payable(msg.sender).call{value: refund}("");
                require(success, "Refund failed");
            }
        }
        
        // Calculate subdomain node
        bytes32 subNode = keccak256(abi.encodePacked(parentNode, keccak256(bytes(label))));
        
        // Check if subdomain already exists
        require(!subdomains[subNode].exists, "Subdomain already exists");
        
        // Handle approval-based registration
        if (config.requiresApproval && msg.sender != orbit.owner(parentNode)) {
            pendingRegistrations[parentNode][label] = owner;
            emit RegistrationRequested(parentNode, label, owner);
            return;
        }
        
        // Register the subdomain
        _registerSubdomain(parentNode, label, owner, resolver, config.defaultDuration);
    }
    
    /**
     * @notice Internal function to register subdomain
     */
    function _registerSubdomain(
        bytes32 parentNode,
        string memory label,
        address owner,
        address resolver,
        uint256 duration
    ) internal {
        bytes32 labelHash = keccak256(bytes(label));
        bytes32 subNode = keccak256(abi.encodePacked(parentNode, labelHash));
        
        // Set subdomain in Orbit registry
        orbit.setSubnodeRecord(parentNode, labelHash, owner, resolver, 0);
        
        // Calculate expiry
        uint256 expiresAt = 0;
        if (duration > 0) {
            expiresAt = block.timestamp + duration;
        }
        
        // Store subdomain info
        subdomains[subNode] = Subdomain({
            name: label,
            owner: owner,
            resolver: resolver,
            price: 0,
            isForSale: false,
            expiresAt: expiresAt,
            parentNode: parentNode,
            exists: true
        });
        
        // Update subdomain count
        subdomainConfigs[parentNode].currentCount++;
        
        emit SubdomainRegistered(
            parentNode,
            subNode,
            label,
            owner,
            subdomainConfigs[parentNode].defaultPrice,
            expiresAt
        );
    }
    
    /**
     * @notice Approve a pending subdomain registration
     */
    function approveRegistration(
        bytes32 parentNode,
        string calldata label,
        address resolver
    ) external onlyDomainOwner(parentNode) {
        address requester = pendingRegistrations[parentNode][label];
        require(requester != address(0), "No pending registration");
        
        delete pendingRegistrations[parentNode][label];
        
        _registerSubdomain(
            parentNode,
            label,
            requester,
            resolver,
            subdomainConfigs[parentNode].defaultDuration
        );
        
        emit RegistrationApproved(parentNode, label, requester);
    }
    
    /**
     * @notice Transfer subdomain ownership
     */
    function transferSubdomain(
        bytes32 subNode,
        address newOwner
    ) external onlySubdomainOwner(subNode) {
        address oldOwner = subdomains[subNode].owner;
        subdomains[subNode].owner = newOwner;
        
        // Update Orbit registry
        orbit.setOwner(subNode, newOwner);
        
        emit SubdomainTransferred(subNode, oldOwner, newOwner);
    }
    
    /**
     * @notice Delete a subdomain
     */
    function deleteSubdomain(
        bytes32 parentNode,
        string calldata label
    ) external onlyDomainOwner(parentNode) {
        bytes32 labelHash = keccak256(bytes(label));
        bytes32 subNode = keccak256(abi.encodePacked(parentNode, labelHash));
        
        require(subdomains[subNode].exists, "Subdomain does not exist");
        
        // Clear from Orbit registry
        orbit.setSubnodeOwner(parentNode, labelHash, address(0));
        
        // Delete subdomain data
        delete subdomains[subNode];
        
        // Update count
        subdomainConfigs[parentNode].currentCount--;
        
        emit SubdomainDeleted(parentNode, subNode, label);
    }
    
    /**
     * @notice Renew an expiring subdomain
     */
    function renewSubdomain(
        bytes32 subNode,
        uint256 additionalDuration
    ) external payable {
        Subdomain storage subdomain = subdomains[subNode];
        require(subdomain.exists, "Subdomain does not exist");
        require(subdomain.expiresAt > 0, "Subdomain is permanent");
        
        SubdomainConfig storage config = subdomainConfigs[subdomain.parentNode];
        
        // Check payment for renewal
        if (config.defaultPrice > 0 && msg.sender != orbit.owner(subdomain.parentNode)) {
            require(msg.value >= config.defaultPrice, "Insufficient payment");
            
            uint256 protocolFee = (config.defaultPrice * protocolFeePercent) / 100;
            uint256 ownerShare = config.defaultPrice - protocolFee;
            
            pendingWithdrawals[config.paymentReceiver] += ownerShare;
            pendingWithdrawals[protocolFeeWallet] += protocolFee;
            
            // Refund excess safely
            if (msg.value > config.defaultPrice) {
                uint256 refund = msg.value - config.defaultPrice;
                (bool success, ) = payable(msg.sender).call{value: refund}("");
                require(success, "Refund failed");
            }
        }
        
        // Extend expiry
        if (block.timestamp > subdomain.expiresAt) {
            // Already expired, start from now
            subdomain.expiresAt = block.timestamp + additionalDuration;
        } else {
            // Not expired, add to current expiry
            subdomain.expiresAt += additionalDuration;
        }
        
        emit SubdomainRenewed(subNode, subdomain.expiresAt);
    }
    
    /**
     * @notice List subdomain for sale
     */
    function listSubdomainForSale(
        bytes32 subNode,
        uint256 price
    ) external onlySubdomainOwner(subNode) {
        subdomains[subNode].isForSale = true;
        subdomains[subNode].price = price;
        
        emit SubdomainListed(subNode, price);
    }
    
    /**
     * @notice Buy a listed subdomain
     */
    function buySubdomain(bytes32 subNode) external payable nonReentrant {
        Subdomain storage subdomain = subdomains[subNode];
        require(subdomain.exists, "Subdomain does not exist");
        require(subdomain.isForSale, "Not for sale");
        require(msg.value >= subdomain.price, "Insufficient payment");
        
        address seller = subdomain.owner;
        
        // Transfer ownership
        subdomain.owner = msg.sender;
        subdomain.isForSale = false;
        
        // Update Orbit registry
        orbit.setOwner(subNode, msg.sender);
        
        // Handle payment
        pendingWithdrawals[seller] += subdomain.price;
        
        // Refund excess
        if (msg.value > subdomain.price) {
            (bool success, ) = payable(msg.sender).call{value: msg.value - subdomain.price}("");
            require(success, "SubdomainRegistrar: Refund failed");
        }
        
        emit SubdomainTransferred(subNode, seller, msg.sender);
    }
    
    /**
     * @notice Batch register multiple subdomains
     */
    function batchRegisterSubdomains(
        bytes32 parentNode,
        string[] calldata labels,
        address[] calldata owners,
        address resolver
    ) external onlyDomainOwner(parentNode) {
        require(labels.length == owners.length, "Mismatched arrays");
        
        SubdomainConfig storage config = subdomainConfigs[parentNode];
        
        for (uint i = 0; i < labels.length; i++) {
            _registerSubdomain(
                parentNode,
                labels[i],
                owners[i],
                resolver,
                config.defaultDuration
            );
        }
    }
    
    /**
     * @notice Get all subdomains for a parent node
     */
    
    /**
     * @notice Check if subdomain is available
     */
    function isAvailable(bytes32 parentNode, string calldata label) 
        external 
        view 
        returns (bool) 
    {
        bytes32 subNode = keccak256(abi.encodePacked(
            parentNode,
            keccak256(bytes(label))
        ));
        
        if (subdomains[subNode].exists) {
            // Check if expired
            if (subdomains[subNode].expiresAt > 0 && 
                block.timestamp > subdomains[subNode].expiresAt) {
                return true;
            }
            return false;
        }
        
        return true;
    }
    
    /**
     * @notice Withdraw accumulated funds
     */
    function withdraw() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "Nothing to withdraw");
        
        // CRITICAL: Set to 0 BEFORE external call to prevent reentrancy
        pendingWithdrawals[msg.sender] = 0;
        
        // Use call instead of transfer for better gas handling
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Transfer failed");
    }
    
    /**
     * @notice Update payment receiver for a domain's subdomains
     */
    function updatePaymentReceiver(
        bytes32 parentNode,
        address newReceiver
    ) external onlyDomainOwner(parentNode) {
        subdomainConfigs[parentNode].paymentReceiver = newReceiver;
    }

    function setProtocolFee(address _wallet, uint256 _percent) external onlyOwner {
        require(_percent <= 100, "Percent too high");
        protocolFeeWallet = _wallet;
        protocolFeePercent = _percent;
    }
    
    /**
     * @notice Emergency cleanup for expired subdomains
     */
    function cleanupExpiredSubdomain(bytes32 subNode) external {
        Subdomain storage subdomain = subdomains[subNode];
        require(subdomain.exists, "Subdomain does not exist");
        require(subdomain.expiresAt > 0, "Subdomain is permanent");
        require(block.timestamp > subdomain.expiresAt + 90 days, "Grace period not over");
        
        // Clear from Orbit registry
        orbit.setOwner(subNode, address(0));
        
        // Delete subdomain data
        delete subdomains[subNode];
        
        // Update count
        subdomainConfigs[subdomain.parentNode].currentCount--;
    }
    
    /**
     * @notice Validate label characters (alphanumeric and hyphen only)
     */
    function _isValidLabel(string memory label) internal pure returns (bool) {
        bytes memory b = bytes(label);
        
        // Check first and last char are not hyphens
        if (b[0] == 0x2d || b[b.length - 1] == 0x2d) return false;
        
        for (uint i = 0; i < b.length; i++) {
            bytes1 char = b[i];
            // Allow a-z
            if (char >= 0x61 && char <= 0x7a) continue;
            // Allow 0-9
            if (char >= 0x30 && char <= 0x39) continue;
            // Allow hyphen
            if (char == 0x2d) continue;
            // Invalid character
            return false;
        }
        
        return true;
    }
}
