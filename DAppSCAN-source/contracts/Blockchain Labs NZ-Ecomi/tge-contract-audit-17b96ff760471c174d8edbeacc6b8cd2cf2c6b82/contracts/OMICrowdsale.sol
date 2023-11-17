pragma solidity ^0.4.18;
// SWC-102-Outdated Compiler Version: L1
import "./OMIToken.sol";
import "./OMITokenLock.sol";
import "../node_modules/zeppelin-solidity/contracts/math/SafeMath.sol";
import "../node_modules/zeppelin-solidity/contracts/crowdsale/validation/WhitelistedCrowdsale.sol";
import "../node_modules/zeppelin-solidity/contracts/lifecycle/Pausable.sol";

/// @title OMICrowdsale
/// @author Mikel Duffy - <mikel@ecomi.com>
contract OMICrowdsale is WhitelistedCrowdsale, Pausable {
  using SafeMath for uint256;

  /* 
   *  Constants
   */
  uint256 constant crowdsaleStartTime = 1530316800;
  uint256 constant crowdsaleFinishTime = 1538351999;
  uint256 constant crowdsaleUSDGoal = 44625000;
  uint256 constant crowdsaleTokenGoal = 362500000*1e18;
  uint256 constant minimumTokenPurchase = 2500*1e18;
  uint256 constant maximumTokenPurchase = 1000000*1e18;

  /*
   *  Storage
   */
  OMIToken public token;
  OMITokenLock public tokenLock;

  uint256 currentDiscountAmount;
  uint256 public totalUSDRaised;
  uint256 public totalTokensSold;
  bool public isFinalized = false;

  mapping(address => uint256) public purchaseRecords;

  /*
   *  Events
   */
  event RateChanged(uint256 newRate);
  event USDRaisedUpdated(uint256 newTotal);
  event CrowdsaleStarted();
  event CrowdsaleFinished();


  /*
   *  Modifiers
   */
  modifier whenNotFinalized () {
    require(!isFinalized);
    _;
  }

  /*
   *  Public Functions
   */
  /// @dev Contract constructor sets...
  function OMICrowdsale (
    uint256 _startingRate,
    address _ETHWallet,
    address _OMIToken,
    address _OMITokenLock
  )
    Crowdsale(_startingRate, _ETHWallet, ERC20(_OMIToken))
    public
  {
    token = OMIToken(_OMIToken);
    tokenLock = OMITokenLock(_OMITokenLock);
    rate = _startingRate;
  }

  /// @dev Allows the owner to set the current rate for calculating the number of tokens for a purchase.
  /// @dev An external cron job will fetch the ETH/USD daily average from the cryptocompare API and call this function.
  function setRate(uint256 _newRate)
    public
    onlyOwner
    whenNotFinalized
    returns(bool)
  {
    require(_newRate > 0);
    rate = _newRate;
    RateChanged(rate);
    return true;
  }

  /// @dev Allows the owner to update the total amount of USD raised. T
  function setUSDRaised(uint256 _total)
    public
    onlyOwner
    whenNotFinalized
  {
    require(_total > 0);
    totalUSDRaised = _total;
    USDRaisedUpdated(_total);
  }

  /// @dev Gets the purchase records for a given address
  /// @param _beneficiary Tokan purchaser
  function getPurchaseRecord(address _beneficiary) 
    public 
    view 
    isWhitelisted(_beneficiary)
    returns(uint256)
  {
    return purchaseRecords[_beneficiary];
  }

  /*
   *  Internal Functions
   */
  /// @dev Extend parent behavior to check if current stage should close. Must call super to ensure the enforcement of the whitelist.
  /// @param _beneficiary Token purchaser
  /// @param _weiAmount Amount of wei contributed
  function _preValidatePurchase(address _beneficiary, uint256 _weiAmount)
    internal
   {
    super._preValidatePurchase(_beneficiary, _weiAmount);

    // Crowdsale should not be paused
    require(!paused);

    // Crowdsale should not be finalized
    require(!isFinalized);

    uint256 _tokenAmount = _getTokenAmount(_weiAmount);
    // Beneficiary's total should be between the minimum and maximum purchase amounts
    uint256 _totalPurchased = purchaseRecords[_beneficiary].add(_tokenAmount);
    require(_totalPurchased >= minimumTokenPurchase);
    require(_totalPurchased <= maximumTokenPurchase);

    // Must make the purchase from the intended whitelisted address
    require(msg.sender == _beneficiary);

    // Must be after the start time
    require(now >= crowdsaleStartTime);
  }

  /// @dev Overrides parent by storing balances in timelock contract instead of issuing tokens right away.
  /// @param _beneficiary Token purchaser
  /// @param _tokenAmount Amount of tokens purchased
  function _processPurchase(address _beneficiary, uint256 _tokenAmount)
    internal
  {
    // Lock beneficiary's tokens
    uint day = 86400;
    tokenLock.lockTokens(_beneficiary, day.mul(7), _tokenAmount);
  }

  /// @dev Override for extensions that require an internal state to check for validity (current user contributions, etc.)
  /// @param _beneficiary Address receiving the tokens
  /// @param _weiAmount Value in wei involved in the purchase
  function _updatePurchasingState(address _beneficiary, uint256 _weiAmount)
    internal
  {
    uint256 _tokenAmount = _getTokenAmount(_weiAmount);

    // Add token amount to the purchase history
    purchaseRecords[_beneficiary] = purchaseRecords[_beneficiary].add(_tokenAmount);
    
    // Add token amount to total tokens sold
    totalTokensSold = totalTokensSold.add(_tokenAmount);

    // Finish the crowdsale...
    // ...if there is not a minimum purchase left
    if (crowdsaleTokenGoal.sub(totalTokensSold) < minimumTokenPurchase) {
      _finalization();
    }
    // ...if USD funding goal has been reached
    if (totalUSDRaised >= crowdsaleUSDGoal) {
      _finalization();
    }
    // ...if the time is after the crowdsale end time
    if (now > crowdsaleFinishTime) {
      _finalization();
    }
  }

  /// @dev Finalizes crowdsale
  function _finalization()
    internal
    whenNotFinalized
  {
    isFinalized = true;
    tokenLock.finishCrowdsale();
    CrowdsaleFinished();
  }
}
