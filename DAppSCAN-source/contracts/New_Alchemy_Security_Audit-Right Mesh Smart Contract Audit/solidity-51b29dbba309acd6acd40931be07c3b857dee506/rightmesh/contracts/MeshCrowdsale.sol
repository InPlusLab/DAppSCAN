pragma solidity ^0.4.18;

import './MeshToken.sol';
import 'zeppelin-solidity/contracts/crowdsale/CappedCrowdsale.sol';
import 'zeppelin-solidity/contracts/math/SafeMath.sol';
import 'zeppelin-solidity/contracts/ownership/Ownable.sol';


/**
 * CappedCrowdsale limits the total number of wei that can be collected in the sale.
 */
contract MeshCrowdsale is CappedCrowdsale, Ownable {

  using SafeMath for uint256;

  /**
   * @dev weiLimits keeps track of amount of wei that can be contibuted by an address.
   */
  mapping (address => uint256) public weiLimits;

  /**
   * @dev weiContributions keeps track of amount of wei that are contibuted by an address.
   */
  mapping (address => uint256) public weiContributions;

  /**
   * @dev whitelistingAgents keeps track of who is allowed to call the setLimit method
   */
  mapping (address => bool) public whitelistingAgents;

  /**
   * @dev minimumContribution keeps track of what should be the minimum contribution required per address
   */
  uint256 public minimumContribution;

  /**
   * @dev variable to keep track of beneficiaries for which we need to mint the tokens directly
   */
  address[] public beneficiaries;

  /**
   * @dev variable to keep track of amount og tokens to mint for beneficiaries
   */
  uint256[] public beneficiaryAmounts;

  /*---------------------------------constructor---------------------------------*/

  /**
   * @dev Constructor for MeshCrowdsale contract
   */
  function MeshCrowdsale(uint256 _startTime, uint256 _endTime, uint256 _rate, address _wallet, uint256 _cap, uint256 _minimumContribution, MeshToken _token, address[] _beneficiaries, uint256[] _beneficiaryAmounts)
  CappedCrowdsale(_cap)
  Crowdsale(_startTime, _endTime, _rate, _wallet, _token)
  public
  {
    require(_beneficiaries.length == _beneficiaryAmounts.length);
    beneficiaries = _beneficiaries;
    beneficiaryAmounts = _beneficiaryAmounts;

    minimumContribution = _minimumContribution;
  }

  /*---------------------------------overridden methods---------------------------------*/

  /**
   * overriding Crowdsale#buyTokens to keep track of wei contributed per address
   */
  function buyTokens(address beneficiary) public payable {
    weiContributions[msg.sender] = weiContributions[msg.sender].add(msg.value);
    super.buyTokens(beneficiary);
  }

  /**
   * overriding CappedCrowdsale#validPurchase to add extra contribution limit logic
   * @return true if investors can buy at the moment
   */
  function validPurchase() internal view returns (bool) {
    bool withinLimit = weiContributions[msg.sender] <= weiLimits[msg.sender];
    bool atleastMinimumContribution = weiContributions[msg.sender] >= minimumContribution;
    return atleastMinimumContribution && withinLimit && super.validPurchase();
  }



  /*---------------------------------new methods---------------------------------*/


  /**
   * @dev Allows owner to add / remove whitelistingAgents
   * @param _address that is being allowed or removed from whitelisting addresses
   * @param _value boolean indicating if address is whitelisting agent or not
   * @return boolean indicating function success.
   */
  function setWhitelistingAgent(address _address, bool _value) external onlyOwner returns (bool) {
    whitelistingAgents[_address] = _value;
    return true;
  }

  /**
   * @dev Allows the current owner to update contribution limits
   * @param _addresses whose contribution limits should be changed
   * @param _weiLimit new contribution limit
   * @return boolean indicating function success.
   */
  function setLimit(address[] _addresses, uint256 _weiLimit) external returns (bool) {
    require(whitelistingAgents[msg.sender] == true);

    for (uint i = 0; i < _addresses.length; i++) {
      address _address = _addresses[i];

      // only allow changing the limit to be greater than current contribution
      if(_weiLimit >= weiContributions[_address]) {
        weiLimits[_address] = _weiLimit;
      }
    }
    return true;
  }

  /**
   * @dev Allows the current owner to change the ETH to token generation rate.
   * @param _rate indicating the new token generation rate.
   * @return boolean indicating function success.
   */
  function setRate(uint256 _rate) external onlyOwner returns (bool) {
    // make sure the crowdsale has not started
    require(weiRaised == 0);

    // make sure new rate is greater than 0
    require(_rate > 0);

    rate = _rate;
    return true;
  }


  /**
   * @dev Allows the current owner to change the crowdsale cap.
   * @param _cap indicating the new crowdsale cap.
   * @return boolean indicating function success.
   */
  function setCap(uint256 _cap) external onlyOwner returns (bool) {
    // make sure the crowdsale has not started
    require(weiRaised == 0);

    // make sure new cap is greater than 0
    require(_cap > 0);

    cap = _cap;
    return true;
  }

  /**
   * @dev Allows the current owner to change the required minimum contribution.
   * @param _minimumContribution indicating the minimum required contribution.
   * @return boolean indicating function success.
   */
  function setMinimumContribution(uint256 _minimumContribution) external onlyOwner returns (bool) {
    minimumContribution = _minimumContribution;
    return true;
  }

  /*
   * @dev Function to perform minting to predefined beneficiaries once crowdsale has started
   * can be called by anyone as the outcome is fixed and does not depend on who is calling the method
   * can be called multiple times but will only do the minting once per address
   */
  function mintPredefinedTokens() external onlyOwner returns (bool) {
    // make sure the crowdsale has started
    require(weiRaised > 0);

    // loop through the list and call mint on token directly
    // this minting does not affect any crowdsale numbers
    for (uint i = 0; i < beneficiaries.length; i++) {
      if (beneficiaries[i] != address(0) && token.balanceOf(beneficiaries[i]) == 0) {
        token.mint(beneficiaries[i], beneficiaryAmounts[i]);
      }
    }
  }

  /*---------------------------------proxy methods for token when owned by contract---------------------------------*/
  /**
   * @dev Allows the current owner to transfer token control back to contract owner
   */
  function transferTokenOwnership() external onlyOwner {
    token.transferOwnership(owner);
  }
}
