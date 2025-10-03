// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

interface IRevenueDistributor {
    function deposit() external payable;

    function depositToken(uint256 tokenAmount) external;

    function setRevenueBeneficiary(address _revenueBeneficiary) external;

    function setStakingDistributor(address _stakingDistributor) external;

    function setTokenSwapRouter(
        address _tokenSwapRouter,
        address[] memory _tokenSwapPaths
    ) external;

    function allocatePendingRevenue() external;

    function allocatePendingStaking() external;

    function allocatePendingBurning() external;

    function allocateAllPendings() external;

    function allocatePendingRevenueToken() external;

    function allocatePendingStakingToken() external;

    function allocateAllPendingTokens() external;

    function getUnlockedStakingAmount() view external returns(uint256);

    function getUnlockedStakingTokenAmount() view external returns(uint256);

    
}
