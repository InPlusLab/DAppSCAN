pragma solidity 0.5.14;

import "openzeppelin-solidity/contracts/token/ERC20/SafeERC20.sol";
import "./config/Constant.sol";
import "./config/GlobalConfig.sol";
import "./lib/SavingLib.sol";
import "./lib/Utils.sol";
import "@openzeppelin/upgrades/contracts/Initializable.sol";
import "./InitializableReentrancyGuard.sol";
import "./InitializablePausable.sol";
import { ICToken } from "./compound/ICompound.sol";
import { ICETH } from "./compound/ICompound.sol";
import "openzeppelin-solidity/contracts/math/Math.sol";
// import "@nomiclabs/buidler/console.sol";

contract SavingAccount is Initializable, InitializableReentrancyGuard, Constant, InitializablePausable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Math for uint256;

    GlobalConfig public globalConfig;

    // Following are the constants, initialized via upgradable proxy contract
    // This is emergency address to allow withdrawal of funds from the contract

    event Transfer(address indexed token, address from, address to, uint256 amount);
    event Borrow(address indexed token, address from, uint256 amount);
    event Repay(address indexed token, address from, uint256 amount);
    event Deposit(address indexed token, address from, uint256 amount);
    event Withdraw(address indexed token, address from, uint256 amount);
    event WithdrawAll(address indexed token, address from, uint256 amount);
    event Claim(address from, uint256 amount);

    modifier onlyEmergencyAddress() {
        require(msg.sender ==  EMERGENCY_ADDR, "User not authorized");
        _;
    }

    modifier onlySupportedToken(address _token) {
        if(!Utils._isETH(address(globalConfig), _token)) {
            require(globalConfig.tokenInfoRegistry().isTokenExist(_token), "Unsupported token");
        }
        _;
    }

    modifier onlyEnabledToken(address _token) {
        require(globalConfig.tokenInfoRegistry().isTokenEnabled(_token), "The token is not enabled");
        _;
    }

    modifier onlyAuthorized() {
        require(msg.sender == address(globalConfig.bank()),
            "Only authorized to call from DeFiner internal contracts.");
        _;
    }

    constructor() public {
        // THIS SHOULD BE EMPTY FOR UPGRADABLE CONTRACTS
        // console.log("Start to construct", msg.sender);
    }

    /**
     * Initialize function to be called by the Deployer for the first time
     * @param _tokenAddresses list of token addresses
     * @param _cTokenAddresses list of corresponding cToken addresses
     * @param _globalConfig global configuration contract
     */
    function initialize(
        address[] memory _tokenAddresses,
        address[] memory _cTokenAddresses,
        GlobalConfig _globalConfig
    )
        public
        initializer
    {
        // Initialize InitializableReentrancyGuard
        super._initialize();
        super._initialize(address(_globalConfig));

        globalConfig = _globalConfig;

        require(_tokenAddresses.length == _cTokenAddresses.length, "Token and cToken length don't match.");
        uint tokenNum = _tokenAddresses.length;
        for(uint i = 0;i < tokenNum;i++) {
            if(_cTokenAddresses[i] != address(0x0) && _tokenAddresses[i] != ETH_ADDR) {
                approveAll(_tokenAddresses[i]);
            }
        }
    }

    /**
     * Approve transfer of all available tokens
     * @param _token token address
     */
    function approveAll(address _token) public {
        address cToken = globalConfig.tokenInfoRegistry().getCToken(_token);
        require(cToken != address(0x0), "cToken address is zero");
        IERC20(_token).safeApprove(cToken, 0);
        IERC20(_token).safeApprove(cToken, uint256(-1));
    }

    /**
     * Get current block number
     * @return the current block number
     */
    function getBlockNumber() internal view returns (uint) {
        return block.number;
    }

    /**
     * Transfer the token between users inside DeFiner
     * @param _to the address that the token be transfered to
     * @param _token token address
     * @param _amount amout of tokens transfer
     */
    function transfer(address _to, address _token, uint _amount) external onlySupportedToken(_token) onlyEnabledToken(_token) whenNotPaused nonReentrant {

        globalConfig.bank().newRateIndexCheckpoint(_token);
        uint256 amount = globalConfig.accounts().withdraw(msg.sender, _token, _amount);
        globalConfig.accounts().deposit(_to, _token, amount);

        emit Transfer(_token, msg.sender, _to, amount);
    }

    /**
     * Borrow the amount of token from the saving pool.
     * @param _token token address
     * @param _amount amout of tokens to borrow
     */
    function borrow(address _token, uint256 _amount) external onlySupportedToken(_token) onlyEnabledToken(_token) whenNotPaused nonReentrant {

        require(_amount != 0, "Borrow zero amount of token is not allowed.");

        globalConfig.bank().borrow(msg.sender, _token, _amount);

        // Transfer the token on Ethereum
        SavingLib.send(globalConfig, _amount, _token);

        emit Borrow(_token, msg.sender, _amount);
    }

    /**
     * Repay the amount of token back to the saving pool.
     * @param _token token address
     * @param _amount amout of tokens to borrow
     * @dev If the repay amount is larger than the borrowed balance, the extra will be returned.
     */
    function repay(address _token, uint256 _amount) public payable onlySupportedToken(_token) nonReentrant {
        require(_amount != 0, "Amount is zero");
        SavingLib.receive(globalConfig, _amount, _token);

        // Add a new checkpoint on the index curve.
        uint256 amount = globalConfig.bank().repay(msg.sender, _token, _amount);

        // Send the remain money back
        if(amount < _amount) {
            SavingLib.send(globalConfig, _amount.sub(amount), _token);
        }

        emit Repay(_token, msg.sender, amount);
    }

    /**
     * Deposit the amount of token to the saving pool.
     * @param _token the address of the deposited token
     * @param _amount the mount of the deposited token
     */
    function deposit(address _token, uint256 _amount) public payable onlySupportedToken(_token) onlyEnabledToken(_token) nonReentrant {
        require(_amount != 0, "Amount is zero");
        SavingLib.receive(globalConfig, _amount, _token);
        globalConfig.bank().deposit(msg.sender, _token, _amount);

        emit Deposit(_token, msg.sender, _amount);
    }

    /**
     * Withdraw a token from an address
     * @param _token token address
     * @param _amount amount to be withdrawn
     */
    function withdraw(address _token, uint256 _amount) external onlySupportedToken(_token) whenNotPaused nonReentrant {
        require(_amount != 0, "Amount is zero");
        uint256 amount = globalConfig.bank().withdraw(msg.sender, _token, _amount);
        SavingLib.send(globalConfig, amount, _token);

        emit Withdraw(_token, msg.sender, amount);
    }

    /**
     * Withdraw all tokens from the saving pool.
     * @param _token the address of the withdrawn token
     */
    function withdrawAll(address _token) external onlySupportedToken(_token) whenNotPaused nonReentrant {

        // Sanity check
        require(globalConfig.accounts().getDepositPrincipal(msg.sender, _token) > 0, "Token depositPrincipal must be greater than 0");

        // Add a new checkpoint on the index curve.
        globalConfig.bank().newRateIndexCheckpoint(_token);

        // Get the total amount of token for the account
        uint amount = globalConfig.accounts().getDepositBalanceCurrent(_token, msg.sender);

        uint256 actualAmount = globalConfig.bank().withdraw(msg.sender, _token, amount);
        if(actualAmount != 0) {
            SavingLib.send(globalConfig, actualAmount, _token);
        }
        emit WithdrawAll(_token, msg.sender, actualAmount);
    }

    struct LiquidationVars {
        // address token;
        // uint256 tokenPrice;
        // uint256 coinValue;
        uint256 borrowerCollateralValue;
        // uint256 tokenAmount;
        // uint256 tokenDivisor;
        uint256 msgTotalBorrow;
        uint256 targetTokenBalance;
        uint256 targetTokenBalanceBorrowed;
        uint256 targetTokenPrice;
        uint256 liquidationDiscountRatio;
        uint256 totalBorrow;
        uint256 borrowPower;
        uint256 liquidateTokenBalance;
        uint256 liquidateTokenPrice;
        // uint256 liquidateTokenValue;
        uint256 limitRepaymentValue;
        uint256 borrowTokenLTV;
        uint256 repayAmount;
        uint256 payAmount;
    }

    function liquidate(address _borrower, address _borrowedToken, address _collateralToken) public onlySupportedToken(_borrowedToken) onlySupportedToken(_collateralToken) whenNotPaused nonReentrant {

        require(globalConfig.accounts().isAccountLiquidatable(_borrower), "The borrower is not liquidatable.");
        LiquidationVars memory vars;

        // It is required that the liquidator doesn't exceed it's borrow power.
        vars.msgTotalBorrow = globalConfig.accounts().getBorrowETH(msg.sender);
        require(
            vars.msgTotalBorrow < globalConfig.accounts().getBorrowPower(msg.sender),
            "No extra funds are used for liquidation."
        );

        // _borrowedToken balance of the liquidator (deposit balance)
        vars.targetTokenBalance = globalConfig.accounts().getDepositBalanceCurrent(_borrowedToken, msg.sender);
        require(vars.targetTokenBalance > 0, "The account amount must be greater than zero.");

        // _borrowedToken balance of the borrower (borrow balance)
        vars.targetTokenBalanceBorrowed = globalConfig.accounts().getBorrowBalanceCurrent(_borrowedToken, _borrower);
        require(vars.targetTokenBalanceBorrowed > 0, "The borrower doesn't own any debt token specified by the liquidator.");

        // _borrowedToken available for liquidation
        uint256 borrowedTokenAmountForLiquidation = vars.targetTokenBalance.min(vars.targetTokenBalanceBorrowed);

        // _collateralToken balance of the borrower (deposit balance)
        vars.liquidateTokenBalance = globalConfig.accounts().getDepositBalanceCurrent(_collateralToken, _borrower);
        vars.liquidateTokenPrice = globalConfig.tokenInfoRegistry().priceFromAddress(_collateralToken);

        uint divisor = 10 ** uint256(globalConfig.tokenInfoRegistry().getTokenDecimals(_borrowedToken));
        uint liquidateTokendivisor = 10 ** uint256(globalConfig.tokenInfoRegistry().getTokenDecimals(_collateralToken));

        // _collateralToken to purchase so that borrower's balance matches its borrow power
        vars.totalBorrow = globalConfig.accounts().getBorrowETH(_borrower);
        vars.borrowPower = globalConfig.accounts().getBorrowPower(_borrower);
        vars.liquidationDiscountRatio = globalConfig.liquidationDiscountRatio();
        vars.borrowTokenLTV = globalConfig.tokenInfoRegistry().getBorrowLTV(_borrowedToken);
        vars.limitRepaymentValue = vars.totalBorrow.sub(vars.borrowPower).mul(100).div(vars.liquidationDiscountRatio.sub(vars.borrowTokenLTV));

        uint256 collateralTokenValueForLiquidation = vars.limitRepaymentValue.min(vars.liquidateTokenBalance.mul(vars.liquidateTokenPrice).div(liquidateTokendivisor));

        vars.targetTokenPrice = globalConfig.tokenInfoRegistry().priceFromAddress(_borrowedToken);
        uint256 liquidationValue = collateralTokenValueForLiquidation.min(borrowedTokenAmountForLiquidation.mul(vars.targetTokenPrice).mul(100).div(divisor).div(vars.liquidationDiscountRatio));

        vars.repayAmount = liquidationValue.mul(vars.liquidationDiscountRatio).mul(divisor).div(100).div(vars.targetTokenPrice);
        vars.payAmount = vars.repayAmount.mul(liquidateTokendivisor).mul(100).mul(vars.targetTokenPrice);
        vars.payAmount = vars.payAmount.div(divisor).div(vars.liquidationDiscountRatio).div(vars.liquidateTokenPrice);

        globalConfig.accounts().deposit(msg.sender, _collateralToken, vars.payAmount);
        globalConfig.accounts().withdraw(msg.sender, _borrowedToken, vars.repayAmount);
        globalConfig.accounts().withdraw(_borrower, _collateralToken, vars.payAmount);
        globalConfig.accounts().repay(_borrower, _borrowedToken, vars.repayAmount);
    }

    /**
     * Withdraw token from Compound
     * @param _token token address
     * @param _amount amount of token
     */
    function fromCompound(address _token, uint _amount) external onlyAuthorized {
        require(ICToken(globalConfig.tokenInfoRegistry().getCToken(_token)).redeemUnderlying(_amount) == 0, "redeemUnderlying failed");
    }

    function toCompound(address _token, uint _amount) external onlyAuthorized {
        address cToken = globalConfig.tokenInfoRegistry().getCToken(_token);
        if (Utils._isETH(address(globalConfig), _token)) {
            ICETH(cToken).mint.value(_amount)();
        } else {
            // uint256 success = ICToken(cToken).mint(_amount);
            require(ICToken(cToken).mint(_amount) == 0, "mint failed");
        }
    }

    function() external payable{}

    function emergencyWithdraw(address _token) external onlyEmergencyAddress {
        SavingLib.emergencyWithdraw(globalConfig, _token);
    }

    /**
     * An account claim all mined FIN token
     */
    function claim() public nonReentrant {
        uint FINAmount = globalConfig.accounts().claim(msg.sender);
        IERC20(globalConfig.tokenInfoRegistry().addressFromIndex(11)).safeTransfer(msg.sender, FINAmount);

        emit Claim(msg.sender, FINAmount);
    }
}
