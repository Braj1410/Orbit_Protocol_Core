// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./TLDStorage.sol";
import "./TLDRegistrarFactory.sol";
import "./ITLDFactory.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract TLDManager is Initializable, ERC721Upgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable, ITLDFactory {
    
    TLDStorage public storageModule;
    TLDRegistrarFactory public registrarFactory;
    
    uint256 public tldFee;
    uint256 public constant MIN_DURATION = 365 days;
    uint256 public constant GRACE_PERIOD = 30 days;
    uint256 private tokenIdCounter;
    
    mapping(address => uint256) public pendingWithdrawals;
    
    event TLDCreated(uint256 indexed tokenId, string name, address owner);
    event TLDRenewed(uint256 indexed tokenId, uint256 newExpiry);
    event TLDFeeChanged(uint256 newFee);
    
    function initialize(
        address _storage,
        address _registrar
    ) public initializer {
        __ERC721_init("Orbit TLD", "TLD");
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        
        storageModule = TLDStorage(_storage);
        registrarFactory = TLDRegistrarFactory(_registrar);
        tldFee = 1000 ether;
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyOwner
        override
    {}

    function setTldFee(uint256 _newFee) external onlyOwner {
        tldFee = _newFee;
        emit TLDFeeChanged(_newFee);
    }
    
    function createTLD(
        string calldata name,
        uint256 regFee,
        uint256 duration
    ) external payable returns (uint256) {
        require(duration >= MIN_DURATION, "Too short");
        require(msg.value >= tldFee, "Low fee");
        require(bytes(name).length >= 2 && bytes(name).length <= 63, "Bad length");
        
        string memory lower = _lower(name);
        require(storageModule.isNameAvailable(lower), "Taken");
        
        uint256 id = ++tokenIdCounter;
        
        address registrar = registrarFactory.deployRegistrar(id, lower, msg.sender);
        
        storageModule.createTLD(
            id, lower, msg.sender, registrar, regFee,
            50, block.timestamp + duration, tldFee
        );
        
        pendingWithdrawals[owner()] += msg.value;
        
        _safeMint(msg.sender, id);
        emit TLDCreated(id, lower, msg.sender);
        return id;
    }
    
    function renewTLD(uint256 id, uint256 duration) external payable {
        require(ownerOf(id) == msg.sender, "Not owner");
        require(duration >= MIN_DURATION, "Too short");
        require(msg.value >= tldFee, "Low fee");
        
        TLDStorage.TLD memory tld = storageModule.getTLD(id);
        uint256 newExpiry = tld.expirationTime + duration;
        
        storageModule.updateTLDExpiration(id, newExpiry);
        pendingWithdrawals[owner()] += msg.value;
        
        emit TLDRenewed(id, newExpiry);
    }

    function withdraw() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "Nothing to withdraw");
        
        pendingWithdrawals[msg.sender] = 0;
        
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Transfer failed");
    }
    
    function getTLD(uint256 id) external view override returns (
        string memory name,
        address owner,
        address registrar,
        uint256 registrationFee,
        uint256 totalRegistrations,
        uint256 totalRevenue,
        bool isActive
    ) {
        TLDStorage.TLD memory tld = storageModule.getTLD(id);
        return (
            tld.name, tld.owner, tld.registrar,
            tld.registrationFee, tld.totalRegistrations,
            tld.totalRevenue, tld.isActive
        );
    }
    
    function _update(address to, uint256 id, address auth) internal override returns (address) {
        address from = super._update(to, id, auth);
        if (from != address(0) && to != address(0)) {
            // This is a transfer (not mint or burn)
            storageModule.updateTLDOwner(id, to);
            registrarFactory.transferRegistrarOwnership(id, to);
        }
        return from;
    }
    
    function _lower(string calldata s) private pure returns (string memory) {
        bytes memory b = bytes(s);
        bytes memory r = new bytes(b.length);
        for (uint i = 0; i < b.length; i++) {
            uint8 c = uint8(b[i]);
            r[i] = (c >= 65 && c <= 90) ? bytes1(c + 32) : b[i];
        }
        return string(r);
    }

    function distributeRevenue(uint256, uint256) external payable override {
        // This is a placeholder to satisfy the interface
    }
}
