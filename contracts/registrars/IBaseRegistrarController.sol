// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "../oracles/IPriceOracle.sol";

interface IBaseRegistrarController {
    function rentPrice(string memory, uint256)
        external
        returns (IPriceOracle.Price memory);

    function valid(string memory) external returns (bool);

    function available(string memory) external returns (bool);

    function strLength(string memory) external returns (uint256);

    function makeCommitment(
        string memory,
        address,
        uint256,
        bytes32,
        address,
        bytes[] calldata,
        bool
    ) external returns (bytes32);

    function commit(bytes32) external;
}
