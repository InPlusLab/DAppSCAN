pragma solidity >=0.4.24;

import "zos-lib/contracts/upgradeability/UpgradeabilityProxy.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";

/** 
 * @title DelayedUpgradeabilityProxy
 * @notice Implements an upgradeability proxy with the option of
 * introducing pending implementations. 
 */
contract DelayedUpgradeabilityProxy is UpgradeabilityProxy {
    using SafeMath for uint256;

    address public pendingImplementation;
    bool public pendingImplementationIsSet;
    uint256 public pendingImplementationApplicationDate; // Date on which to switch all contract calls to the new implementation
    uint256 public UPGRADE_DELAY = 4 weeks;

    event PendingImplementationChanged(address indexed oldPendingImplementation, address indexed newPendingImplementation);

    constructor(address _implementation) public UpgradeabilityProxy(_implementation) {}

    /**
    * @notice Sets the pending implementation address of the proxy.
    * This function is internal--uses of this proxy should wrap this function
    * with a public function in order to make it externally callable.
    * @param implementation Address of the new implementation.
    */
    function _setPendingUpgrade(address implementation) internal {
        address oldPendingImplementation = pendingImplementation;
        pendingImplementation = implementation;
        pendingImplementationIsSet = true;
        emit PendingImplementationChanged(oldPendingImplementation, implementation);
        pendingImplementationApplicationDate = block.timestamp.add(UPGRADE_DELAY);
    }

    /**
    * @notice Overrides the _willFallback() function of Proxy, which enables some code to
    * be executed prior to the fallback function. In this case, the purpose of this code
    * is to automatically switch the implementation to the pending implementation if the 
    * wait period of UPGRADE_DELAY (28 days) has been satisfied.
    */
    function _willFallback() internal {
        if (pendingImplementationIsSet && block.timestamp > pendingImplementationApplicationDate) {
            _upgradeTo(pendingImplementation);
            pendingImplementationIsSet = false;
            super._willFallback();
        }
        else {
            super._willFallback();
        }
    }
}
