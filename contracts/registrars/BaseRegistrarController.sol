//SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "./IBaseRegistrar.sol";
import "./IBaseRegistrarController.sol";
import "./IReverseRegistrar.sol";
import "../oracles/IPriceOracle.sol";
import "../utils/StringUtils.sol";
import "../utils/Blocklist.sol";
import "../tokens/IRevenueDistributor.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "../utils/Address.sol";

/**
 * @dev A base registrar controller for registering and renewing names with owner controls.
 */
abstract contract BaseRegistrarController is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, IBaseRegistrarController {
    using StringUtils for *;
    using Address for address;

    uint256 public constant MIN_REGISTRATION_DURATION = 28 days;
    string private constant ORBIT_LABEL = "orbit";
    bytes32 private constant ORBIT_NODE =
        0x93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae;
    uint256 public constant MIN_COMMITMENT_AGE = 300; // 5 minutes for better security
    uint256 public constant MAX_COMMITMENT_AGE = 24 * 60 * 60; // 24 hours

    IBaseRegistrar public registrar;

    IReverseRegistrar public reverseRegistrar;
    IPriceOracle public priceOracle;
    Blocklist public blocklist;
    IRevenueDistributor public revenueDistributor;
    bool public chanceRequired;

    mapping(bytes32 => uint256) public commitments;

    event NameRegistered(
        string name,
        bytes32 indexed label,
        address indexed owner,
        uint256 baseCost,
        uint256 premium,
        uint256 expires
    );

    event NameRenewed(
        string name,
        bytes32 indexed label,
        uint256 cost,
        uint256 expires
    );

    event ReverseRegistrarChanged(address indexed reverseRegistrar);

    event PriceOracleChanged(address indexed priceOracle);

    event BlocklistChanged(address indexed blocklist);

    event RevenueDistributorChanged(address indexed revenueDistributor);

    event ChanceRequiredChanged(bool required);

    function initialize(
        IBaseRegistrar _registrar,
        IPriceOracle _priceOracle,
        IReverseRegistrar _reverseRegistrar
    ) public virtual initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __Pausable_init();
        require(address(_registrar) != address(0), "BaseRegistrarController: registrar cannot be zero");
        require(address(_priceOracle) != address(0), "BaseRegistrarController: priceOracle cannot be zero");
        require(address(_reverseRegistrar) != address(0), "BaseRegistrarController: reverseRegistrar cannot be zero");
        registrar = _registrar;
        priceOracle = _priceOracle;
        reverseRegistrar = _reverseRegistrar;
        chanceRequired = false;
    }

    function rentPrice(string memory name, uint256 duration)
        public
        view
        virtual
        override
        returns (IPriceOracle.Price memory price)
    {
        bytes32 label = keccak256(bytes(name));
        price = priceOracle.price(
            name,
            registrar.nameExpires(uint256(label)),
            duration
        );
    }

    function valid(string memory name)
        public
        view
        virtual
        override
        returns (bool)
    {
        if (strLength(name) < 3) {
            return false;
        }

        if (address(blocklist) != address(0)) {
            if (blocklist.hasName(name, msg.sender)) {
                return false;
            }
        }

        return true;
    }

    function available(string memory name)
        public
        view
        virtual
        override
        returns (bool)
    {
        bytes32 label = keccak256(bytes(name));
        return valid(name) && registrar.available(uint256(label));
    }

    /**
     * @dev Get price in CRO for a name registration
     * @param name The name to check price for
     * @param duration How long to register for
     * @return The total price in CRO (wei)
     */
    function getPrice(string memory name, uint256 duration) 
        public 
        view 
        returns (uint256) 
    {
        IPriceOracle.Price memory price = rentPrice(name, duration);
        return price.base + price.premium;
    }

    function strLength(string memory name)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return name.strlen();
    }

    function makeCommitment(
        string memory name,
        address owner,
        uint256 duration,
        bytes32 secret,
        address resolver,
        bytes[] calldata data,
        bool reverseRecord
    ) public pure virtual override returns (bytes32) {
        bytes32 label = keccak256(bytes(name));
        if (data.length > 0) {
            require(
                resolver != address(0),
                "BaseRegistrarController: resolver is required when data is supplied"
            );
        }
        return
            keccak256(
                abi.encode(
                    label,
                    owner,
                    duration,
                    resolver,
                    data,
                    secret,
                    reverseRecord
                )
            );
    }

    function commit(bytes32 commitment) public virtual override {
        require(commitments[commitment] + MAX_COMMITMENT_AGE < block.timestamp, "BaseRegistrarController: invalid commitment");
        commitments[commitment] = block.timestamp;
    }

    function setReverseRegistrar(address _reverseRegistrar) external onlyOwner {
        reverseRegistrar = IReverseRegistrar(_reverseRegistrar);
        emit ReverseRegistrarChanged(_reverseRegistrar);
    }

    function setPriceOracle(address _priceOracle) external onlyOwner {
        priceOracle = IPriceOracle(_priceOracle);
        emit PriceOracleChanged(_priceOracle);
    }

    function setBlocklist(address _blocklist) external onlyOwner {
        blocklist = Blocklist(_blocklist);
        emit BlocklistChanged(_blocklist);
    }

    function setRevenueDistributor(address _revenueDistributor)
        external
        onlyOwner
    {
        revenueDistributor = IRevenueDistributor(_revenueDistributor);
        emit RevenueDistributorChanged(_revenueDistributor);
    }

    function setChanceRequired(bool _required) external onlyOwner {
        chanceRequired = _required;
        emit ChanceRequiredChanged(_required);
    }

    function distributeHeldRevenue() external onlyOwner {
        _distributeRevenue(_heldRevenue());
    }

    function minCommitmentAge() public pure returns (uint256) {
        return MIN_COMMITMENT_AGE;
    }

    function maxCommitmentAge() public pure returns (uint256) {
        return MAX_COMMITMENT_AGE;
    }

    function supportsInterface(bytes4 interfaceID)
        external
        pure
        virtual
        returns (bool)
    {
        return
            interfaceID == type(IERC165).interfaceId ||
            interfaceID == type(IBaseRegistrarController).interfaceId;
    }

    /* Internal functions */

    function _consumeCommitment(
        string memory name,
        uint256 duration,
        bytes32 commitment
    ) internal {
        // Require a valid commitment (is old enough and is committed)
        require(
            commitments[commitment] + MIN_COMMITMENT_AGE <= block.timestamp,
            "BaseRegistrarController: Commitment is not valid"
        );

        // If the commitment is too old, or the name is registered, stop
        require(
            commitments[commitment] + MAX_COMMITMENT_AGE > block.timestamp,
            "BaseRegistrarController: Commitment has expired"
        );

        require(
            available(name),
            "BaseRegistrarController: Name is unavailable"
        );

        if (chanceRequired && strLength(name) < 5) {
            if (address(blocklist) != address(0)) {
                blocklist.checkChance(name, msg.sender);
            }
        }

        delete commitments[commitment];

        require(duration >= MIN_REGISTRATION_DURATION);
    }

    function _setReverseRecord(
        string memory name,
        address resolver,
        address owner
    ) internal {
        reverseRegistrar.setNameForAddr(
            msg.sender,
            owner,
            resolver,
            string.concat(name, ".", ORBIT_LABEL)
        );
    }

    function _heldRevenue() internal view virtual returns (uint256) {
        return 0;
    }

    function _distributeRevenue(uint256) internal virtual {
        require(
            false,
            "BaseRegistrarController: unimplemented distributing method"
        );
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
