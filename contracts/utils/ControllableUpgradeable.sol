// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract ControllableUpgradeable is Initializable, OwnableUpgradeable {
    mapping(address => bool) public controllers;

    event ControllerChanged(address indexed controller, bool enabled);

    function __Controllable_init() internal onlyInitializing {
        __Ownable_init(msg.sender);
    }

    modifier onlyController() {
        require(
            controllers[msg.sender],
            "Controllable: Caller is not a controller"
        );
        _;
    }

    function setController(address controller, bool enabled) public onlyOwner {
        controllers[controller] = enabled;
        emit ControllerChanged(controller, enabled);
    }
}
