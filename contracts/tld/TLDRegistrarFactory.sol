// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../Orbit.sol";
import "../OrbitRoot.sol";
import "./TLDRegistrar.sol";
import "../utils/Ownable.sol";

/**
 * @title TLDRegistrarFactory
 * @notice Factory for deploying TLD registrars
 * @dev Separated to reduce main factory size
 */
contract TLDRegistrarFactory is Ownable {
    Orbit public immutable orbit;
    OrbitRoot public immutable orbitRoot;
    address public tldFactory;

    mapping(uint256 => address) public registrars; // tokenId => registrar
    mapping(address => bool) public isRegistrar;

    event RegistrarDeployed(
        uint256 indexed tokenId,
        string name,
        address registrar,
        address owner
    );

    modifier onlyFactory() {
        require(msg.sender == tldFactory, "Only factory");
        _;
    }

    constructor(Orbit _orbit, OrbitRoot _orbitRoot) {
        orbit = _orbit;
        orbitRoot = _orbitRoot;
    }

    function setTLDFactory(address _factory) external onlyOwner {
        tldFactory = _factory;
    }

    /**
     * @notice Deploy a new registrar for a TLD
     */
    function deployRegistrar(
        uint256 tokenId,
        string calldata tldName,
        address tldOwner
    ) external onlyFactory returns (address) {
        require(registrars[tokenId] == address(0), "Already deployed");

        bytes32 label = keccak256(bytes(tldName));
        bytes32 rootNode = bytes32(0);
        bytes32 node = keccak256(abi.encodePacked(rootNode, label));

        TLDRegistrar registrar = new TLDRegistrar();

        registrar.initialize(orbit, node, tldFactory, tldOwner);

        // Register with OrbitRoot
        orbitRoot.setSubnodeOwner(label, address(registrar));

        registrars[tokenId] = address(registrar);
        isRegistrar[address(registrar)] = true;

        emit RegistrarDeployed(tokenId, tldName, address(registrar), tldOwner);

        return address(registrar);
    }

    /**
     * @notice Update registrar configuration
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
     * @notice Transfer registrar ownership
     */
    function transferRegistrarOwnership(
        uint256 tokenId,
        address newOwner
    ) external onlyFactory {
        address registrar = registrars[tokenId];
        require(registrar != address(0), "No registrar");

        TLDRegistrar(registrar).transferOwnership(newOwner);
    }

    /**
     * @notice Get registrar for a TLD
     */
    function getRegistrar(uint256 tokenId) external view returns (address) {
        return registrars[tokenId];
    }
}
