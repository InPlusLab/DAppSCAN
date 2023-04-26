// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/IConnector.sol";
import "./idle/interfaces/IIdleToken.sol";

contract ConnectorIDLE is IConnector, Ownable {

    IIdleToken public idleToken;

    function setIdleToken(address _idleToken) public onlyOwner {
        require(_idleToken != address(0), "Zero address not allowed");
        idleToken = IIdleToken(_idleToken);
    }

    function stake(
        address _asset,
        uint256 _amount,
        address _beneficiar
    ) public override {
        IERC20(_asset).approve(address(idleToken), _amount);
        uint256 mintedTokens = idleToken.mintIdleToken(_amount, true, _beneficiar);
        IERC20(address (idleToken)).transfer(_beneficiar, mintedTokens);
    }

    function unstake(
        address _asset,
        uint256 _amount,
        address _beneficiar
    ) public override returns (uint256) {
        uint256 redeemedTokens = idleToken.redeemIdleToken(_amount);
        IERC20(_asset).transfer(_beneficiar, redeemedTokens);
        return redeemedTokens;
    }

}
