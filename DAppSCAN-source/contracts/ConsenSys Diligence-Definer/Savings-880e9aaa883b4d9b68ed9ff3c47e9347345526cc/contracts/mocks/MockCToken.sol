pragma solidity 0.5.14;

contract MockCToken {

    // 1. CERC20 
    function mint(uint mintAmount) external returns (uint);
    function redeem(uint redeemAmount) external returns (uint);
    function redeemUnderlying(uint redeemAmount) external returns (uint);
    function borrow(uint borrowAmount) external returns (uint);
    function repayBorrow(uint repayAmount) external returns (uint);
    function repayBorrowBehalf(address borrower, uint repayAmount) external returns (uint);
    function liquidateBorrow(address borrower, uint repayAmount, address cTokenCollateral) external returns (uint);

    // 2. CETHER.sol
    function mint() external payable;
    function repayBorrow() external payable;
    function repayBorrowBehalf(address borrower) external payable;

    // 3. ERC20.sol
    function totalSupply() public view returns (uint256);
    function balanceOf(address account) public view returns (uint256);
    function transfer(address recipient, uint256 amount) public returns (bool);
    function allowance(address owner, address spender) public view returns (uint256);
    function approve(address spender, uint256 amount) public returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) public returns (bool);
    function increaseAllowance(address spender, uint256 addedValue) public returns (bool);
    function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool);

    function supplyRatePerBlock() external view returns (uint);
    function borrowRatePerBlock() external view returns (uint);
    function exchangeRateStore() external view returns (uint);
    function exchangeRateCurrent() external returns (uint);
    function balanceOfUnderlying(address owner) external returns (uint);
}