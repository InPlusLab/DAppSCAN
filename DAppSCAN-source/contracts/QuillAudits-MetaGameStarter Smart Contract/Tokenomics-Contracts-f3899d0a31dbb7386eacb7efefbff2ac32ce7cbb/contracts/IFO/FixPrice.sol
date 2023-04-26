// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../ProxyClones/OwnableForClones.sol";
import "./AggregatorV3Interface.sol";

/**

    ✩░▒▓▆▅▃▂▁𝐌𝐞𝐭𝐚𝐆𝐚𝐦𝐞𝐇𝐮𝐛▁▂▃▅▆▓▒░✩

*/


contract MGHPublicOffering is OwnableForClones {

  // chainlink impl. to get any kind of pricefeed
  AggregatorV3Interface internal priceFeed;

  // The LP token used
  IERC20 public lpToken;

  // The offering token
  IERC20 public offeringToken;

  // The block number when IFO starts
  uint256 public startBlock;

  // The block number when IFO ends
  uint256 public endBlock;

  //after this block harvesting is possible
  uint256 private harvestBlock;

  // maps the user-address to the deposited amount in that Pool
  mapping(address => uint256) private amount;

  // amount of tokens offered for the pool (in offeringTokens)
  uint256 private offeringAmount;

  // price in MGH/USDT => for 1 MGH/USDT price would be 10**12; 10MGH/USDT would be 10**13
  uint256 private _price;

  // total amount deposited in the Pool (in LP tokens); resets when new Start and EndBlock are set
  uint256 private totalAmount;

  // Admin withdraw event
  event AdminWithdraw(uint256 amountLP, uint256 amountOfferingToken, uint256 amountWei);

  // Admin recovers token
  event AdminTokenRecovery(address tokenAddress, uint256 amountTokens);

  // Deposit event
  event Deposit(address indexed user, uint256 amount);

  // Harvest event
  event Harvest(address indexed user, uint256 offeringAmount);

  // Event for new start & end blocks
  event NewStartAndEndBlocks(uint256 startBlock, uint256 endBlock);

  // parameters are set for the pool
  event PoolParametersSet(uint256 offeringAmount, uint256 price);

  // timeLock ensures that users have enough time to harvest before Admin withdraws tokens,
  // sets new Start and EndBlocks or changes Pool specifications
  modifier timeLock() {
    require(block.number > harvestBlock, "admin must wait before calling this function");
    _;
  }

  /**
    * @dev It can only be called once.
    * @param _lpToken the LP token used
    * @param _offeringToken the token that is offered for the IFO
    * @param _offeringAmount amount without decimals
    * @param __price the price in OfferingToken/LPToken adjusted already by 6 decimal places
    * @param _startBlock start of sale time
    * @param _endBlock end of sale time
    * @param _harvestBlock start of harvest time
    * @param _adminAddress the admin address
  */
  function initialize(
    address _lpToken,
    address _offeringToken,
    address _priceFeed,
    address _adminAddress,
    uint256 _offeringAmount,
    uint256 __price,
    uint256 _startBlock,
    uint256 _endBlock,
    uint256 _harvestBlock
    )
    external initializer
    {
    __Ownable_init();
    lpToken = IERC20(_lpToken);
    offeringToken = IERC20(_offeringToken);
    priceFeed = AggregatorV3Interface(_priceFeed);
    setPool(_offeringAmount*10**18, __price*10**6);
    updateStartAndEndBlocks(_startBlock, _endBlock, _harvestBlock);
    transferOwnership(_adminAddress);
  }

  /**
    * @notice It allows users to deposit LP tokens opr ether to pool
    * @param _amount: the number of LP token used (6 decimals)
  */
  function deposit(uint256 _amount) external payable {

    // Checks whether the block number is not too early
    require(block.number > startBlock && block.number < endBlock, "Not sale time");

    // Transfers funds to this contract
    if (_amount > 0) {
      require(lpToken.transferFrom(address(msg.sender), address(this), _amount));
  	}
    // Updates the totalAmount for pool
    if (msg.value > 0) {
      _amount += uint256(getLatestEthPrice()) * msg.value / 1e20;
    }
    totalAmount += _amount;

    // if its pool1, check if new total amount will be smaller or equal to OfferingAmount / price
    require(
      offeringAmount >= totalAmount * _price,
      "not enough tokens left"
    );

    // Update the user status
    amount[msg.sender] += _amount;

    emit Deposit(msg.sender, _amount);
  }

  /**
    * @notice It allows users to harvest from pool
    * @notice if user is not whitelisted and the whitelist is active, the user is refunded in lpTokens
  */
  function harvest() external {
    // buffer time between end of deposit and start of harvest for admin to whitelist (~7 hours)
    require(block.number > harvestBlock, "Too early to harvest");

    // Checks whether the user has participated
    require(amount[msg.sender] > 0, "already harvested");

    // Initialize the variables for offering and refunding user amounts
    uint256 offeringTokenAmount = _calculateOfferingAmount(msg.sender);

    amount[msg.sender] = 0;

    require(offeringToken.transfer(address(msg.sender), offeringTokenAmount));

    emit Harvest(msg.sender, offeringTokenAmount);
  }


  /**
    * @notice It allows the admin to withdraw funds
    * @notice the offering token can only be withdrawn 10000 blocks after harvesting
    * @param _lpAmount: the number of LP token to withdraw (18 decimals)
    * @param _offerAmount: the number of offering amount to withdraw
    * @param _weiAmount: the amount of Wei to withdraw
    * @dev This function is only callable by admin.
  */
  function finalWithdraw(uint256 _lpAmount, uint256 _offerAmount, uint256 _weiAmount) external  onlyOwner {

    if (_lpAmount > 0) {
      lpToken.transfer(address(msg.sender), _lpAmount);
    }

    if (_offerAmount > 0) {
      require(block.number > harvestBlock + 10000, "too early to withdraw offering token");
      offeringToken.transfer(address(msg.sender), _offerAmount);
    }

    if (_weiAmount > 0) {
      payable(address(msg.sender)).transfer(_weiAmount);
    }

    emit AdminWithdraw(_lpAmount, _offerAmount, _weiAmount);
  }

  /**
    * @notice It allows the admin to recover wrong tokens sent to the contract
    * @param _tokenAddress: the address of the token to withdraw (18 decimals)
    * @param _tokenAmount: the number of token amount to withdraw
    * @dev This function is only callable by admin.
  */
  function recoverWrongTokens(address _tokenAddress, uint256 _tokenAmount) external onlyOwner {
    require(_tokenAddress != address(lpToken), "Cannot be LP token");
    require(_tokenAddress != address(offeringToken), "Cannot be offering token");

    IERC20(_tokenAddress).transfer(address(msg.sender), _tokenAmount);

    emit AdminTokenRecovery(_tokenAddress, _tokenAmount);
  }

  /**
    * @notice timeLock
    * @notice It sets parameters for pool
    * @param _offeringAmount offering amount with all decimals
    * @dev This function is only callable by admin
  */
  function setPool(
    uint256 _offeringAmount,
    uint256 __price
   ) public onlyOwner timeLock
   {
    offeringAmount = _offeringAmount;
    _price = __price;
    emit PoolParametersSet(_offeringAmount, _price);
  }

  /**
    * @notice It allows the admin to update start and end blocks
    * @notice automatically resets the totalAmount in the Pool to 0, but not userAmounts
    * @notice timeLock
    * @param _startBlock: the new start block
    * @param _endBlock: the new end block
  */
  function updateStartAndEndBlocks(uint256 _startBlock, uint256 _endBlock, uint256 _harvestBlock) public onlyOwner timeLock {
    require(_startBlock < _endBlock, "New startBlock must be lower than new endBlock");
    require(block.number < _startBlock, "New startBlock must be higher than current block");
    totalAmount = 0;
    startBlock = _startBlock;
    endBlock = _endBlock;
    harvestBlock = _harvestBlock;

    emit NewStartAndEndBlocks(_startBlock, _endBlock);
  }

  /**
    * @notice It returns the pool information
    * @return offeringAmountPool: amount of tokens offered for the pool (in offeringTokens)
    * @return _price the price in OfferingToken/LPToken, 10**12 means 1:1 because of different decimal places
    * @return totalAmountPool: total amount pool deposited (in LP tokens)
  */
  function viewPoolInformation()
    external
    view
    returns(
      uint256,
      uint256,
      uint256
    )
    {
    return (
      offeringAmount,
      _price,
      totalAmount
    );
  }

  /**
    * @notice External view function to see user amount in pool
    * @param _user: user address
  */
  function viewUserAmount(address _user)
    external
    view
    returns(uint256)
  {
    return (amount[_user]);
  }

  /**
    * @notice External view function to see user offering amounts
    * @param _user: user address
  */
  function viewUserOfferingAmount(address _user)
    external
    view
    returns(uint256)
  {
    return _calculateOfferingAmount(_user);
  }

  /**
    * @notice It calculates the offering amount for a user and the number of LP tokens to transfer back.
    * @param _user: user address
    * @return the amount of OfferingTokens _user receives as of now
  */
  function _calculateOfferingAmount(address _user)
    internal
    view
    returns(uint256)
  {
    return amount[_user] * _price;
  }

  function setToken(address _lpToken, address _offering) public onlyOwner timeLock {
    lpToken = IERC20(_lpToken);
    offeringToken = IERC20(_offering);
  }

  /**
    * @return returns the price from the AggregatorV3 contract specified in initialization 
  */
  function getLatestEthPrice() public view returns(int) {
    (
      uint80 roundID,
      int price,
      uint startedAt,
      uint timeStamp,
      uint80 answeredInRound
    ) = priceFeed.latestRoundData();
    return price;
  }
}
