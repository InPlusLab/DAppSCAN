pragma solidity ^0.5.0;

import "openzeppelin-solidity/contracts/drafts/TokenVesting.sol";
import "zos-lib/contracts/upgradeability/AdminUpgradeabilityProxy.sol";
import "zos-lib/contracts/upgradeability/ProxyAdmin.sol";


/**
 * This creates the artifacts allowing us to use these 3rd party contracts directly
 */
contract Dependencies is TokenVesting, AdminUpgradeabilityProxy, ProxyAdmin
{
  constructor() internal
    TokenVesting(address(0), 0, 0, 0, false)
    AdminUpgradeabilityProxy(address(0), address(0), '')
  {}
}