// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "./IBaseRegistrarController.sol";

interface IOrbitRegistrarController is IBaseRegistrarController {
    function register(
        string calldata,
        address,
        uint256,
        bytes32,
        address,
        bytes[] calldata,
        bool
    ) external payable;

    function renew(string calldata, uint256) external payable;
}
