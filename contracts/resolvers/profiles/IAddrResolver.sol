// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/**
 * Interface for the basic addr function.
 */
interface IAddrResolver {
    event AddrChanged(bytes32 indexed node, address a);

    /**
     * Returns the address associated with an Orbit node.
     * @param node The Orbit node to query.
     * @return The associated address.
     */
    function addr(bytes32 node) external view returns (address payable);
}
