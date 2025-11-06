pragma solidity ^0.8.28;
struct TLD {
    bytes32 name;
    address owner;
    address registrar;
    address registrarController;
    uint256 creationTime;
    uint256 registrationFee;
    uint256 totalRegistrations;
    uint256 totalRevenue;
    bool isActive;
    uint256 ownerSharePercentage;
    uint256 expirationTime;
    uint256 renewalFee;
}
