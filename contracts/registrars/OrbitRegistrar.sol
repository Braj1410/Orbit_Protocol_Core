//SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "../Orbit.sol";
import "./IBaseRegistrar.sol";
import "./BaseRegistrar.sol";

import "../utils/Address.sol";

contract OrbitRegistrar is BaseRegistrar {
    using Address for address;

    string private constant ORBIT_LABEL = "orbit";
    bytes32 private constant ORBIT_NODE =
        0x93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae;


    function transferFromWithCalls(
        address from,
        address to,
        uint256 id,
        address resolver,
        bytes[] calldata data,
        bool updateRegistry
    ) external live {
        require(_isApprovedOrOwner(_msgSender(), id), "OrbitRegistrar: caller is not owner nor approved");

        // transfer ERC721
        _transfer(from, to, id);

        // change owner in registry
        if (updateRegistry) {
            orbit.setSubnodeOwner(baseNode, bytes32(id), to);
        }

        // clean resolver records
        if (resolver != address(0) && data.length > 0) {
            bytes32 nodehash = keccak256(abi.encodePacked(ORBIT_NODE, bytes32(id)));
            for (uint256 i = 0; i < data.length; i++) {
                // check first few bytes are namehash
                bytes32 txNamehash = bytes32(data[i][4:36]);
                require(
                    txNamehash == nodehash,
                    "OrbitRegistrar: Namehash on record do not match the name being registered"
                );
                resolver.functionCall(
                    data[i],
                    "OrbitRegistrar: Failed to set Record"
                );
            }
        }
    }
}
