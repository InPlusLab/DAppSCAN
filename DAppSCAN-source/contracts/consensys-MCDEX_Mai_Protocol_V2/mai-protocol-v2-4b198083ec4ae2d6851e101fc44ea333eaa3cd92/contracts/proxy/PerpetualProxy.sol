pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2; // to enable structure-type parameter

import {LibMathSigned, LibMathUnsigned} from "../lib/LibMath.sol";
import "../lib/LibTypes.sol";
import "../interface/IPerpetual.sol";
import "../interface/IPerpetualProxy.sol";


contract PerpetualProxy {
    using LibTypes for LibTypes.Side;

    IPerpetual perpetual;

    modifier onlyAMM() {
        require(msg.sender == address(perpetual.amm()), "invalid caller");
        _;
    }

    constructor(address _perpetual) public {
        perpetual = IPerpetual(_perpetual);
    }

    function self() public view returns (address) {
        return address(this);
    }

    function status() public view returns (LibTypes.Status) {
        return perpetual.status();
    }

    function devAddress() public view returns (address) {
        return perpetual.devAddress();
    }

    function markPrice() public returns (uint256) {
        return perpetual.markPrice();
    }

    function settlementPrice() public view returns (uint256) {
        return perpetual.settlementPrice();
    }

    // note: do NOT call this function in a non-transaction request, unless you do not care about the broker appliedHeight.
    // because in a call(), block.number is the on-chain height, and it will be 1 more in a transaction
    function currentBroker(address guy) public view returns (address) {
        return perpetual.currentBroker(guy);
    }

    function availableMargin(address guy) public returns (int256) {
        return perpetual.availableMargin(guy);
    }

    function getPoolAccount() public view returns (IPerpetualProxy.PoolAccount memory pool) {
        LibTypes.PositionAccount memory position = perpetual.getPosition(self());
        require(position.side != LibTypes.Side.SHORT, "pool should be long");
        pool.positionSize = position.size;
        pool.positionEntryValue = position.entryValue;
        pool.positionEntrySocialLoss = position.entrySocialLoss;
        pool.positionEntryFundingLoss = position.entryFundingLoss;
        pool.cashBalance = perpetual.getCashBalance(self()).balance;
        pool.socialLossPerContract = perpetual.socialLossPerContract(LibTypes.Side.LONG);
    }

    function cashBalance() public view returns (int256) {
        return perpetual.getCashBalance(self()).balance;
    }

    function positionSize() public view returns (uint256) {
        return perpetual.getPosition(self()).size;
    }

    function positionSide() public view returns (LibTypes.Side) {
        return perpetual.getPosition(self()).side;
    }

    function positionEntryValue() public view returns (uint256) {
        return perpetual.getPosition(self()).entryValue;
    }

    function positionEntrySocialLoss() public view returns (int256) {
        return perpetual.getPosition(self()).entrySocialLoss;
    }

    function positionEntryFundingLoss() public view returns (int256) {
        return perpetual.getPosition(self()).entryFundingLoss;
    }

    function socialLossPerContract(LibTypes.Side side) public view returns (int256) {
        return perpetual.socialLossPerContract(side);
    }

    function transferBalanceIn(address from, uint256 amount) public onlyAMM {
        perpetual.transferCashBalance(from, self(), amount);
    }

    function transferBalanceOut(address to, uint256 amount) public onlyAMM {
        perpetual.transferCashBalance(self(), to, amount);
    }

    function transferBalanceTo(address from, address to, uint256 amount) public onlyAMM {
        perpetual.transferCashBalance(from, to, amount);
    }

    function trade(address guy, LibTypes.Side side, uint256 price, uint256 amount) public onlyAMM returns (uint256) {
        perpetual.tradePosition(self(), side.counterSide(), price, amount);
        return perpetual.tradePosition(guy, side, price, amount);
    }

    function setBrokerFor(address guy, address broker) public onlyAMM {
        perpetual.setBrokerFor(guy, broker);
    }

    function depositFor(address guy, uint256 amount) public onlyAMM {
        perpetual.depositFor(guy, amount);
    }

    function depositEtherFor(address guy) public payable onlyAMM {
        perpetual.depositEtherFor.value(msg.value)(guy);
    }

    function withdrawFor(address payable guy, uint256 amount) public onlyAMM {
        perpetual.withdrawFor(guy, amount);
    }

    function isSafe(address guy) public returns (bool) {
        return perpetual.isSafe(guy);
    }

    function isSafeWithPrice(address guy, uint256 currentMarkPrice) public returns (bool) {
        return perpetual.isSafeWithPrice(guy, currentMarkPrice);
    }

    function isProxySafe() public returns (bool) {
        return perpetual.isSafe(self());
    }

    function isProxySafeWithPrice(uint256 currentMarkPrice) public returns (bool) {
        return perpetual.isSafeWithPrice(self(), currentMarkPrice);
    }

    function isIMSafe(address guy) public returns (bool) {
        return perpetual.isIMSafe(guy);
    }

    function isIMSafeWithPrice(address guy, uint256 currentMarkPrice) public returns (bool) {
        return perpetual.isIMSafeWithPrice(guy, currentMarkPrice);
    }

    function lotSize() public view returns (uint256) {
        return perpetual.getGovernance().lotSize;
    }

    function tradingLotSize() public view returns (uint256) {
        return perpetual.getGovernance().tradingLotSize;
    }
}
