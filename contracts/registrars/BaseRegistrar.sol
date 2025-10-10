//SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "../Orbit.sol";
import "./IBaseRegistrar.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

import "../tld/structs.sol";
import "hardhat/console.sol";

contract BaseRegistrar is ERC721Enumerable, IBaseRegistrar {
    Orbit public orbit;
    bytes32 public baseNode;

    address public _owner;
    address public _tldfactory;
    address public _registrarFactory;

    // A map of addresses that are authorised to register and renew names.
    mapping(address => bool) public controllers;

    mapping(uint256 => uint) public expiries;

    uint256 public constant GRACE_PERIOD = 90 days;

    bytes4 private constant RECLAIM_ID =
        bytes4(keccak256("reclaim(uint256,address)"));

    event OwnershipTransferred(
        address indexedpreviousOwner,
        address indexed newOwner
    );

    /**
     * v2.1.3 version of _isApprovedOrOwner which calls ownerOf(tokenId) and takes grace period into consideration instead of ERC721.ownerOf(tokenId);
     * https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v2.1.3/contracts/token/ERC721/ERC721.sol#L187
     * @dev Returns whether the given spender can transfer a given token ID
     * @param spender address of the spender to query
     * @param tokenId uint256 ID of the token to be transferred
     * @return bool whether the msg.sender is approved for the given token ID,
     *    is an operator of the owner, or is the owner of the token
     */
    function _isApprovedOrOwner(
        address spender,
        uint256 tokenId
    ) internal view returns (bool) {
        address owner = ownerOf(tokenId);
        return (spender == owner ||
            getApproved(tokenId) == spender ||
            isApprovedForAll(owner, spender));
    }

    constructor(
        Orbit _orbit,
        bytes32 _baseNode,
        address tldfactory,
        address registrarFactory,
        address owner
    ) ERC721("BaseRegistrar", "BR") {
        require(
            address(_orbit) != address(0),
            "BaseRegistrar: orbit cannot be zero address"
        );
        require(
            _baseNode != bytes32(0),
            "BaseRegistrar: baseNode cannot be zero"
        );
        orbit = _orbit;
        baseNode = _baseNode;

        _tldfactory = tldfactory;
        _owner = owner;
        _registrarFactory = registrarFactory;
        //controllers[owner] = true;
    }

    modifier live() {
        require(orbit.owner(baseNode) == address(this));
        _;
    }

    modifier onlyController() {
        require(controllers[_msgSender()]);
        _;
    }

    modifier onlyFactory() {
        require(_msgSender() == _tldfactory, "Only factory");
        _;
    }

    modifier onlyOwner() {
        console.log(_tldfactory);
        console.log(_msgSender());
        require(
            _msgSender() == _owner ||
                _msgSender() == _tldfactory ||
                _msgSender() == _registrarFactory,
            "Ownable: caller is not the owner"
        );
        _;
    }

    /**
     * @dev Gets the owner of the specified token ID. Names become unowned
     *      when their registration expires.
     * @param tokenId uint256 ID of the token to query the owner of
     * @return address currently marked as the owner of the given token ID
     */
    function ownerOf(
        uint256 tokenId
    ) public view override(ERC721, IERC721) returns (address) {
        require(
            expiries[tokenId] > block.timestamp,
            "BaseRegistrar: expiries of token is invalid"
        );
        return super.ownerOf(tokenId);
    }

    // Authorises a controller, who can register and renew domains.
    function addController(address controller) external override onlyOwner {
        controllers[controller] = true;
        emit ControllerAdded(controller);
    }

    // Revoke controller permission for an address.
    function removeController(address controller) external override onlyOwner {
        controllers[controller] = false;
        emit ControllerRemoved(controller);
    }

    // Set the resolver for the TLD this registrar manages.
    function setResolver(address resolver) external override onlyOwner {
        orbit.setResolver(baseNode, resolver);
    }

    // Returns the expiration timestamp of the specified id.
    function nameExpires(uint256 id) external view override returns (uint) {
        return expiries[id];
    }

    // Returns true if the specified name is available for registration.
    function available(uint256 id) public view override returns (bool) {
        // Not available if it's registered here or in its grace period.

        return expiries[id] + GRACE_PERIOD < block.timestamp;
    }

    /**
     * @dev Register a name.
     * @param id The token ID (keccak256 of the label).
     * @param owner The address that should own the registration.
     * @param duration Duration in seconds for the registration.
     */
    function register(
        uint256 id,
        address owner,
        uint duration
    ) external override returns (uint) {
        return _register(id, owner, duration, true);
    }

    /**
     * @dev Register a name, without modifying the registry.
     * @param id The token ID (keccak256 of the label).
     * @param owner The address that should own the registration.
     * @param duration Duration in seconds for the registration.
     */
    function registerOnly(
        uint256 id,
        address owner,
        uint duration
    ) external override returns (uint) {
        return _register(id, owner, duration, false);
    }

    /**
     * @dev Register a name with extra parameters, resolver and ttl.
     * @param id The token ID (keccak256 of the label).
     * @param owner The address that should own the registration.
     * @param duration Duration in seconds for the registration.
     * @param resolver The address of the resolver for updating registry.
     * @param ttl TTL in seconds for updating registry.
     */
    function registerExtra(
        uint256 id,
        address owner,
        uint duration,
        address resolver,
        uint64 ttl
    ) external override returns (uint) {
        uint expires = _register(id, owner, duration, false);
        orbit.setSubnodeRecord(baseNode, bytes32(id), owner, resolver, ttl);
        return expires;
    }

    function _register(
        uint256 id,
        address owner,
        uint duration,
        bool updateRegistry
    ) internal live onlyController returns (uint) {
        require(available(id));
        require(
            block.timestamp + duration + GRACE_PERIOD >
                block.timestamp + GRACE_PERIOD
        ); // Prevent future overflow

        expiries[id] = block.timestamp + duration;
        if (_ownerOf(id) != address(0)) {
            // Name was previously owned, and expired
            _burn(id);
        }
        _mint(owner, id);
        if (updateRegistry) {
            orbit.setSubnodeOwner(baseNode, bytes32(id), owner);
        }

        emit NameRegistered(id, owner, block.timestamp + duration);

        return block.timestamp + duration;
    }

    function renew(
        uint256 id,
        uint duration
    ) external override live onlyController returns (uint) {
        require(
            expiries[id] + GRACE_PERIOD >= block.timestamp,
            "BaseRegistrar: unable to renew"
        ); // Name must be registered here or in grace period
        require(
            expiries[id] + duration + GRACE_PERIOD > duration + GRACE_PERIOD
        ); // Prevent future overflow

        expiries[id] += duration;
        emit NameRenewed(id, expiries[id]);
        return expiries[id];
    }

    /**
     * @dev Reclaim ownership of a name in Orbit, if you own it in the registrar.
     */
    function reclaim(uint256 id, address owner) external override live {
        require(_isApprovedOrOwner(_msgSender(), id));
        orbit.setSubnodeOwner(baseNode, bytes32(id), owner);
    }

    function supportsInterface(
        bytes4 interfaceID
    ) public pure override(ERC721Enumerable, IERC165) returns (bool) {
        return
            interfaceID == type(IERC165).interfaceId ||
            interfaceID == type(IERC721).interfaceId ||
            interfaceID == RECLAIM_ID;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        _owner = newOwner;
        emit OwnershipTransferred(_owner, newOwner);
    }
}
