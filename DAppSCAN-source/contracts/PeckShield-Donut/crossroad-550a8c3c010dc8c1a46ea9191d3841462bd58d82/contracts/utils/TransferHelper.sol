// SPDX-License-Identifier: MIT

pragma solidity 0.8.3;

library TransferHelper
{
    function safeTransferETH(address to, uint value) internal {
        (bool success,) = to.call{value:value}(new bytes(0));
        require(success, 'TransferHelper: ETH_TRANSFER_FAILED');
    }
}
