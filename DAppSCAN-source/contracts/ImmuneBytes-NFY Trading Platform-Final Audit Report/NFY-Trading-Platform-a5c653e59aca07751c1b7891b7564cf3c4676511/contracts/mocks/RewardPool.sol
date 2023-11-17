// SPDX-License-Identifier: MIT

pragma solidity ^0.6.10;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./Ownable.sol";

contract RewardPool is Ownable{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public NFYToken;

    constructor(IERC20 _NFYToken) public {
        NFYToken = _NFYToken;
    }

    function allowTransferToStaking(address _stakingAddress, uint _amount) public onlyOwner() {
        NFYToken.approve(_stakingAddress, _amount);
    }

}
