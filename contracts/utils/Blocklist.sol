// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../utils/StringUtils.sol";

contract Blocklist is UUPSUpgradeable, OwnableUpgradeable {
    using StringUtils for *;

    bool public enabled;
    mapping(bytes32 => bool) private _list;
    mapping(address => mapping(bytes32 => bool)) private _allows;
    mapping(address => bool) private _checkers;
    mapping(address => uint256) private _chances;

    event EnabledChange(bool enabled);
    event CheckerChange(address checker, bool enabled);

    function initialize() initializer public {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        enabled = true;
    }

    function has(bytes32 label, address user) public view returns (bool) {
        if (enabled != true) {
            return false;
        }

        if (_list[label] != true) {
            return false;
        }

        if (user == address(0)) {
            user = msg.sender;
        }

        // allow target users
        if (_allows[user][label] == true) {
            return false;
        }

        return true;
    }

    function hasName(string memory name, address user) public view returns (bool result) {
        uint256 length = name.strlen();

        // if all chars are from ASCII
        if (length == bytes(name).length) {
            name = name.toLower();
        }

        bytes32 label = keccak256(bytes(name));
        result = has(label, user);
    }

    function checkChance(string memory, address user) public {
        require(_checkers[msg.sender], "sender is not authorized to check");
        require(_chances[user] > 0, "user has no more chances");

        _chances[user] -= 1;
    }

    function update(bytes32 label, bool blocked) external onlyOwner() {
        _list[label] = blocked;
    }

    function batchUpdate(bytes32[] calldata labels, bool blocked) external onlyOwner() {
        for (uint i = 0; i < labels.length; i++) {
            _list[labels[i]] = blocked;
        }
    }

    function batchDelete(bytes32[] calldata labels) external onlyOwner() {
        for (uint i = 0; i < labels.length; i++) {
            delete _list[labels[i]];
        }
    }

    function allowed(address user, bytes32 label) public view returns (bool) {
        return _allows[user][label];
    }

    function allow(address user, bytes32[] calldata labels) external onlyOwner() {
        for (uint i = 0; i < labels.length; i++) {
            _allows[user][labels[i]] = true;
        }
    }

    function disallow(address user, bytes32[] calldata labels) external onlyOwner() {
        for (uint i = 0; i < labels.length; i++) {
            delete _allows[user][labels[i]];
        }
    }

    function batchAllow(address[] calldata users, bytes32[] calldata labels) external onlyOwner() {
        for (uint i = 0; i < users.length; i++) {
            _allows[users[i]][labels[i]] = true;
        }
    }

    function batchDisallow(address[] calldata users, bytes32[] calldata labels) external onlyOwner() {
        for (uint i = 0; i < users.length; i++) {
            delete _allows[users[i]][labels[i]];
        }
    }

    function enable() external onlyOwner() {
        enabled = true;
        emit EnabledChange(enabled);
    }

    function disable() external onlyOwner() {
        enabled = false;
        emit EnabledChange(enabled);
    }

    function checker(address _checker) public view returns (bool) {
        return _checkers[_checker];
    }

    function setChecker(address _checker, bool _enabled) external onlyOwner() {
        _checkers[_checker] = _enabled;
        emit CheckerChange(_checker, _enabled);
    }

    function updateChance(address user, uint256 number) external onlyOwner() {
        _chances[user] = number;
    }

    function batchUpdateChance(address[] calldata users, uint256 number) external onlyOwner() {
        for (uint i = 0; i < users.length; i++) {
            _chances[users[i]] = number;
        }
    }

    function batchSyncChance(address[] calldata users, uint256[] calldata numbers) external onlyOwner() {
        for (uint i = 0; i < users.length; i++) {
            _chances[users[i]] = numbers[i];
        }
    }

    function chance(address user) public view returns (uint256) {
        return _chances[user];
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}