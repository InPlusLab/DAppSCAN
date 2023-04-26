pragma solidity ^0.4.24;


import '../../contracts/openzeppelin-solidity/contracts/ownership/Ownable.sol';


// adapted from:
// https://openzeppelin.org/api/docs/crowdsale_validation_WhitelistedCrowdsale.html

contract  TwoKeyWhitelisted is Ownable {


  mapping(address => bool) public whitelist;

  constructor() Ownable() public {

  }

  function isWhitelisted(address _beneficiary) public view returns(bool) {
    return(whitelist[_beneficiary]);
  }

  /**
   * @dev Adds single address to whitelist.
   * @param _beneficiary Address to be added to the whitelist
   */
  function addToWhitelist(address _beneficiary) public onlyOwner {
    whitelist[_beneficiary] = true;
  }

  /**
   * @dev Adds list of addresses to whitelist. Not overloaded due to limitations with truffle testing.
   * @param _beneficiaries Addresses to be added to the whitelist
   */
  function addManyToWhitelist(address[] _beneficiaries) public onlyOwner {
    for (uint256 i = 0; i < _beneficiaries.length; i++) {
      whitelist[_beneficiaries[i]] = true;
    }
  }

  /**
   * @dev Removes single address from whitelist.
   * @param _beneficiary Address to be removed to the whitelist
   */
  function removeFromWhitelist(address _beneficiary) public onlyOwner {
    whitelist[_beneficiary] = false;
  }


}
