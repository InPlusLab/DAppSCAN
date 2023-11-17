// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { IERC20 } from "../lib/erc20/src/interfaces/IERC20.sol";

/**
 * @title Small Library to standardize erc20 token interactions. 
 * @dev   Code taken from https://github.com/maple-labs/erc20-helper
 * @dev   Acknowledgements to Solmate, OpenZeppelin, and Uniswap-V3 for inspiring this code.
 */
library ERC20Helper {

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    function transfer(address token, address to, uint256 amount) internal returns (bool) {
        return _call(token, abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
    }

    function transferFrom(address token, address from, address to, uint256 amount) internal returns (bool) {
        return _call(token, abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, amount));
    }

    function approve(address token, address spender, uint256 amount) internal returns (bool) {
        return _call(token, abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
    }

    function _call(address token, bytes memory data) private returns (bool success) {
        bytes memory returnData;
        (success, returnData) = token.call(data);

        return success && (returnData.length == 0 || abi.decode(returnData, (bool)));
    }

}
