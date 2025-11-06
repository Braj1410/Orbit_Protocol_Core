//SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "./BaseRegistrarController.sol";
import "./IOrbitRegistrarController.sol";
import "./IReverseRegistrar.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../utils/Address.sol";

/**
 * @dev A registrar controller for registering and renewing names at fixed cost.
 */
contract OrbitRegistrarController is
    BaseRegistrarController,
    IOrbitRegistrarController
{
    using Address for address;

    function initialize(
        IBaseRegistrar _registrar,
        IPriceOracle _priceOracle,
        IReverseRegistrar _reverseRegistrar,
        bytes32 basenode,
        string memory label
    ) public override initializer {
        super.initialize(
            _registrar,
            _priceOracle,
            _reverseRegistrar,
            basenode,
            label
        );
    }

    function register(
        string calldata name,
        address owner,
        uint256 duration,
        bytes32 secret,
        address resolver,
        bytes[] calldata data,
        bool reverseRecord
    ) public payable nonReentrant whenNotPaused {
        // Parameter validation
        require(
            bytes(name).length > 0,
            "OrbitRegistrarController: Name cannot be empty"
        );
        require(
            owner != address(0),
            "OrbitRegistrarController: Owner cannot be zero address"
        );
        require(
            duration <= 10 * 365 days,
            "OrbitRegistrarController: Duration exceeds maximum (10 years)"
        );
        require(
            duration >= MIN_REGISTRATION_DURATION,
            "OrbitRegistrarController: Duration too short"
        );

        // CRITICAL: Normalize domain name to lowercase to prevent case variations
        string memory normalizedName = _toLowerCase(name);
        bytes32 label = keccak256(bytes(normalizedName));
        IPriceOracle.Price memory price = rentPrice(normalizedName, duration);
        uint256 amount = price.base + price.premium;
        require(
            msg.value >= amount,
            "OrbitRegistrarController: Not enough payment provided"
        );

        _consumeCommitment(
            name,
            duration,
            makeCommitment(
                name,
                owner,
                duration,
                secret,
                resolver,
                data,
                reverseRecord
            )
        );

        uint256 expires = registrar.registerExtra(
            uint256(label),
            owner,
            duration,
            resolver,
            uint64(0)
        );

        // Set resolver records if resolver is provided
        if (resolver != address(0) && data.length > 0) {
            // Validate resolver is a contract
            require(
                resolver.code.length > 0,
                "OrbitRegistrarController: Resolver must be a contract"
            );

            bytes32 nodehash = keccak256(abi.encodePacked(BASE_NODE, label));
            for (uint256 i = 0; i < data.length; i++) {
                // Validate data length
                require(
                    data[i].length >= 36,
                    "OrbitRegistrarController: Invalid resolver data"
                );

                // check first few bytes are namehash
                bytes32 txNamehash = bytes32(data[i][4:36]);
                require(
                    txNamehash == nodehash,
                    "OrbitRegistrarController: Namehash on record do not match the name being registered"
                );

                // Use gas-limited call to prevent DoS
                (bool success, ) = resolver.call{gas: 100000}(data[i]);
                require(
                    success,
                    "OrbitRegistrarController: Failed to set Record"
                );
            }
        }

        if (reverseRecord) {
            _setReverseRecord(name, resolver, owner);
        }

        emit NameRegistered(
            name,
            label,
            owner,
            price.base,
            price.premium,
            expires
        );

        _distributeRevenue(amount);

        if (msg.value > amount) {
            (bool success, ) = payable(_msgSender()).call{
                value: msg.value - amount
            }("cancel");
            require(success, "OrbitRegistrarController: Refund failed");
        }
    }

    function renew(
        string calldata name,
        uint256 duration
    ) external payable nonReentrant whenNotPaused {
        // Parameter validation
        require(
            bytes(name).length > 0,
            "OrbitRegistrarController: Name cannot be empty"
        );
        require(
            duration <= 10 * 365 days,
            "OrbitRegistrarController: Duration exceeds maximum (10 years)"
        );
        require(
            duration >= MIN_REGISTRATION_DURATION,
            "OrbitRegistrarController: Duration too short"
        );

        // CRITICAL: Normalize domain name to lowercase for consistency
        string memory normalizedName = _toLowerCase(name);
        bytes32 label = keccak256(bytes(normalizedName));
        IPriceOracle.Price memory price = rentPrice(normalizedName, duration);
        uint256 amount = price.base;
        require(
            msg.value >= amount,
            "OrbitRegistrarController: Not enough payment provided for renewal"
        );

        uint256 expires = registrar.renew(uint256(label), duration);

        _distributeRevenue(amount);

        if (msg.value > amount) {
            (bool success, ) = payable(msg.sender).call{
                value: msg.value - amount
            }("");
            require(success, "OrbitRegistrarController: Refund failed");
        }

        emit NameRenewed(normalizedName, label, amount, expires);
    }

    function supportsInterface(
        bytes4 interfaceID
    ) external pure override returns (bool) {
        return
            interfaceID == type(IERC165).interfaceId ||
            interfaceID == type(IOrbitRegistrarController).interfaceId;
    }

    function _distributeRevenue(uint256 amount) internal override {
        if (address(revenueDistributor) != address(0)) {
            revenueDistributor.deposit{value: amount}();
        }
    }

    function _heldRevenue() internal view override returns (uint256) {
        return address(this).balance;
    }

    /**
     * @notice Convert string to lowercase to prevent case variation conflicts
     * @dev Prevents duplicate domains like Joey.cro and joey.cro
     */
    function _toLowerCase(
        string calldata str
    ) private pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        bytes memory lowerBytes = new bytes(strBytes.length);

        for (uint256 i = 0; i < strBytes.length; i++) {
            // Convert A-Z to a-z
            if (strBytes[i] >= 0x41 && strBytes[i] <= 0x5A) {
                lowerBytes[i] = bytes1(uint8(strBytes[i]) + 32);
            } else {
                lowerBytes[i] = strBytes[i];
            }
        }

        return string(lowerBytes);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override {}
}
