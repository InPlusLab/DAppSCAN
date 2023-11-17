pragma solidity ^0.8.0;

interface IRevenueSharingPool {
    
    struct UserInfo {
        uint256 amount;
        uint256 rewardDept;
        uint256 pendingReward;
        uint256 lastUpdateRoundId;
    }
    
    struct InputToken {
        address token;
        uint256 amount;
        address[] tokenToBUSDPath;
    }
    
    event DepositStake(address indexed account, uint256 amount, uint256 timestamp);
    event WithdrawStake(address indexed account, uint256 amount, uint256 timestamp);
    event ClaimReward(address indexed account, uint256 amount, uint256 timestamp);
    event DistributeLuckyRevenue(address from, address to, uint256 amounts);
    
    function depositToken(uint256 amount) external;
    function withdrawToken() external;
    function claimReward() external;
    function getRoundPastTime() external view returns (uint256);
    function getLuckyBalance() external view returns (uint256);
    function getLuckyBusdBalance() external view returns (uint256);
    function getPendingReward() external view returns (uint256);
    function depositRevenue(InputToken[] calldata inputTokens,address[] calldata BUSDToOutputPath,uint256 minOutputAmount) external payable;
}
