// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/**
 * Interface for the new (multicoin) addr function.
 */
interface IAddressResolver {
    event AddressChanged(bytes32 indexed node, uint coinType, bytes newAddress);

    /**
     * Returns the address associated with an Orbit node.
     * @param node The Orbit node to query.
     * @param coinType The coin type from slip-0044.
     * @return The associated address in bytes.
     */
    function addr(bytes32 node, uint coinType) external view returns(bytes memory);
}
