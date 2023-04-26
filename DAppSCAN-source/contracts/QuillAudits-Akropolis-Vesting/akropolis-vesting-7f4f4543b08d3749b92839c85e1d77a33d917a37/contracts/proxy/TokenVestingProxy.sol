pragma solidity ^0.5.0;

//Import Upgradeability Template
import "zos-lib/contracts/upgradeability/UpgradeabilityProxy.sol";

//Timelock Template
import '../openzeppelin/TokenVesting.sol';

//Beneficieries template
import "../helpers/BeneficiaryOperations.sol";


/**
* @title TokenVestingProxy
* @notice A proxy contract that serves the latest implementation of TokenVestingProxy.
*/

contract TokenVestingProxy is UpgradeabilityProxy, TokenVesting, BeneficiaryOperations {

    IERC20 private token;

    constructor (address _implementation, IERC20 _token, address _beneficiary, uint256 _start, uint256 _cliffDuration, uint256 _duration)
        UpgradeabilityProxy(_implementation, "")
        TokenVesting(_beneficiary, _start, _cliffDuration, _duration, false) public {
            token = _token;
    }
    
    /**
    * @dev Upgrade the backing implementation of the proxy.
    * Only the group of beneficiaries can call this function.
    * @param newImplementation Address of the new implementation.
    */
    function upgradeTo(address newImplementation) public onlyManyBeneficiaries  {
        _upgradeTo(newImplementation);
    }

    /**
    * @return The address of the implementation.
    */
    function implementation() public view returns (address) {
        return _implementation();
    }
}


