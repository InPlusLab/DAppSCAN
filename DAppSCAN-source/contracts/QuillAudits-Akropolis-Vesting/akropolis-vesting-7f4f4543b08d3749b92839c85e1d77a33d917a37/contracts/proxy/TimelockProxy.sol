pragma solidity ^0.5.0;

//Import Upgradeability Template
import "zos-lib/contracts/upgradeability/UpgradeabilityProxy.sol";

//Timelock Template
import '../openzeppelin/TokenTimelock.sol';

//Beneficieries template
import "../helpers/BeneficiaryOperations.sol";


/**
* @title TimelockProxy
* @notice A proxy contract that serves the latest implementation of TimelockProxy.
*/

contract TimelockProxy is UpgradeabilityProxy, TokenTimelock, BeneficiaryOperations {


    constructor (address _implementation, IERC20 _token, address _beneficiary, uint256 _releaseTime)
        UpgradeabilityProxy(_implementation, "") 
        TokenTimelock(_token, msg.sender, _releaseTime) public  {} 
    

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


