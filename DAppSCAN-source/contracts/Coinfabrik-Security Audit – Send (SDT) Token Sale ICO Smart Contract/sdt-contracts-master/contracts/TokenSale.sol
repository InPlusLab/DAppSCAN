pragma solidity ^0.4.18;

import "./TokenVesting.sol";
import "zeppelin-solidity/contracts/token/BurnableToken.sol";
import "zeppelin-solidity/contracts/ownership/Ownable.sol";
import "zeppelin-solidity/contracts/math/SafeMath.sol";


/**
 * @title Crowdsale contract
 * @dev see https://send.sd/crowdsale
 */
contract TokenSale is Ownable {
  using SafeMath for uint256;

  /* Leave 10 tokens margin error in order to succedd
  with last pool allocation in case hard cap is reached */
  uint256 constant public HARD_CAP = 70000000 ether;
  uint256 constant public VESTING_TIME = 90 days;
  uint256 public weiUsdRate = 1;
  uint256 public btcUsdRate = 1;

  uint256 public vestingEnds;
  uint256 public startTime;
  uint256 public endTime;
  address public wallet;

  uint256 public vestingStarts;

  uint256 public soldTokens;
  uint256 public raised;

  bool public activated = false;
  bool public isStopped = false;
  bool public isFinalized = false;

  BurnableToken public token;
  TokenVesting public vesting;

  event NewBuyer(
    address indexed holder,
    uint256 sndAmount,
    uint256 usdAmount,
    uint256 ethAmount,
    uint256 btcAmount
  );

  event ClaimedTokens(
    address indexed _token,
    address indexed _controller,
    uint256 _amount
  );

  modifier validAddress(address _address) {
    require(_address != address(0x0));
    _;
  }

  modifier isActive() {
    require(activated);
    require(!isStopped);
    require(!isFinalized);
    require(block.timestamp >= startTime);
    require(block.timestamp <= endTime);
    _;
  }

  function TokenSale(
      uint256 _startTime,
      uint256 _endTime,
      address _wallet,
      uint256 _vestingStarts
  ) public validAddress(_wallet) {
    require(_startTime > block.timestamp - 60);
    require(_endTime > startTime);
    require(_vestingStarts > startTime);

    vestingStarts = _vestingStarts;
    vestingEnds = vestingStarts.add(VESTING_TIME);
    startTime = _startTime;
    endTime = _endTime;
    wallet = _wallet;
  }

  /**
   * @dev set an exchange rate in wei
   * @param _rate uint256 The new exchange rate
   */
  function setWeiUsdRate(uint256 _rate) public onlyOwner {
    require(_rate > 0);
    weiUsdRate = _rate;
  }

  /**
   * @dev set an exchange rate in satoshis
   * @param _rate uint256 The new exchange rate
   */
  function setBtcUsdRate(uint256 _rate) public onlyOwner {
    require(_rate > 0);
    btcUsdRate = _rate;
  }

  /**
   * @dev initialize the contract and set token
   */
  function initialize(
      address _sdt,
      address _vestingContract,
      address _icoCostsPool,
      address _distributionContract
  ) public validAddress(_sdt) validAddress(_vestingContract) onlyOwner {
    require(!activated);
    activated = true;

    token = BurnableToken(_sdt);
    vesting = TokenVesting(_vestingContract);

    // 1% reserve is released on deploy
    token.transfer(_icoCostsPool, 7000000 ether);
    token.transfer(_distributionContract, 161000000 ether);

    //early backers allocation
    uint256 threeMonths = vestingStarts.add(90 days);

    updateStats(0, 43387693 ether);
    grantVestedTokens(0x02f807E6a1a59F8714180B301Cba84E76d3B4d06, 22572063 ether, vestingStarts, threeMonths);
    grantVestedTokens(0x3A1e89dD9baDe5985E7Eb36E9AFd200dD0E20613, 15280000 ether, vestingStarts, threeMonths);
    grantVestedTokens(0xA61c9A0E96eC7Ceb67586fC8BFDCE009395D9b21, 250000 ether, vestingStarts, threeMonths);
    grantVestedTokens(0x26C9899eA2F8940726BbCC79483F2ce07989314E, 100000 ether, vestingStarts, threeMonths);
    grantVestedTokens(0xC88d5031e00BC316bE181F0e60971e8fEdB9223b, 1360000 ether, vestingStarts, threeMonths);
    grantVestedTokens(0x38f4cAD7997907741FA0D912422Ae59aC6b83dD1, 250000 ether, vestingStarts, threeMonths);
    grantVestedTokens(0x2b2992e51E86980966c42736C458e2232376a044, 105000 ether, vestingStarts, threeMonths);
    grantVestedTokens(0xdD0F60610052bE0976Cf8BEE576Dbb3a1621a309, 140000 ether, vestingStarts, threeMonths);
    grantVestedTokens(0xd61B4F33D3413827baa1425E2FDa485913C9625B, 740000 ether, vestingStarts, threeMonths);
    grantVestedTokens(0xE6D4a77D01C680Ebbc0c84393ca598984b3F45e3, 505630 ether, vestingStarts, threeMonths);
    grantVestedTokens(0x35D3648c29Ac180D5C7Ef386D52de9539c9c487a, 150000 ether, vestingStarts, threeMonths);
    grantVestedTokens(0x344a6130d187f51ef0DAb785e10FaEA0FeE4b5dE, 967500 ether, vestingStarts, threeMonths);
    grantVestedTokens(0x026cC76a245987f3420D0FE30070B568b4b46F68, 967500 ether, vestingStarts, threeMonths);
  }

  function finalize(
      address _poolA,
      address _poolB,
      address _poolC,
      address _poolD
  )
      public
      validAddress(_poolA)
      validAddress(_poolB)
      validAddress(_poolC)
      validAddress(_poolD)
      onlyOwner
  {
    grantVestedTokens(_poolA, 175000000 ether, vestingStarts, vestingStarts.add(7 years));
    grantVestedTokens(_poolB, 168000000 ether, vestingStarts, vestingStarts.add(7 years));
    grantVestedTokens(_poolC, 70000000 ether, vestingStarts, vestingStarts.add(7 years));
    grantVestedTokens(_poolD, 48999990 ether, vestingStarts, vestingStarts.add(4 years));

    token.burn(token.balanceOf(this));
  }

  function stop() public onlyOwner isActive returns(bool) {
    isStopped = true;
    return true;
  }

  function resume() public onlyOwner returns(bool) {
    require(isStopped);
    isStopped = false;
    return true;
  }

  function () public payable {
    uint256 usd = msg.value.div(weiUsdRate);
    doPurchase(usd, msg.value, 0, msg.sender, vestingEnds);
    forwardFunds();
  }

  function btcPurchase(
      address _beneficiary,
      uint256 _btcValue
  ) public onlyOwner validAddress(_beneficiary) {
    uint256 usd = _btcValue.div(btcUsdRate);
    doPurchase(usd, 0, _btcValue, _beneficiary, vestingEnds);
  }

  /**
  * @dev Number of tokens is given by:
  * usd * 100 ether / 14
  */
  function computeTokens(uint256 _usd) public pure returns(uint256) {
    return _usd.mul(100 ether).div(14);
  }

  //////////
  // Safety Methods
  //////////
  /// @notice This method can be used by the controller to extract mistakenly
  ///  sent tokens to this contract.
  /// @param _token The address of the token contract that you want to recover
  ///  set to 0 in case you want to extract ether.
  function claimTokens(address _token) public onlyOwner {
    require(_token != address(token));
    if (_token == 0x0) {
      owner.transfer(this.balance);
      return;
    }

    ERC20Basic erc20token = ERC20Basic(_token);
    uint256 balance = erc20token.balanceOf(this);
    erc20token.transfer(owner, balance);
    ClaimedTokens(_token, owner, balance);
  }

  function forwardFunds() internal {
    wallet.transfer(msg.value);
  }

  /**
   * @notice The owner of this contract is the owner of token's contract
   * @param _usd amount invested in USD
   * @param _eth amount invested in ETH y contribution was made in ETH, 0 otherwise
   * @param _btc amount invested in BTC y contribution was made in BTC, 0 otherwise
   * @param _address Address to send tokens to
   * @param _vestingEnds vesting finish timestamp
   */
  function doPurchase(
      uint256 _usd,
      uint256 _eth,
      uint256 _btc,
      address _address,
      uint256 _vestingEnds
  )
      internal
      isActive
      returns(uint256)
  {
    require(_usd >= 10);

    uint256 soldAmount = computeTokens(_usd);

    updateStats(_usd, soldAmount);
    grantVestedTokens(_address, soldAmount, vestingStarts, _vestingEnds);
    NewBuyer(_address, soldAmount, _usd, _eth, _btc);

    return soldAmount;
  }

  /**
   * @dev Helper function to update collected and allocated tokens stats
   */
  function updateStats(uint256 usd, uint256 tokens) internal {
    raised = raised.add(usd);
    soldTokens = soldTokens.add(tokens);

    require(soldTokens <= HARD_CAP);
  }

  /**
   * @dev grant vested tokens
   * @param _to Adress to grant vested tokens
   * @param _value number of tokens to grant
   * @param _start vesting start timestamp
   * @param _vesting vesting finish timestamp
   */
  function grantVestedTokens(
      address _to,
      uint256 _value,
      uint256 _start,
      uint256 _vesting
  ) internal {
    token.transfer(vesting, _value);
    vesting.grantVestedTokens(_to, _value, _start, _vesting);
  }
}
