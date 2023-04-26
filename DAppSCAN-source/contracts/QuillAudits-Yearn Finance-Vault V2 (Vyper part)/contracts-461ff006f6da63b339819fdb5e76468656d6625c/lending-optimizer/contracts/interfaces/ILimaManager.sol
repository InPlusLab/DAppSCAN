pragma solidity ^0.6.6;

import {IERC20, ILimaToken} from "./ILimaToken.sol";
import {IAmunUser} from "./IAmunUser.sol";


interface ILimaManager is IAmunUser {

    function isInvestmentToken(address _token) external returns (bool);

    function create(ILimaToken _limaToken, IERC20 _investmentToken, uint256 _amount, address _holder) external returns (bool);
    function redeem(ILimaToken _limaToken, IERC20 _payoutToken, uint256 _amount, address _holder) external returns (bool);
    function rebalance(ILimaToken _limaToken, address _bestToken) external returns (bool);
    function getTokenValue(address targetToken) external view returns (bool);
}