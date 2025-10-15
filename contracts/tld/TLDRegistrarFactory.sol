// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../Orbit.sol";
import "../OrbitRoot.sol";
import "./TLDRegistrar.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title TLDRegistrarFactory
 * @notice Factory for deploying TLD registrars
 * @dev Separated to reduce main factory size
 */
contract TLDRegistrarFactory is OwnableUpgradeable, UUPSUpgradeable {
    Orbit public orbit;
    OrbitRoot public orbitRoot;
    address public tldFactory;

    mapping(uint256 => address) public registrars; // tokenId => proxy
    mapping(address => bool) public isRegistrar;

    event RegistrarDeployed(
        uint256 indexed tokenId,
        string name,
        address proxy,
        address owner
    );

    modifier onlyFactory() {
        require(msg.sender == tldFactory, "Only factory");
        _;
    }

    function initialize(Orbit _orbit, OrbitRoot _orbitRoot) public initializer {
        __Ownable_init(msg.sender);
        orbit = _orbit;
        orbitRoot = _orbitRoot;
    }

    function setTLDFactory(address _factory) external onlyOwner {
        tldFactory = _factory;
    }

    /**
     * @notice Deploy a new proxy for a TLD
     */
    function deployRegistrar(
        uint256 tokenId,
        string calldata tldName,
        address tldOwner
    ) external onlyFactory returns (address) {
        require(registrars[tokenId] == address(0), "Already deployed");

        bytes32 label = keccak256(bytes(tldName));
        bytes32 node = keccak256(abi.encodePacked(orbitRoot.ROOT_NODE, label));

        TLDRegistrar registrar = new TLDRegistrar(
            orbit,
            node,
            tldFactory,
            address(this),
            tldOwner
        );

        // Register with OrbitRoot
        console.log("Registring with OrbitRoot", address(registrar));
        orbitRoot.registerNode(node, address(registrar));

        registrars[tokenId] = address(registrar);
        isRegistrar[address(registrar)] = true;

        emit RegistrarDeployed(tokenId, tldName, address(registrar), tldOwner);
        return address(registrar);
    }

    /**
     * @notice Update proxy configuration
     * @dev Note: TLDRegistrar fees are immutable, this is a placeholder
     */
    function updateRegistrarFee(
        uint256 tokenId,
        uint256 newFee
    ) external onlyFactory {
        // TLDRegistrar doesn't have setRegistrationFee
        // Fee updates are handled at the storage level
        // This function exists for interface compatibility
    }

    /**
     * @notice Transfer proxy ownership
     */
    function transferRegistrarOwnership(
        uint256 tokenId,
        address newOwner
    ) external onlyFactory {
        address proxy = registrars[tokenId];
        require(proxy != address(0), "No proxy");

        TLDRegistrar(proxy).transferOwnership(newOwner);
    }

    /**
     * @notice Get proxy for a TLD
     */
    function getRegistrar(uint256 tokenId) external view returns (address) {
        return registrars[tokenId];
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override {}
}
