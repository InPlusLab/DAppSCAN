pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2; // to enable structure-type parameter
// SWC-135-Code With No Effects: L4-5
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../lib/LibOrder.sol";
import "../lib/LibTypes.sol";
import {LibMathSigned, LibMathUnsigned} from "../lib/LibMath.sol";

import "./Position.sol";
import "./Brokerage.sol";

import "../interface/IPriceFeeder.sol";
import "../interface/IGlobalConfig.sol";


contract Perpetual is Brokerage, Position {
    using LibMathSigned for int256;
    using LibMathUnsigned for uint256;
    using LibOrder for LibTypes.Side;
    using SafeERC20 for IERC20;
    uint256 public totalAccounts;
    address[] public accountList;
    mapping(address => bool) private accountCreated;

    event CreatePerpetual();
    event CreateAccount(uint256 indexed id, address indexed guy);
    event Buy(address indexed guy, uint256 price, uint256 amount);
    event Sell(address indexed guy, uint256 price, uint256 amount);
    event Liquidate(address indexed keeper, address indexed guy, uint256 price, uint256 amount);
    event EndGlobalSettlement();
    // SWC-119-Shadowing State Variables: L34-41
    constructor(address globalConfig, address devAddress, address collateral, uint256 collateralDecimals)
        public
        Position(collateral, collateralDecimals)
    {
        setGovernanceAddress("globalConfig", globalConfig);
        setGovernanceAddress("dev", devAddress);
        emit CreatePerpetual();
    }

    // Admin functions
    function setCashBalance(address guy, int256 amount) public onlyWhitelistAdmin {
        require(status == LibTypes.Status.SETTLING, "wrong perpetual status");
        int256 deltaAmount = amount.sub(cashBalances[guy].balance);
        cashBalances[guy].balance = amount;
        emit InternalUpdateBalance(guy, deltaAmount, amount);
    }

    // Public functions
    function() external payable {
        revert("no payable");
    }

    function markPrice() public ammRequired returns (uint256) {
        return status == LibTypes.Status.NORMAL ? amm.currentMarkPrice() : settlementPrice;
    }

    function setBroker(address broker) public {
        setBroker(msg.sender, broker, globalConfig.brokerLockBlockCount());
    }

    function setBrokerFor(address guy, address broker) public onlyWhitelisted {
        setBroker(guy, broker, globalConfig.brokerLockBlockCount());
    }

    function depositToAccount(address guy, uint256 amount) private {
        require(guy != address(0), "invalid guy");
        deposit(guy, amount);

        // append to the account list. make the account trackable
        if (!accountCreated[guy]) {
            emit CreateAccount(totalAccounts, guy);
            accountList.push(guy);
            totalAccounts++;
            accountCreated[guy] = true;
        }
    }

    function depositFor(address guy, uint256 amount) public onlyWhitelisted {
        require(isTokenizedCollateral(), "token not acceptable");

        depositToAccount(guy, amount);
    }

    function depositEtherFor(address guy) public payable onlyWhitelisted {
        require(!isTokenizedCollateral(), "ether not acceptable");

        depositToAccount(guy, msg.value);
    }

    function deposit(uint256 amount) public {
        require(isTokenizedCollateral(), "token not acceptable");

        depositToAccount(msg.sender, amount);
    }

    function depositEther() public payable {
        require(!isTokenizedCollateral(), "ether not acceptable");

        depositToAccount(msg.sender, msg.value);
    }

    // this is a composite function of perp.deposit + perp.setBroker
    // composite functions accept amount = 0
    function depositAndSetBroker(uint256 amount, address broker) public {
        setBroker(broker);
        if (amount > 0) {
            deposit(amount);
        }
    }

    // this is a composite function of perp.deposit + perp.setBroker
    // composite functions accept amount = 0
    function depositEtherAndSetBroker(address broker) public payable {
        setBroker(broker);
        if (msg.value > 0) {
            depositEther();
        }
    }

    function applyForWithdrawal(uint256 amount) public {
        applyForWithdrawal(msg.sender, amount, globalConfig.withdrawalLockBlockCount());
    }

    function settleFor(address guy) private {
        uint256 currentMarkPrice = markPrice();
        LibTypes.PositionAccount memory account = positions[guy];
        if (account.size > 0) {
            int256 pnl = close(account, currentMarkPrice, account.size);
            updateBalance(guy, pnl);
            positions[guy] = account;
        }
        emit UpdatePositionAccount(guy, account, totalSize(LibTypes.Side.LONG), currentMarkPrice);
    }

    function settle() public {
        require(status == LibTypes.Status.SETTLED, "wrong perpetual status");

        address payable guy = msg.sender;
        settleFor(guy);
        withdrawAll(guy);
    }

    function endGlobalSettlement() public onlyWhitelistAdmin {
        require(status == LibTypes.Status.SETTLING, "wrong perpetual status");

        address guy = address(amm.perpetualProxy());
        settleFor(guy);
        status = LibTypes.Status.SETTLED;

        emit EndGlobalSettlement();
    }

    function withdrawFromAccount(address payable guy, uint256 amount) private {
        require(guy != address(0), "invalid guy");
        require(status != LibTypes.Status.SETTLING, "wrong perpetual status");

        uint256 currentMarkPrice = markPrice();
        require(isSafeWithPrice(guy, currentMarkPrice), "unsafe before withdraw");
        remargin(guy, currentMarkPrice);
        address broker = currentBroker(guy);
        bool forced = broker == address(amm.perpetualProxy()) || broker == address(0);
        withdraw(guy, amount, forced);

        require(isSafeWithPrice(guy, currentMarkPrice), "unsafe after withdraw");
        require(availableMarginWithPrice(guy, currentMarkPrice) >= 0, "withdraw margin");
    }

    function withdrawFor(address payable guy, uint256 amount) public onlyWhitelisted {
        require(status == LibTypes.Status.NORMAL, "wrong perpetual status");
        withdrawFromAccount(guy, amount);
    }

    function withdraw(uint256 amount) public {
        withdrawFromAccount(msg.sender, amount);
    }

    function depositToInsuranceFund(uint256 rawAmount) public {
        require(isTokenizedCollateral(), "token not acceptable");
        require(rawAmount > 0, "invalid amount");

        int256 wadAmount = depositToProtocol(msg.sender, rawAmount);
        insuranceFundBalance = insuranceFundBalance.add(wadAmount);

        require(insuranceFundBalance >= 0, "negtive insurance fund");

        emit UpdateInsuranceFund(insuranceFundBalance);
    }

    function depositEtherToInsuranceFund() public payable {
        require(!isTokenizedCollateral(), "ether not acceptable");
        require(msg.value > 0, "invalid amount");

        int256 wadAmount = depositToProtocol(msg.sender, msg.value);
        insuranceFundBalance = insuranceFundBalance.add(wadAmount);

        require(insuranceFundBalance >= 0, "negtive insurance fund");

        emit UpdateInsuranceFund(insuranceFundBalance);
    }

    function withdrawFromInsuranceFund(uint256 rawAmount) public onlyWhitelistAdmin {
        require(rawAmount > 0, "invalid amount");
        require(insuranceFundBalance > 0, "insufficient funds");
        require(rawAmount <= insuranceFundBalance.toUint256(), "insufficient funds");

        int256 wadAmount = toWad(rawAmount);
        insuranceFundBalance = insuranceFundBalance.sub(wadAmount);
        withdrawFromProtocol(msg.sender, rawAmount);

        require(insuranceFundBalance >= 0, "negtive insurance fund");

        emit UpdateInsuranceFund(insuranceFundBalance);
    }

    function positionMargin(address guy) public returns (uint256) {
        return Position.marginWithPrice(guy, markPrice());
    }

    function maintenanceMargin(address guy) public returns (uint256) {
        return maintenanceMarginWithPrice(guy, markPrice());
    }

    function marginBalance(address guy) public returns (int256) {
        return marginBalanceWithPrice(guy, markPrice());
    }

    function pnl(address guy) public returns (int256) {
        return pnlWithPrice(guy, markPrice());
    }

    function availableMargin(address guy) public returns (int256) {
        return availableMarginWithPrice(guy, markPrice());
    }

    function drawableBalance(address guy) public returns (int256) {
        return drawableBalanceWithPrice(guy, markPrice());
    }

    // safe for liquidation
    function isSafe(address guy) public returns (bool) {
        uint256 currentMarkPrice = markPrice();
        return isSafeWithPrice(guy, currentMarkPrice);
    }

    // safe for liquidation
    function isSafeWithPrice(address guy, uint256 currentMarkPrice) public returns (bool) {
        return
            marginBalanceWithPrice(guy, currentMarkPrice) >=
            maintenanceMarginWithPrice(guy, currentMarkPrice).toInt256();
    }

    function isBankrupt(address guy) public returns (bool) {
        return marginBalanceWithPrice(guy, markPrice()) < 0;
    }

    // safe for opening positions
    function isIMSafe(address guy) public returns (bool) {
        uint256 currentMarkPrice = markPrice();
        return isIMSafeWithPrice(guy, currentMarkPrice);
    }

    // safe for opening positions
    function isIMSafeWithPrice(address guy, uint256 currentMarkPrice) public returns (bool) {
        return availableMarginWithPrice(guy, currentMarkPrice) >= 0;
    }
    // SWC-105-Unprotected Ether Withdrawal: L270-289
    function liquidateFrom(address from, address guy, uint256 maxAmount) public returns (uint256, uint256) {
        require(maxAmount.mod(governance.lotSize) == 0, "invalid lot size");
        require(!isSafe(guy), "safe account");

        uint256 liquidationPrice = markPrice();
        uint256 liquidationAmount = calculateLiquidateAmount(guy, liquidationPrice);
        uint256 totalPositionSize = positions[guy].size;
        uint256 liquidatableAmount = totalPositionSize.sub(totalPositionSize.mod(governance.lotSize));
        liquidationAmount = liquidationAmount.ceil(governance.lotSize).min(maxAmount).min(liquidatableAmount);
        require(liquidationAmount > 0, "nothing to liquidate");

        uint256 opened = liquidate(from, guy, liquidationPrice, liquidationAmount);
        if (opened > 0) {
            require(availableMarginWithPrice(from, liquidationPrice) >= 0, "liquidator margin");
        } else {
            require(isSafe(from), "liquidator unsafe");
        }

        emit Liquidate(from, guy, liquidationPrice, liquidationAmount);
    }

    function liquidate(address guy, uint256 maxAmount) public returns (uint256, uint256) {
        require(status != LibTypes.Status.SETTLED, "wrong perpetual status");
        return liquidateFrom(msg.sender, guy, maxAmount);
    }

    function tradePosition(address trader, LibTypes.Side side, uint256 price, uint256 amount)
        public
        onlyWhitelisted
        returns (uint256)
    {
        require(status != LibTypes.Status.SETTLING, "wrong perpetual status");
        require(side == LibTypes.Side.LONG || side == LibTypes.Side.SHORT, "invalid side");

        uint256 opened = Position.trade(trader, side, price, amount);
        if (side == LibTypes.Side.LONG) {
            emit Buy(trader, price, amount);
        } else if (side == LibTypes.Side.SHORT) {
            emit Sell(trader, price, amount);
        }
        return opened;
    }

    function transferCashBalance(address from, address to, uint256 amount) public onlyWhitelisted {
        require(status != LibTypes.Status.SETTLING, "wrong perpetual status");
        transferBalance(from, to, amount.toInt256());
    }
}
