// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./utils/Ownable.sol";
import "./OrbitRegistry.sol";
import "./utils/Controllable.sol";

contract OrbitRoot is Ownable, Controllable {
    bytes32 public immutable ROOT_NODE;

    bytes4 private constant INTERFACE_META_ID =
        bytes4(keccak256("supportsInterface(bytes4)"));

    event TLDLocked(bytes32 indexed label);

    OrbitRegistry public orbit;
    mapping(bytes32 => bool) public locked;

    constructor() {
        ROOT_NODE = bytes32(0x0);
        orbit = new OrbitRegistry();
    }

    function setSubnodeOwner(
        bytes32 node,
        bytes32 label,
        address owner
    ) external onlyController returns (bytes32 _subnode) {
        require(!locked[label], "Cant allow locked label");
        bytes32 subnode = orbit.setSubnodeOwner(node, label, owner);
        return subnode;
    }

    function registerNode(bytes32 node, address owner) external onlyController {
        orbit.registerNode(node, owner);
    }

    function setResolver(address resolver) external onlyOwner {
        orbit.setResolver(ROOT_NODE, resolver);
    }

    function lock(bytes32 label) external onlyOwner {
        emit TLDLocked(label);
        locked[label] = true;
    }

    function supportsInterface(
        bytes4 interfaceID
    ) external pure returns (bool) {
        return interfaceID == INTERFACE_META_ID;
    }
}
