// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IReverseAdapter {
    struct DomainInfo {
        string name;
        string tld;
        uint256 timestamp;
        bool isPrimary;
    }

    function setName(
        address addr,
        string calldata name,
        string calldata tld,
        bool makePrimary
    ) external;

    function setPrimaryName(uint256 index) external;

    function removeName(address addr, string calldata name) external;

    function getName(address addr) external view returns (string memory);

    function getAllNames(
        address addr
    ) external view returns (DomainInfo[] memory);

    function getDomainInfo(
        address addr,
        uint256 index
    )
        external
        view
        returns (
            string memory name,
            string memory tld,
            uint256 timestamp,
            bool isPrimary
        );

    function hasName(address addr) external view returns (bool);

    function getNameCount(address addr) external view returns (uint256);

    function authorizeRegistrar(address registrar, bool authorized) external;

    function batchAuthorizeRegistrars(
        address[] calldata registrars,
        bool authorized
    ) external;

    function getTLDStats(string calldata tld) external view returns (uint256);

    function resolve(address addr) external view returns (string memory);

    function batchResolve(
        address[] calldata addresses
    ) external view returns (string[] memory);

    function searchDomains(
        string calldata query
    ) external pure returns (address[] memory, string[] memory);
}
