// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/**
 * @title ITLDFactory
 * @notice Interface for TLD Factory interaction
 */
interface ITLDFactory {
    function distributeRevenue(uint256 tokenId, uint256 duration) external payable;
    function getTLD(uint256 tokenId) external view returns (
        string memory name,
        address owner,
        address registrar,
        uint256 registrationFee,
        uint256 totalRegistrations,
        uint256 totalRevenue,
        bool isActive
    );
}