// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

interface IBankingNode {
    //ERC20 functions

    function name() external pure returns (string memory);

    function symbol() external pure returns (string memory);

    function decimals() external pure returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function transfer(address to, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    //Banking Node Functions

    function requestLoan(
        uint256 loanAmount,
        uint256 paymentInterval,
        uint256 numberOfPayments,
        uint256 interestRate,
        bool interestOnly,
        address collateral,
        uint256 collateralAmount,
        address agent,
        string memory message
    ) external returns (uint256 requestId);

    function withdrawCollateral(uint256 loanId) external;

    function collectAaveRewards(address[] calldata assets) external;

    function collectCollateralFees(address collateral) external;

    function makeLoanPayment(uint256 loanId) external;

    function repayEarly(uint256 loanId) external;

    function collectFees() external;

    function deposit(uint256 _amount) external;

    function withdraw(uint256 _amount) external;

    function stake(uint256 _amount) external;

    function initiateUnstake(uint256 _amount) external;

    function unstake() external;

    function slashLoan(uint256 loanId, uint256 minOut) external;

    function sellSlashed(uint256 minOut) external;

    function donateBaseToken(uint256 _amount) external;

    //Operator only functions

    function approveLoan(uint256 loanId, uint256 requiredCollateralAmount)
        external;

    function clearPendingLoans() external;

    function whitelistAddresses(address whitelistAddition) external;

    //View functions

    function getStakedBNPL() external view returns (uint256);

    function getBaseTokenBalance(address user) external view returns (uint256);

    function getBNPLBalance(address user) external view returns (uint256 what);

    function getUnbondingBalance(address user) external view returns (uint256);

    function getNextPayment(uint256 loanId) external view returns (uint256);

    function getNextDueDate(uint256 loanId) external view returns (uint256);

    function getTotalAssetValue() external view returns (uint256);

    function getPendingRequestCount() external view returns (uint256);

    function getCurrentLoansCount() external view returns (uint256);

    function getDefaultedLoansCount() external view returns (uint256);
}
