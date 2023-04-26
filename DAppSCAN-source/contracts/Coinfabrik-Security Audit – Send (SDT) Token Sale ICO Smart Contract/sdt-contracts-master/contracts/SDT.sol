pragma solidity ^0.4.18;

import './SendToken.sol';


/**
 * @title To instance SendToken for SEND foundation crowdasale
 * @dev see https://send.sd/token
 */
contract SDT is SendToken {
  string constant public name = "SEND Token";
  string constant public symbol = "SDT";
  uint256 constant public decimals = 18;

  modifier validAddress(address _address) {
    require(_address != address(0x0));
    _;
  }

  /**
  * @dev Constructor
  * @param _sale Address that will hold all vesting allocated tokens
  * @notice contract owner will have special powers in the contract
  * @notice _sale should hold all tokens in production as all pool will be vested
  * @return A uint256 representing the locked amount of tokens
  */
  function SDT(address _sale) public validAddress(_sale) {
    verifiedAddresses[owner] = true;
    totalSupply = 700000000 * 10 ** decimals;
    balances[_sale] = totalSupply;
  }
}
