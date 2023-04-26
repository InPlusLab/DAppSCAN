pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2; // to enable structure-type parameter

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../lib/LibMath.sol";
import "../lib/LibTypes.sol";


contract Collateral {
    using LibMathSigned for int256;
    using LibMathUnsigned for uint256;
    using SafeERC20 for IERC20;

    uint256 private constant MAX_DECIMALS = 18;
    int256 private scaler;

    address public collateral;
    mapping(address => LibTypes.CollateralAccount) internal cashBalances;

    event Deposit(address indexed guy, int256 wadAmount, int256 balance);
    event Withdraw(address indexed guy, int256 wadAmount, int256 balance, int256 appliedBalance);
    event ApplyForWithdrawal(address indexed guy, int256 wadAmount, uint256 appliedHeight);
    event Transfer(address indexed from, address indexed to, int256 wadAmount, int256 balanceFrom, int256 balanceTo);
    event InternalUpdateBalance(address indexed guy, int256 wadAmount, int256 balance);

    constructor(address _collateral, uint256 decimals) public {
        require(decimals <= MAX_DECIMALS, "decimals out of range");
        require(_collateral != address(0x0) || (_collateral == address(0x0) && decimals == 18), "invalid decimals");

        collateral = _collateral;
        scaler = (decimals == MAX_DECIMALS ? 1 : 10**(MAX_DECIMALS - decimals)).toInt256();
    }

    // Public functions
    function getCashBalance(address guy) public view returns (LibTypes.CollateralAccount memory) {
        return cashBalances[guy];
    }

    // Internal functions
    function isTokenizedCollateral() internal view returns (bool) {
        return collateral != address(0x0);
    }

    function deposit(address guy, uint256 rawAmount) internal {
        if (rawAmount == 0) {
            return;
        }
        if (isTokenizedCollateral()) {
            IERC20(collateral).safeTransferFrom(guy, address(this), rawAmount);
        }
        int256 wadAmount = toWad(rawAmount);
        cashBalances[guy].balance = cashBalances[guy].balance.add(wadAmount);

        emit Deposit(guy, wadAmount, cashBalances[guy].balance);
    }

    function applyForWithdrawal(address guy, uint256 rawAmount, uint256 delay) internal {
        int256 wadAmount = toWad(rawAmount);
        cashBalances[guy].appliedBalance = wadAmount;
        cashBalances[guy].appliedHeight = block.number.add(delay);

        emit ApplyForWithdrawal(guy, wadAmount, cashBalances[guy].appliedHeight);
    }

    function _withdraw(address payable guy, int256 wadAmount, bool forced) private {
        require(wadAmount > 0, "negtive amount");
        require(wadAmount <= cashBalances[guy].balance, "insufficient balance");
        if (!forced) {
            require(block.number >= cashBalances[guy].appliedHeight, "applied height not reached");
            require(wadAmount <= cashBalances[guy].appliedBalance, "insufficient applied balance");
            cashBalances[guy].appliedBalance = cashBalances[guy].appliedBalance.sub(wadAmount);
        } else {
            cashBalances[guy].appliedBalance = cashBalances[guy].appliedBalance.sub(
                wadAmount.min(cashBalances[guy].appliedBalance)
            );
        }
        cashBalances[guy].balance = cashBalances[guy].balance.sub(wadAmount);
        uint256 rawAmount = toCollateral(wadAmount);
        if (isTokenizedCollateral()) {
            IERC20(collateral).safeTransfer(guy, rawAmount);
        } else {
            guy.transfer(rawAmount);
        }
        emit Withdraw(guy, wadAmount, cashBalances[guy].balance, cashBalances[guy].appliedBalance);
    }

    function withdraw(address payable guy, uint256 rawAmount, bool force) internal {
        if (rawAmount == 0) {
            return;
        }
        int256 wadAmount = toWad(rawAmount);
        _withdraw(guy, wadAmount, force);
    }

    function depositToProtocol(address guy, uint256 rawAmount) internal returns (int256) {
        if (rawAmount == 0) {
            return 0;
        }
        if (isTokenizedCollateral()) {
            IERC20(collateral).safeTransferFrom(guy, address(this), rawAmount);
        }
        return toWad(rawAmount);
    }

    function withdrawFromProtocol(address payable guy, uint256 rawAmount) internal returns (int256) {
        if (rawAmount == 0) {
            return 0;
        }
        if (isTokenizedCollateral()) {
            IERC20(collateral).safeTransfer(guy, rawAmount);
        } else {
            guy.transfer(rawAmount);
        }
        return toWad(rawAmount);
    }

    function withdrawAll(address payable guy) internal {
        if (cashBalances[guy].balance == 0) {
            return;
        }
        require(cashBalances[guy].balance > 0, "insufficient balance");
        _withdraw(guy, cashBalances[guy].balance, true);
    }

    function updateBalance(address guy, int256 wadAmount) internal {
        cashBalances[guy].balance = cashBalances[guy].balance.add(wadAmount);
        emit InternalUpdateBalance(guy, wadAmount, cashBalances[guy].balance);
    }

    // ensure balance >= 0
    function ensurePositiveBalance(address guy) internal returns (uint256 loss) {
        if (cashBalances[guy].balance < 0) {
            loss = cashBalances[guy].balance.neg().toUint256();
            cashBalances[guy].balance = 0;
        }
    }

    function transferBalance(address from, address to, int256 wadAmount) internal {
        if (wadAmount == 0) {
            return;
        }
        require(wadAmount > 0, "bug: invalid transfer amount");

        cashBalances[from].balance = cashBalances[from].balance.sub(wadAmount); // may be negative balance
        cashBalances[to].balance = cashBalances[to].balance.add(wadAmount);

        emit Transfer(from, to, wadAmount, cashBalances[from].balance, cashBalances[to].balance);
    }

    function toWad(uint256 rawAmount) internal view returns (int256) {
        return rawAmount.toInt256().mul(scaler);
    }

    function toCollateral(int256 wadAmount) internal view returns (uint256) {
        return wadAmount.div(scaler).toUint256();
    }
}
