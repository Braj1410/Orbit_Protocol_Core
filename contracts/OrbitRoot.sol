// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./utils/Ownable.sol";
import "./Orbit.sol";
import "./utils/Controllable.sol";

contract OrbitRoot is Ownable, Controllable {
    bytes32 private immutable ROOT_NODE;

    bytes4 private constant INTERFACE_META_ID =
        bytes4(keccak256("supportsInterface(bytes4)"));

    event TLDLocked(bytes32 indexed label);

    Orbit public orbit;
    mapping(bytes32 => bool) public locked;

    constructor(Orbit _orbit, bytes32 _node) {
        require(
            address(_orbit) != address(0),
            "OrbitRoot: orbit cannot be zero address"
        );
        orbit = _orbit;
        ROOT_NODE = _node;
    }

    function setSubnodeOwner(
        bytes32 label,
        address owner
    ) external onlyController {
        require(!locked[label], "Cant allow locked label");
        orbit.setSubnodeOwner(ROOT_NODE, label, owner);
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
