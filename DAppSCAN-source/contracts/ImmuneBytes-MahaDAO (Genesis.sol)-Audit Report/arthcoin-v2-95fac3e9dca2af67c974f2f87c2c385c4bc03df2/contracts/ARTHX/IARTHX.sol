// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import {IERC20} from '../ERC20/IERC20.sol';
import {IAnyswapV4Token} from '../ERC20/IAnyswapV4Token.sol';
import {IARTHXTaxController} from "./IARTHXTaxController.sol";

/**
 * @title  ARTHShares.
 * @author MahaDAO.
 */
interface IARTHX is IERC20, IAnyswapV4Token {
    function setOwner(address _ownerAddress) external;

    function setOracle(address newOracle) external;

    function setArthController(address _controller) external;

    function setTimelock(address newTimelock) external;

    function setARTHAddress(address arthContractAddress) external;

    function poolMint(address account, uint256 amount) external;

    function poolBurnFrom(address account, uint256 amount) external;

    function setTaxController(IARTHXTaxController controller) external;

    function taxTransfer(
        address spender,
        address receiver,
        uint256 amount
    ) external;
}
