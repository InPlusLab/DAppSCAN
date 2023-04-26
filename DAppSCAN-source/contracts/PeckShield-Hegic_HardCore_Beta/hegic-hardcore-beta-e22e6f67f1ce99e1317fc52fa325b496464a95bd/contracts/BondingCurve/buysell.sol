pragma solidity 0.8.6;

import "./IBondingCurve.sol";

contract BuySell {
    constructor(
        IErc20BondingCurve _usdc20BondingCurve,
        IETHBondingCurve _ethBondingCurve
    ) {
        usdc20BondingCurve = _usdc20BondingCurve;
        ethBondingCurve = _ethBondingCurve;
    }

    IErc20BondingCurve usdc20BondingCurve;
    IETHBondingCurve ethBondingCurve;

    function buysellInOneTxnETH(uint256 tokenAmount) public payable {
        ethBondingCurve.buy{value: msg.value}(tokenAmount);
        ethBondingCurve.sell(tokenAmount);
    }

    function buysellInOneTxnUSDC(uint256 tokenAmount) public {
        usdc20BondingCurve.buy(tokenAmount);
        usdc20BondingCurve.sell(tokenAmount);
    }
}
