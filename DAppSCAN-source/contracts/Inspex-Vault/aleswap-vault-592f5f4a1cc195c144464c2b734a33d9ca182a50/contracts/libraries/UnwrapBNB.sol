//SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@uniswap/lib/contracts/libraries/TransferHelper.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

contract UnwrapBNB {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    address private constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    receive() external payable {}

    function unwrap(uint _amount, address _recipient) external  {
        IWETH(WBNB).withdraw(_amount);
        TransferHelper.safeTransferETH(_recipient, _amount);      
    }

}