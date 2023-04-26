// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IStrategyLink {

    event StrategyDeposit(address indexed strategy, uint256 indexed pid, address indexed user, uint256 amount, uint256 borrowAmount);
    event StrategyBorrow(address indexed strategy, uint256 indexed pid, address indexed user, uint256 borrowAmount);
    event StrategyWithdraw(address indexed strategy, uint256 indexed pid, address indexed user, uint256 amount);
    event StrategyLiquidation(address indexed strategy, uint256 indexed pid, address indexed user, uint256 amount);
    
    function bank() external view returns(address);
    function getSource() external view returns (string memory);
    function userInfo(uint256 _pid, address _account) external view returns (uint256,uint256,address,uint256);
    function getPoolInfo(uint256 _pid) external view  returns(address[] memory collateralToken, address baseToken, address lpToken, uint256 poolId, uint256 totalLPAmount, uint256 totalLPRefund);
    function getBorrowInfo(uint256 _pid, address _account) external view returns (address borrowFrom, uint256 bid);
    function getBorrowAmount(uint256 _pid, address _account) external view returns (uint256 value);
    function getDepositAmount(uint256 _pid, address _account) external view returns (uint256 amount);

    function getPoolCollateralToken(uint256 _pid) external view returns (address[] memory collateralToken);
    function getPoollpToken(uint256 _pid) external view returns (address lpToken);
    function getBaseToken(uint256 _pid) external view returns (address baseToken);

    function poolLength() external view returns (uint256);

    function pendingRewards(uint256 _pid, address _account) external view returns (uint256 value);
    function pendingLPAmount(uint256 _pid, address _account) external view returns (uint256 value);

    function massUpdatePools() external;
    function updatePool(uint256 _pid) external;

    function deposit(uint256 _pid, address _account, address _debtFrom, uint256 _bAmount, uint256 _desirePrice, uint256 _slippage) external returns (uint256 lpAmount);
    function depositLPToken(uint256 _pid, address _account, address _debtFrom, uint256 _bAmount, uint256 _desirePrice, uint256 _slippage) external returns (uint256 lpAmount);
    
    function withdraw(uint256 _pid, address _account, uint256 _rate) external;
    function withdrawLPToken(uint256 _pid, address _account, uint256 _rate) external;

    function emergencyWithdraw(uint256 _pid, address _account) external;

    function liquidation(uint256 _pid, address _account, address _hunter, uint256 _maxDebt) external;
    function repayBorrow(uint256 _pid, address _account, uint256 _rate, bool _fast) external;
}