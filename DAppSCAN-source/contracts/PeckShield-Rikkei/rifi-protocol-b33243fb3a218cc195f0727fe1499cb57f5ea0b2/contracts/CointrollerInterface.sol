pragma solidity ^0.5.16;

contract CointrollerInterface {
    /// @notice Indicator that this is a Cointroller contract (for inspection)
    bool public constant isCointroller = true;

    /*** Assets You Are In ***/

    function enterMarkets(address[] calldata rTokens) external returns (uint[] memory);
    function exitMarket(address rToken) external returns (uint);

    /*** Policy Hooks ***/

    function mintAllowed(address rToken, address minter, uint mintAmount) external returns (uint);
    function mintVerify(address rToken, address minter, uint mintAmount, uint mintTokens) external;

    function redeemAllowed(address rToken, address redeemer, uint redeemTokens) external returns (uint);
    function redeemVerify(address rToken, address redeemer, uint redeemAmount, uint redeemTokens) external;

    function borrowAllowed(address rToken, address borrower, uint borrowAmount) external returns (uint);
    function borrowVerify(address rToken, address borrower, uint borrowAmount) external;

    function repayBorrowAllowed(
        address rToken,
        address payer,
        address borrower,
        uint repayAmount) external returns (uint);
    function repayBorrowVerify(
        address rToken,
        address payer,
        address borrower,
        uint repayAmount,
        uint borrowerIndex) external;

    function liquidateBorrowAllowed(
        address rTokenBorrowed,
        address rTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount) external returns (uint);
    function liquidateBorrowVerify(
        address rTokenBorrowed,
        address rTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount,
        uint seizeTokens) external;

    function seizeAllowed(
        address rTokenCollateral,
        address rTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens) external returns (uint);
    function seizeVerify(
        address rTokenCollateral,
        address rTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens) external;

    function transferAllowed(address rToken, address src, address dst, uint transferTokens) external returns (uint);
    function transferVerify(address rToken, address src, address dst, uint transferTokens) external;

    /*** Liquidity/Liquidation Calculations ***/

    function liquidateCalculateSeizeTokens(
        address rTokenBorrowed,
        address rTokenCollateral,
        uint repayAmount) external view returns (uint, uint);
}
