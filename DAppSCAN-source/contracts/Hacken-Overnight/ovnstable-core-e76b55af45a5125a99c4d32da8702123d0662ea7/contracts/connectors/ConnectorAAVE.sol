// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/IConnector.sol";
import "./aave/interfaces/ILendingPool.sol";
import "./aave/interfaces/ILendingPoolAddressesProvider.sol";
import "./aave/interfaces/IPriceOracleGetter.sol";

contract ConnectorAAVE is IConnector, Ownable {
    ILendingPoolAddressesProvider public lpap;

    event UpdatedLpap(address lpap);

    function setLpap(address _lpap) public onlyOwner {
        require(_lpap != address(0), "Zero address not allowed");
        lpap = ILendingPoolAddressesProvider(_lpap);
        emit UpdatedLpap(_lpap);
    }

    function stake(
        address _asset,
        uint256 _amount,
        address _beneficiar
    ) public override {
        ILendingPool pool = ILendingPool(lpap.getLendingPool());
        IERC20(_asset).approve(address(pool), _amount);
        pool.deposit(_asset, _amount, _beneficiar, 0);
    }

    function unstake(
        address _asset,
        uint256 _amount,
        address _to
    ) public override returns (uint256) {
        ILendingPool pool = ILendingPool(lpap.getLendingPool());

        uint256 w = pool.withdraw(_asset, _amount, _to);
        DataTypes.ReserveData memory res = pool.getReserveData(_asset);

        //TODO: use _to to for returning tokens
        IERC20(res.aTokenAddress).transfer(
            msg.sender,
            IERC20(res.aTokenAddress).balanceOf(address(this))
        );
        return w;
    }
}
