// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../Orbit.sol";
import "../utils/Ownable.sol";

/**
 * @title UniversalReverseAdapter
 * @notice One-time integration contract for all TLDs to enable reverse resolution
 * @dev Maps addresses to their primary names across all TLDs
 */
contract UniversalReverseAdapter is Ownable {
    
    struct DomainInfo {
        string name;        // Full domain name (e.g., "alice.orbit")
        string tld;         // TLD (e.g., "orbit")
        uint256 timestamp;  // When it was set
        bool isPrimary;     // Is this the primary name
    }
    
    // State variables
    Orbit public immutable orbit;
    
    // Address to all their domains
    mapping(address => DomainInfo[]) public addressToDomains;
    
    // Address to primary domain index
    mapping(address => uint256) public primaryDomainIndex;
    
    // Quick lookup: address to primary name
    mapping(address => string) public primaryNames;
    
    // TLD registrars that can set names
    mapping(address => bool) public authorizedRegistrars;
    
    // Statistics
    uint256 public totalMappings;
    mapping(string => uint256) public tldCounts;
    
    // Events
    event NameSet(
        address indexed addr,
        string name,
        string tld,
        bool isPrimary
    );
    
    event PrimaryNameChanged(
        address indexed addr,
        string oldName,
        string newName
    );
    
    event NameRemoved(
        address indexed addr,
        string name
    );
    
    event RegistrarAuthorized(
        address indexed registrar,
        bool authorized
    );
    
    modifier onlyAuthorizedRegistrar() {
        require(authorizedRegistrars[msg.sender], "Not authorized registrar");
        _;
    }
    
    constructor(Orbit _orbit) {
        orbit = _orbit;
    }
    
    /**
     * @notice Set a reverse name mapping (called by registrars)
     * @param addr The address to map
     * @param name The full domain name
     * @param tld The TLD part
     * @param makePrimary Whether to make this the primary name
     */
    function setName(
        address addr,
        string calldata name,
        string calldata tld,
        bool makePrimary
    ) external onlyAuthorizedRegistrar {
        // Check if this name already exists for the address
        bool exists = false;
        uint256 existingIndex;
        
        DomainInfo[] storage domains = addressToDomains[addr];
        for (uint256 i = 0; i < domains.length; i++) {
            if (keccak256(bytes(domains[i].name)) == keccak256(bytes(name))) {
                exists = true;
                existingIndex = i;
                break;
            }
        }
        
        if (!exists) {
            // Add new domain
            domains.push(DomainInfo({
                name: name,
                tld: tld,
                timestamp: block.timestamp,
                isPrimary: false
            }));
            
            totalMappings++;
            tldCounts[tld]++;
            
            if (makePrimary || domains.length == 1) {
                _setPrimary(addr, domains.length - 1);
            }
        } else if (makePrimary) {
            // Update existing to be primary
            _setPrimary(addr, existingIndex);
        }
        
        emit NameSet(addr, name, tld, makePrimary);
    }
    
    /**
     * @notice User can set their primary name from their registered names
     */
    function setPrimaryName(uint256 index) external {
        DomainInfo[] storage domains = addressToDomains[msg.sender];
        require(index < domains.length, "Invalid index");
        
        _setPrimary(msg.sender, index);
    }
    
    /**
     * @notice Internal function to set primary name
     */
    function _setPrimary(address addr, uint256 index) private {
        DomainInfo[] storage domains = addressToDomains[addr];
        
        // Clear old primary
        uint256 oldIndex = primaryDomainIndex[addr];
        if (oldIndex < domains.length) {
            domains[oldIndex].isPrimary = false;
        }
        
        // Set new primary
        domains[index].isPrimary = true;
        primaryDomainIndex[addr] = index;
        
        string memory oldName = primaryNames[addr];
        string memory newName = domains[index].name;
        primaryNames[addr] = newName;
        
        emit PrimaryNameChanged(addr, oldName, newName);
    }
    
    /**
     * @notice Remove a name mapping (called by registrars)
     */
    function removeName(
        address addr,
        string calldata name
    ) external onlyAuthorizedRegistrar {
        DomainInfo[] storage domains = addressToDomains[addr];
        
        for (uint256 i = 0; i < domains.length; i++) {
            if (keccak256(bytes(domains[i].name)) == keccak256(bytes(name))) {
                string memory tld = domains[i].tld;
                bool wasPrimary = domains[i].isPrimary;
                
                // Remove by swapping with last element
                domains[i] = domains[domains.length - 1];
                domains.pop();
                
                totalMappings--;
                tldCounts[tld]--;
                
                // If removed name was primary, set new primary if any left
                if (wasPrimary) {
                    if (domains.length > 0) {
                        _setPrimary(addr, 0);
                    } else {
                        delete primaryNames[addr];
                        delete primaryDomainIndex[addr];
                    }
                }
                
                emit NameRemoved(addr, name);
                break;
            }
        }
    }
    
    /**
     * @notice Get primary name for an address
     */
    function getName(address addr) external view returns (string memory) {
        return primaryNames[addr];
    }
    
    /**
     * @notice Get all domains for an address
     */
    function getAllNames(address addr) 
        external 
        view 
        returns (DomainInfo[] memory) 
    {
        return addressToDomains[addr];
    }
    
    /**
     * @notice Get specific domain info
     */
    function getDomainInfo(address addr, uint256 index) 
        external 
        view 
        returns (
            string memory name,
            string memory tld,
            uint256 timestamp,
            bool isPrimary
        ) 
    {
        require(index < addressToDomains[addr].length, "Invalid index");
        DomainInfo memory domain = addressToDomains[addr][index];
        return (domain.name, domain.tld, domain.timestamp, domain.isPrimary);
    }
    
    /**
     * @notice Check if address has any names
     */
    function hasName(address addr) external view returns (bool) {
        return addressToDomains[addr].length > 0;
    }
    
    /**
     * @notice Get count of domains for an address
     */
    function getNameCount(address addr) external view returns (uint256) {
        return addressToDomains[addr].length;
    }
    
    /**
     * @notice Authorize a registrar to set names
     */
    function authorizeRegistrar(address registrar, bool authorized) 
        external 
        onlyOwner 
    {
        authorizedRegistrars[registrar] = authorized;
        emit RegistrarAuthorized(registrar, authorized);
    }
    
    /**
     * @notice Batch authorize registrars
     */
    function batchAuthorizeRegistrars(
        address[] calldata registrars,
        bool authorized
    ) external onlyOwner {
        for (uint256 i = 0; i < registrars.length; i++) {
            authorizedRegistrars[registrars[i]] = authorized;
            emit RegistrarAuthorized(registrars[i], authorized);
        }
    }
    
    /**
     * @notice Get statistics for a TLD
     */
    function getTLDStats(string calldata tld) 
        external 
        view 
        returns (uint256) 
    {
        return tldCounts[tld];
    }
    
    /**
     * @notice Resolve address to primary name (for integration)
     * @dev Standard interface for wallets and dApps
     */
    function resolve(address addr) external view returns (string memory) {
        return primaryNames[addr];
    }
    
    /**
     * @notice Batch resolve addresses
     */
    function batchResolve(address[] calldata addresses) 
        external 
        view 
        returns (string[] memory) 
    {
        string[] memory names = new string[](addresses.length);
        for (uint256 i = 0; i < addresses.length; i++) {
            names[i] = primaryNames[addresses[i]];
        }
        return names;
    }
    
    /**
     * @notice Search for domains by partial match (helper function)
     */
    function searchDomains(string calldata) 
        external 
        pure 
        returns (address[] memory, string[] memory) 
    {
        // This is a simplified search - in production, this would be done off-chain
        // Returns empty arrays as placeholder
        address[] memory addresses = new address[](0);
        string[] memory names = new string[](0);
        
        // Note: This is gas-intensive and should be limited or done off-chain
        // Included here for demonstration purposes
        
        return (addresses, names);
    }
}