// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "../Orbit.sol";
import "./IReverseRegistrar.sol";
import "../resolvers/IResolver.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../utils/ControllableUpgradeable.sol";

bytes32 constant lookup = 0x3031323334353637383961626364656600000000000000000000000000000000;

// namehash('addr.reverse')
bytes32 constant ADDR_REVERSE_NODE = 0x91d1777781884d03a6757a803996e38de2a42967fb37eeaca72729271025a9e2;

contract ReverseRegistrar is
    Initializable,
    OwnableUpgradeable,
    ControllableUpgradeable,
    UUPSUpgradeable,
    IReverseRegistrar
{
    Orbit public orbit;
    IResolver public defaultResolver;

    event ReverseClaimed(address indexed addr, bytes32 indexed node);

    event ResolverChanged(address indexed resolver);

    function initialize(Orbit _orbit) public initializer {
        __Controllable_init();

        orbit = _orbit;

        // Assign ownership of the reverse record to our deployer
        ReverseRegistrar oldRegistrar = ReverseRegistrar(
            _orbit.owner(ADDR_REVERSE_NODE)
        );
        if (address(oldRegistrar) != address(0x0)) {
            oldRegistrar.claim(msg.sender);
        }
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    modifier authorised(address addr) {
        require(
            addr == msg.sender ||
                controllers[msg.sender] ||
                orbit.isApprovedForAll(addr, msg.sender) ||
                ownsContract(addr),
            "ReverseRegistrar: Caller is not a controller or authorised by address or the address itself"
        );
        _;
    }

    function setDefaultResolver(address resolver) public override onlyOwner {
        require(
            address(resolver) != address(0),
            "ReverseRegistrar: Resolver address must not be 0"
        );
        defaultResolver = IResolver(resolver);
        emit ResolverChanged(resolver);
    }

    /**
     * @dev Transfers ownership of the reverse Orbit record associated with the
     *      calling account.
     * @param owner The address to set as the owner of the reverse record in Orbit.
     * @return The Orbit node hash of the reverse record.
     */
    function claim(address owner) public override returns (bytes32) {
        return claimForAddr(msg.sender, owner, address(defaultResolver));
    }

    /**
     * @dev Transfers ownership of the reverse Orbit record associated with the
     *      calling account.
     * @param addr The reverse record to set
     * @param owner The address to set as the owner of the reverse record in Orbit.
     * @return The Orbit node hash of the reverse record.
     */
    function claimForAddr(
        address addr,
        address owner,
        address resolver
    ) public override authorised(addr) returns (bytes32) {
        bytes32 labelHash = sha3HexAddress(addr);
        bytes32 reverseNode = keccak256(
            abi.encodePacked(ADDR_REVERSE_NODE, labelHash)
        );
        emit ReverseClaimed(addr, reverseNode);
        orbit.setSubnodeRecord(
            ADDR_REVERSE_NODE,
            labelHash,
            owner,
            resolver,
            0
        );
        return reverseNode;
    }

    /**
     * @dev Transfers ownership of the reverse Orbit record associated with the
     *      calling account.
     * @param owner The address to set as the owner of the reverse record in Orbit.
     * @param resolver The address of the resolver to set; 0 to leave unchanged.
     * @return The Orbit node hash of the reverse record.
     */
    function claimWithResolver(
        address owner,
        address resolver
    ) public override returns (bytes32) {
        return claimForAddr(msg.sender, owner, resolver);
    }

    /**
     * @dev Sets the `name()` record for the reverse Orbit record associated with
     * the calling account. First updates the resolver to the default reverse
     * resolver if necessary.
     * @param name The name to set for this address.
     * @return The Orbit node hash of the reverse record.
     */
    function setName(string memory name) public override returns (bytes32) {
        return
            setNameForAddr(
                msg.sender,
                msg.sender,
                address(defaultResolver),
                name
            );
    }

    function setNameOnly(
        address addr,
        address resolver,
        string memory name
    ) external override authorised(addr) returns (bytes32) {
        if (resolver == address(0x0)) {
            resolver = address(defaultResolver);
        }

        bytes32 reverseNode = node(addr);
        IResolver(resolver).setName(reverseNode, name);
        return reverseNode;
    }

    /**
     * @dev Sets the `name()` record for the reverse Orbit record associated with
     * the account provided. First updates the resolver to the default reverse
     * resolver if necessary.
     * Only callable by controllers and authorised users
     * @param addr The reverse record to set
     * @param owner The owner of the reverse node
     * @param name The name to set for this address.
     * @return The Orbit node hash of the reverse record.
     */
    function setNameForAddr(
        address addr,
        address owner,
        address resolver,
        string memory name
    ) public override returns (bytes32) {
        if (resolver == address(0x0)) {
            resolver = address(defaultResolver);
        }

        bytes32 reverseNode = claimForAddr(addr, owner, resolver);
        IResolver(resolver).setName(reverseNode, name);
        return reverseNode;
    }

    /**
     * @dev Returns the node hash for a given account's reverse records.
     * @param addr The address to hash
     * @return The Orbit node hash.
     */
    function node(address addr) public pure override returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(ADDR_REVERSE_NODE, sha3HexAddress(addr))
            );
    }

    /**
     * @dev An optimised function to compute the sha3 of the lower-case
     *      hexadecimal representation of an Cronos address.
     * @param addr The address to hash
     * @return ret The SHA3 hash of the lower-case hexadecimal encoding of the
     *         input address.
     */
    function sha3HexAddress(address addr) private pure returns (bytes32 ret) {
        assembly {
            for {
                let i := 40
            } gt(i, 0) {

            } {
                i := sub(i, 1)
                mstore8(i, byte(and(addr, 0xf), lookup))
                addr := div(addr, 0x10)
                i := sub(i, 1)
                mstore8(i, byte(and(addr, 0xf), lookup))
                addr := div(addr, 0x10)
            }

            ret := keccak256(0, 40)
        }
    }

    function ownsContract(address addr) internal view returns (bool) {
        try OwnableUpgradeable(addr).owner() returns (address owner) {
            return owner == msg.sender;
        } catch {
            return false;
        }
    }
}
