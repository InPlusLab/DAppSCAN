pragma solidity ^0.6.2;

import {ILimaTokenStorage} from "./ILimaTokenStorage.sol";
import {IInvestmentToken} from "./IInvestmentToken.sol";
import {IAmunUser} from "./IAmunUser.sol";

/**
 * @title ILimaTokenHelper
 * @author Lima Protocol
 *
 * Standard ILimaTokenHelper.
 */
interface ILimaTokenHelper is IInvestmentToken, IAmunUser, ILimaTokenStorage {
    function getNetTokenValue(address _targetToken)
        external
        view
        returns (uint256 netTokenValue);

    function getNetTokenValueOf(address _targetToken, uint256 _amount)
        external
        view
        returns (uint256 netTokenValue);

    function getExpectedReturn(
        address _from,
        address _to,
        uint256 _amount
    ) external view returns (uint256 returnAmount);

    function getUnderlyingTokenBalance()
        external
        view
        returns (uint256 balance);

    function getUnderlyingTokenBalanceOf(uint256 _amount)
        external
        view
        returns (uint256 balanceOf);

    function getPayback(uint256 gas) external view returns (uint256);

    function isReceiveOracleData(bytes32 _requestId,  address _msgSender) external view;

    function getPerformanceFee()
        external
        view
        returns (uint256 performanceFeeToWallet);

    function getFee(uint256 _amount, uint256 _fee)
        external
        view
        returns (uint256 feeAmount);

    function getExpectedReturnRedeem(uint256 _amount, address _to)
        external
        view
        returns (uint256 minimumReturn);

    function getExpectedReturnCreate(uint256 _amount, address _from)
        external
        view
        returns (uint256 minimumReturn);

    function getExpectedReturnRebalance(
        address _bestToken,
        uint256 _amountToSellForLink
    )
        external
        view
        returns (
            uint256 tokenPosition,
            uint256 minimumReturn,
            uint256 minimumReturnGov,
            uint256 minimumReturnLink
        );

    function decodeOracleData(bytes32 data)
        external
        view
        returns (
            address addr,
            uint256 a,
            uint256 b,
            uint256 c
        );
}
