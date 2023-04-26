pragma solidity 0.8.6;

interface IETHBondingCurve {
    function buy(uint256 tokenAmount) external payable;

    function sell(uint256 tokenAmount) external;
}

interface IErc20BondingCurve {
    function buy(uint256 tokenAmount) external;

    function sell(uint256 tokenAmount) external;
}
