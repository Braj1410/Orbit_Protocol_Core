// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "./IPriceOracle.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../utils/StringUtils.sol";

/**
 * @title OrbitPriceOracle
 * @notice Price oracle for domain names using native CRO currency with governance controls
 * @dev Implements length-based pricing with configurable rates and price change limits
 */
contract OrbitPriceOracle is Initializable, PausableUpgradeable, UUPSUpgradeable, IPriceOracle, OwnableUpgradeable {
    using StringUtils for *;

    // Prices in wei (CRO) per year
    uint256 public price1Letter;  // 1000 CRO per year
    uint256 public price2Letter ;   // 500 CRO per year
    uint256 public price3Letter ;   // 100 CRO per year
    uint256 public price4Letter ;    // 50 CRO per year
    uint256 public price5Letter;    // 10 CRO per year

    // Price change limits (50% max change per day)
    uint256 public constant MAX_PRICE_INCREASE = 150; // 150% = 50% increase
    uint256 public constant MIN_PRICE_DECREASE = 67;  // 67% = 33% decrease
    uint256 public constant PRICE_CHANGE_COOLDOWN = 24 hours;
    
    // Track last price changes
    mapping(uint256 => uint256) public lastPriceChange; // 1=1letter, 2=2letter, etc.
    mapping(uint256 => uint256) public previousPrices;
    
    // Emergency price freeze
    bool public pricesFrozen;
    uint256 public priceFreezeInitiated;
    uint256 public constant MAX_FREEZE_DURATION = 7 days;

    event PricesUpdated(
        uint256 price1Letter,
        uint256 price2Letter,
        uint256 price3Letter,
        uint256 price4Letter,
        uint256 price5Letter
    );
    
    event PriceChangeBlocked(
        uint256 indexed priceLevel,
        uint256 oldPrice,
        uint256 newPrice,
        string reason
    );
    
    event PricesFrozen(address indexed initiator, string reason);
    event PricesUnfrozen(address indexed initiator);

    function initialize(uint256 p1,uint256 p2,uint256 p3,uint256 p4,uint256 p5,bool prices_frozen) public initializer {
        __Pausable_init();
        __Ownable_init(msg.sender);
        // Initialize previous prices
        previousPrices[1] = p1;
        previousPrices[2] = p2;
        previousPrices[3] = p3;
        previousPrices[4] = p4;
        previousPrices[5] = p5;

        price1Letter = p1;
        price2Letter = p2;
        price3Letter = p3;
        price4Letter = p4;
        price5Letter = p5;

        pricesFrozen = prices_frozen;
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyOwner
        override
    {}

    modifier onlyGovernance() {
        require(owner() == msg.sender, "not governance");
        _;
    }

    /**
     * @notice Calculate the price for a name
     * @param name The name to price
     * @param duration How long to register for (in seconds)
     * @return Price structure with base price in CRO
     */
    function price(
        string calldata name,
        uint256, // expires - not used in this implementation
        uint256 duration
    ) external view override returns (IPriceOracle.Price memory) {
        uint256 len = name.strlen();
        uint256 basePrice;

        if (len == 1) {
            basePrice = price1Letter;
        } else if (len == 2) {
            basePrice = price2Letter;
        } else if (len == 3) {
            basePrice = price3Letter;
        } else if (len == 4) {
            basePrice = price4Letter;
        } else {
            basePrice = price5Letter;
        }

        // Calculate price based on duration (price is per year)
        basePrice = (basePrice * duration) / 365 days;

        return IPriceOracle.Price({
            base: basePrice,
            premium: 0  // No premium in this implementation
        });
    }

    /**
     * @notice Update prices with governance controls and limits
     * @param _price1 New price for 1-letter names (in wei)
     * @param _price2 New price for 2-letter names (in wei)
     * @param _price3 New price for 3-letter names (in wei)
     * @param _price4 New price for 4-letter names (in wei)
     * @param _price5 New price for 5+ letter names (in wei)
     */
    function setPrices(
        uint256 _price1,
        uint256 _price2,
        uint256 _price3,
        uint256 _price4,
        uint256 _price5
    ) external onlyGovernance whenNotPaused {
        require(!pricesFrozen, "CROPriceOracle: prices are frozen");
        
        // Validate each price change
        _validatePriceChange(1, price1Letter, _price1);
        _validatePriceChange(2, price2Letter, _price2);
        _validatePriceChange(3, price3Letter, _price3);
        _validatePriceChange(4, price4Letter, _price4);
        _validatePriceChange(5, price5Letter, _price5);
        
        // Update previous prices before changing
        previousPrices[1] = price1Letter;
        previousPrices[2] = price2Letter;
        previousPrices[3] = price3Letter;
        previousPrices[4] = price4Letter;
        previousPrices[5] = price5Letter;
        
        // Update prices
        price1Letter = _price1;
        price2Letter = _price2;
        price3Letter = _price3;
        price4Letter = _price4;
        price5Letter = _price5;
        
        // Update timestamps
        uint256 currentTime = block.timestamp;
        lastPriceChange[1] = currentTime;
        lastPriceChange[2] = currentTime;
        lastPriceChange[3] = currentTime;
        lastPriceChange[4] = currentTime;
        lastPriceChange[5] = currentTime;

        emit PricesUpdated(_price1, _price2, _price3, _price4, _price5);
    }
    
    /**
     * @notice Update individual price level with governance controls
     */
    function setPriceLevel(
        uint256 level,
        uint256 newPrice
    ) external onlyGovernance whenNotPaused {
        require(!pricesFrozen, "CROPriceOracle: prices are frozen");
        require(level >= 1 && level <= 5, "CROPriceOracle: invalid price level");
        
        uint256 currentPrice;
        if (level == 1) currentPrice = price1Letter;
        else if (level == 2) currentPrice = price2Letter;
        else if (level == 3) currentPrice = price3Letter;
        else if (level == 4) currentPrice = price4Letter;
        else currentPrice = price5Letter;
        
        _validatePriceChange(level, currentPrice, newPrice);
        
        // Update previous price
        previousPrices[level] = currentPrice;
        
        // Update price
        if (level == 1) price1Letter = newPrice;
        else if (level == 2) price2Letter = newPrice;
        else if (level == 3) price3Letter = newPrice;
        else if (level == 4) price4Letter = newPrice;
        else price5Letter = newPrice;
        
        // Update timestamp
        lastPriceChange[level] = block.timestamp;
        
        emit PricesUpdated(price1Letter, price2Letter, price3Letter, price4Letter, price5Letter);
    }
    
    /**
     * @notice Validate price change against limits and cooldowns
     */
    function _validatePriceChange(
        uint256 level,
        uint256 oldPrice,
        uint256 newPrice
    ) private view {
        require(newPrice > 0, "CROPriceOracle: price cannot be zero");
        
        // Check cooldown period
        uint256 lastChange = lastPriceChange[level];
        require(
            block.timestamp >= lastChange + PRICE_CHANGE_COOLDOWN,
            "CROPriceOracle: price change cooldown not met"
        );
        
        // Check price change limits (50% max change)
        if (newPrice > oldPrice) {
            // Price increase - max 50% increase
            uint256 maxAllowedPrice = (oldPrice * MAX_PRICE_INCREASE) / 100;
            require(newPrice <= maxAllowedPrice, "CROPriceOracle: price increase too large");
        } else if (newPrice < oldPrice) {
            // Price decrease - max 33% decrease
            uint256 minAllowedPrice = (oldPrice * MIN_PRICE_DECREASE) / 100;
            require(newPrice >= minAllowedPrice, "CROPriceOracle: price decrease too large");
        }
    }
    
    /**
     * @notice Emergency freeze all price changes
     */
    function freezePrices(string memory reason) external onlyGovernance {
        require(!pricesFrozen, "CROPriceOracle: already frozen");
        
        pricesFrozen = true;
        priceFreezeInitiated = block.timestamp;
        
        emit PricesFrozen(_msgSender(), reason);
    }
    
    /**
     * @notice Unfreeze price changes
     */
    function unfreezePrices() external onlyGovernance {
        require(pricesFrozen, "CROPriceOracle: not frozen");
        
        pricesFrozen = false;
        priceFreezeInitiated = 0;
        
        emit PricesUnfrozen(_msgSender());
    }
    
    /**
     * @notice Auto-unfreeze after maximum duration
     */
    function autoUnfreezePrices() external {
        require(pricesFrozen, "CROPriceOracle: not frozen");
        require(
            block.timestamp >= priceFreezeInitiated + MAX_FREEZE_DURATION,
            "CROPriceOracle: freeze duration not met"
        );
        
        pricesFrozen = false;
        priceFreezeInitiated = 0;
        
        emit PricesUnfrozen(address(0)); // address(0) indicates auto-unfreeze
    }
    
    /**
     * @notice Get price change information for a level
     */
    function getPriceChangeInfo(uint256 level)
        external
        view
        returns (
            uint256 currentPrice,
            uint256 previousPrice,
            uint256 lastChangeTime,
            uint256 cooldownRemaining,
            bool canChange
        )
    {
        require(level >= 1 && level <= 5, "CROPriceOracle: invalid level");
        
        if (level == 1) currentPrice = price1Letter;
        else if (level == 2) currentPrice = price2Letter;
        else if (level == 3) currentPrice = price3Letter;
        else if (level == 4) currentPrice = price4Letter;
        else currentPrice = price5Letter;
        
        previousPrice = previousPrices[level];
        lastChangeTime = lastPriceChange[level];
        
        uint256 elapsed = block.timestamp - lastChangeTime;
        cooldownRemaining = elapsed >= PRICE_CHANGE_COOLDOWN ? 0 : PRICE_CHANGE_COOLDOWN - elapsed;
        canChange = !pricesFrozen && cooldownRemaining == 0;
    }
    
    /**
     * @notice Get all current prices and status
     */
    function getPriceStatus()
        external
        view
        returns (
            uint256[5] memory prices,
            uint256[5] memory previousPricesArray,
            uint256[5] memory lastChanges,
            bool frozen,
            uint256 freezeTimeRemaining
        )
    {
        prices[0] = price1Letter;
        prices[1] = price2Letter;
        prices[2] = price3Letter;
        prices[3] = price4Letter;
        prices[4] = price5Letter;
        
        previousPricesArray[0] = previousPrices[1];
        previousPricesArray[1] = previousPrices[2];
        previousPricesArray[2] = previousPrices[3];
        previousPricesArray[3] = previousPrices[4];
        previousPricesArray[4] = previousPrices[5];
        
        lastChanges[0] = lastPriceChange[1];
        lastChanges[1] = lastPriceChange[2];
        lastChanges[2] = lastPriceChange[3];
        lastChanges[3] = lastPriceChange[4];
        lastChanges[4] = lastPriceChange[5];
        
        frozen = pricesFrozen;
        
        if (pricesFrozen) {
            uint256 elapsed = block.timestamp - priceFreezeInitiated;
            freezeTimeRemaining = elapsed >= MAX_FREEZE_DURATION ? 0 : MAX_FREEZE_DURATION - elapsed;
        }
    }
    
    /**
     * @notice Calculate maximum allowed price change for a level
     */
    function getMaxAllowedPriceChange(uint256 level)
        external
        view
        returns (uint256 maxIncrease, uint256 maxDecrease)
    {
        require(level >= 1 && level <= 5, "CROPriceOracle: invalid level");
        
        uint256 currentPrice;
        if (level == 1) currentPrice = price1Letter;
        else if (level == 2) currentPrice = price2Letter;
        else if (level == 3) currentPrice = price3Letter;
        else if (level == 4) currentPrice = price4Letter;
        else currentPrice = price5Letter;
        
        maxIncrease = (currentPrice * MAX_PRICE_INCREASE) / 100;
        maxDecrease = (currentPrice * MIN_PRICE_DECREASE) / 100;
    }

    /**
     * @notice Get the premium for a name (always 0 in this implementation)
     */
    function premium(
        string calldata,
        uint256,
        uint256
    ) external pure returns (uint256) {
        return 0;
    }

    function supportsInterface(bytes4 interfaceID)
        public
        pure
        returns (bool)
    {
        return
            interfaceID == type(IPriceOracle).interfaceId ||
            interfaceID == 0x01ffc9a7; // ERC165
    }
}
