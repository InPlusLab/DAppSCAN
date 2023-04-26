pragma solidity ^0.4.23;

import "./classes/token/IToken.sol";
import "./classes/sale/ISale.sol";
import "./classes/admin/IAdmin.sol";

interface IDutchCrowdsale {
  function init(address, uint, uint, uint, uint, uint, uint, bool, address, bool) external;
}
