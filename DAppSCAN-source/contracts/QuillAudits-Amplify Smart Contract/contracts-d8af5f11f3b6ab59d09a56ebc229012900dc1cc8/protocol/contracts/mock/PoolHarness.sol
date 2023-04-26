// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../Liquidity/Pool.sol";

contract PoolHarness is Pool {

    uint public blockNumber;
    uint public blockTimestamp;

    uint internal _totalPrincipal;
    uint internal _totalSupply;
    uint internal _totalBorrows;
    uint internal _totalInterestRate;

    constructor() Pool(){}

    function fastForward(uint blocks) public returns (uint) {
        blockNumber += blocks;
        return blockNumber;
    }

    function fastTimestamp(uint days_) public returns (uint) {
        blockTimestamp += days_ * 24 * 60 * 60;
        return blockTimestamp;
    }

    function setBlockNumber(uint number) public {
        blockNumber = number;
    }

    function setBlockTimestamp(uint timestamp) public {
        blockTimestamp = timestamp;
    }

    function setTotalPrincipal(uint principal) public {
        _totalPrincipal = principal;
    }

    function setTotalSupply(uint supply) public {
        _totalSupply = supply;
    }

    function setTotalInterestRate(uint rate) public {
        _totalInterestRate = rate;
    }

    function setTotalBorrows(uint borrows) public {
        _totalBorrows = borrows;
    }

    function getBlockNumber() public override view returns (uint) {
        return blockNumber;
    }

    function getBlockTimestamp() public override view returns (uint) {
        return blockTimestamp;
    }

    function totalPrincipal() public override view returns (uint) {
        if(_totalPrincipal == 0) {
            return super.totalPrincipal();
        }
        return _totalPrincipal;
    }

    function totalInterestRate() public override view returns (uint256) {
        if(_totalInterestRate == 0) {
            return super.totalInterestRate();
        }
        return _totalInterestRate;
    }

    function totalSupply() public override view returns (uint) {
        if(_totalSupply == 0) {
            return super.totalSupply();
        }
        return _totalSupply;
    }

    function getTotalBorrowBalance() public override view returns (uint) {
        if(_totalBorrows == 0) {
            return super.getTotalBorrowBalance();
        }
        return _totalBorrows;
    }
}