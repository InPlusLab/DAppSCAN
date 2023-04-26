pragma solidity ^0.4.15;

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

  /*---------------------------------constructor---------------------------------*/

  /**
   * @dev Constructor for MeshCrowdsale contract
   */
  function MeshCrowdsale(uint256 _startTime, uint256 _endTime, uint256 _rate, address _wallet, uint256 _cap, MeshToken _token)
  CappedCrowdsale(_cap)
  Crowdsale(_startTime, _endTime, _rate, _wallet, _token)
  public
  {}

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
    return withinLimit && super.validPurchase();
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
      require(_weiLimit >= weiContributions[_address]);
      weiLimits[_address] = _weiLimit;
    }
    return true;
  }

  /**
   * @dev Allows the current owner to change the ETH to token generation rate.
   * @param _rate indicating the new token generation rate.
   * @return boolean indicating function success.
   */
  function setRate(uint256 _rate) external onlyOwner returns (bool) {
    rate = _rate;
    return true;
  }

  /*---------------------------------proxy methods for token when owned by contract---------------------------------*/
  /**
   * @dev Allows the current owner to transfer token control back to contract owner
   */
  function transferTokenOwnership() external onlyOwner {
    token.transferOwnership(owner);
  }

  /**
   * @dev Allows the contract owner to pause the token transfers on deployed token
   */
  function pauseToken() external onlyOwner {
    MeshToken(token).pause();
  }

  /**
   * @dev Allows the contract owner to unpause the token transfers on deployed token
   */
  function unpauseToken() external onlyOwner {
    MeshToken(token).unpause();
  }
}
