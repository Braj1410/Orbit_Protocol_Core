// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../Orbit.sol";
import "../OrbitRoot.sol";
import "./TLDRegistrar.sol";
import "../ERC1967Proxy.sol";

/**
 * @title TLDRegistrarFactory
 * @notice Factory for deploying TLD registrars
 * @dev Separated to reduce main factory size
 */
contract TLDRegistrarFactory is Ownable {
    Orbit public immutable orbit;
    OrbitRoot public immutable orbitRoot;
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

    constructor(Orbit _orbit, OrbitRoot _orbitRoot) {
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
        bytes32 rootNode = bytes32(0);
        bytes32 node = keccak256(abi.encodePacked(rootNode, label));

        TLDRegistrar registrar = new TLDRegistrar();

        bytes memory initData = abi.encodeWithSelector(
            TLDRegistrar.initialize.selector,
            orbit,
            node,
            tldFactory,
            tldOwner
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(registrar), initData);

        // Register with OrbitRoot
        orbitRoot.setSubnodeOwner(label, address(proxy));

        registrars[tokenId] = address(proxy);
        isRegistrar[address(proxy)] = true;

        emit RegistrarDeployed(tokenId, tldName, address(proxy), tldOwner);

        return address(proxy);
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
}
