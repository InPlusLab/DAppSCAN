pragma solidity ^0.6.6;

import {IERC20} from "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";

/**
 * @title ILimaToken
 * @author Lima Protocol
 *
 * Interface for operating with LimaTokens.
 */
interface ILimaToken is IERC20 {
    /* ============ Functions ============ */
    
    function create(IERC20 _investmentToken, uint256 _amount, address _recipient, uint256 _minimumReturn) external returns (bool);
    function redeem(IERC20 _payoutToken, uint256 _amount, address _recipient, uint256 _minimumReturn) external returns (bool);
    function rebalance(address _bestToken, uint256 _minimumReturn) external returns (bool);
    function getNetTokenValue(address _targetToken) external view returns (uint256 netTokenValue);
    function getNetTokenValueOf(address _targetToken, uint256 _amount) external view returns (uint256 netTokenValue);

    function getUnderlyingTokenBalance() external view returns (uint256 balance);

    function getUnderlyingTokenBalanceOf(uint256 _amount) external view returns (uint256 balance);

    function mint(address _account, uint256 _quantity) external;
    function burn(address _account, uint256 _quantity) external;

    function pause() external;
    function unpause() external;
    function isPaused() external view returns (bool);

    function limaManager() external view returns (address); 
    function isLimaManager() external view returns (bool);
    function renounceLimaManagerOwnership() external;
    function transferLimaManagerOwnership(address _newLimaManager) external;

}