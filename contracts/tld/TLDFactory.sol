// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./TLDStorage.sol";
import "./TLDAuctionModule.sol";
import "./TLDRevenueModule.sol";
import "./TLDRegistrarFactory.sol";
import "./ITLDFactory.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title TLDFactory
 * @notice Main TLD factory that uses all modules
 * @dev Optimized to stay under 24KB by using external modules
 */
import "hardhat/console.sol";

contract TLDFactory is
    Initializable,
    ERC721Upgradeable,
    OwnableUpgradeable,
    ITLDFactory,
    UUPSUpgradeable
{
    // External modules - all the heavy lifting is done here
    TLDStorage public storageModule;
    TLDAuctionModule public auctionModule;
    TLDRevenueModule public revenueModule;
    TLDRegistrarFactory public registrarFactory;

    uint256 public tldFee;
    uint256 public MIN_DURATION;
    uint256 public GRACE_PERIOD;
    uint256 private tokenIdCounter;

    event TLDCreated(uint256 indexed tokenId, string name, address owner);
    event TLDRenewed(uint256 indexed tokenId, uint256 newExpiry);
    event TLDExpired(uint256 indexed tokenId);

    function initialize(
        address _storage,
        address _auction,
        address _revenue,
        address _registrar
    ) public initializer {
        __ERC721_init("Orbit TLD", "TLD");
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        storageModule = TLDStorage(_storage);
        auctionModule = TLDAuctionModule(_auction);
        revenueModule = TLDRevenueModule(_revenue);
        registrarFactory = TLDRegistrarFactory(_registrar);
        tldFee = 1 ether;
        MIN_DURATION = 365 days;
        GRACE_PERIOD = 30 days;
    }

    /**
     * @notice Create a new TLD
     */
    function createTLD(
        string calldata name,
        uint256 regFee,
        uint256 duration
    ) external payable returns (uint256) {
        require(duration >= MIN_DURATION, "Too short");
        require(msg.value >= tldFee, "Low fee");
        require(
            bytes(name).length >= 2 && bytes(name).length <= 63,
            "Bad length"
        );

        string memory lower = _lower(name);
        require(storageModule.isNameAvailable(lower), "Taken");

        uint256 id = ++tokenIdCounter;

        // // Deploy registrar via factory module
        address registrar = registrarFactory.deployRegistrar(
            id,
            lower,
            msg.sender
        );

        console.log(registrar);
        // Store in storage module
        storageModule.createTLD(
            id,
            lower,
            msg.sender,
            registrar,
            regFee,
            50,
            block.timestamp + duration,
            tldFee
        );

        // Process payment via revenue module
        revenueModule.processCreationFee{value: msg.value}(msg.value);

        _safeMint(msg.sender, id);
        emit TLDCreated(id, lower, msg.sender);
        console.log("ID", id);
        return id;
    }

    /**
     * @notice Renew TLD
     */
    function renewTLD(uint256 id, uint256 duration) external payable {
        require(ownerOf(id) == msg.sender, "Not owner");
        require(duration >= MIN_DURATION, "Too short");
        require(msg.value >= tldFee, "Low fee");

        TLDStorage.TLD memory tld = storageModule.getTLD(id);
        uint256 newExpiry = tld.expirationTime + duration;

        storageModule.updateTLDExpiration(id, newExpiry);
        revenueModule.processRenewalFee{value: msg.value}(id);

        emit TLDRenewed(id, newExpiry);
    }

    /**
     * @notice Check and process expiration
     */
    function checkExpiry(uint256 id) external {
        TLDStorage.TLD memory tld = storageModule.getTLD(id);

        if (
            block.timestamp > tld.expirationTime + GRACE_PERIOD && tld.isActive
        ) {
            storageModule.setTLDActive(id, false);
            auctionModule.startAuction(id, tldFee);
            emit TLDExpired(id);
        }
    }

    /**
     * @notice Bid on expired TLD
     */
    function bid(uint256 id) external payable {
        auctionModule.bid{value: msg.value}(id);
    }

    /**
     * @notice Claim won auction
     */
    function claimAuction(uint256 id) external {
        (address winner, uint256 price) = auctionModule.settleAuction(id);
        require(winner == msg.sender, "Not winner");

        _transfer(ownerOf(id), winner, id);
        storageModule.updateTLDOwner(id, winner);
        storageModule.setTLDActive(id, true);
        storageModule.updateTLDExpiration(id, block.timestamp + MIN_DURATION);

        if (price > 0) {
            revenueModule.processCreationFee{value: price}(price);
        }
    }

    /**
     * @notice Withdraw revenue
     */
    function withdraw() external {
        revenueModule.withdraw();
    }

    /**
     * @notice Withdraw auction returns
     */
    function withdrawReturns() external {
        auctionModule.withdraw();
    }

    // ITLDFactory implementation
    function distributeRevenue(
        uint256 tokenId,
        uint256
    ) external payable override {
        address registrar = registrarFactory.getRegistrar(tokenId);
        require(msg.sender == registrar, "Only registrar");
        revenueModule.distributeRevenue{value: msg.value}(tokenId, msg.value);
    }

    function getTLD(
        uint256 id
    )
        external
        view
        override
        returns (
            string memory name,
            address owner,
            address registrar,
            uint256 registrationFee,
            uint256 totalRegistrations,
            uint256 totalRevenue,
            bool isActive
        )
    {
        TLDStorage.TLD memory tld = storageModule.getTLD(id);
        return (
            tld.name,
            tld.owner,
            tld.registrar,
            tld.registrationFee,
            tld.totalRegistrations,
            tld.totalRevenue,
            tld.isActive
        );
    }

    function _update(
        address to,
        uint256 id,
        address auth
    ) internal override returns (address) {
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

    /// @dev Authorization for UUPS upgrades
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
