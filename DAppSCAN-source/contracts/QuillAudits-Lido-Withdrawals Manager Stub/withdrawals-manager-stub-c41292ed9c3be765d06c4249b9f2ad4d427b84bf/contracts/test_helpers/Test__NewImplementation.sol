// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;


/**
 * @dev This is a test helper only, don't use it in production!
 */
contract Test__NewImplementation {
    event SmthHappened();
    event EtherReceived(uint256 amount);

    function wasUpgraded() external pure returns (bool) {
        return true;
    }

    function doSmth() external {
        emit SmthHappened();
    }

    receive() external payable {
        emit EtherReceived(msg.value);
    }
}
