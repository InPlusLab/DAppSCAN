// SWC-101-Integer Overflow and Underflow: L2-308
pragma solidity 0.4.23;

import "openzeppelin-solidity/contracts/token/ERC20/PausableToken.sol";
import "./interfaces/IRegistry.sol";
import "./interfaces/IBrickblockToken.sol";


/*
  glossary:
    dividendParadigm: the way of handling dividends, and the per token data structures
      * totalLockedBBK * (totalMintedPerToken - distributedPerBBK) / 1e18
      * this is the typical way of handling dividends.
      * per token data structures are stored * 1e18 (for more accuracy)
      * this works fine until BBK is locked or unlocked.
        * need to still know the amount they HAD locked before a change.
        * securedFundsParadigm solves this (read below)
      * when BBK is locked or unlocked, current funds for the relevant
        account are bumped to a new paradigm for balance tracking.
      * when bumped to new paradigm, dividendParadigm is essentially zeroed out
        by setting distributedPerBBK to totalMintedPerToken
          * (100 * (100 - 100) === 0)
      * all minting activity related balance increments are tracked through this

    securedFundsParadigm: funds that are bumped out of dividends during lock / unlock
      * securedTokenDistributions (mapping)
      * needed in order to track ACT balance after lock/unlockBBK
      * tracks funds that have been bumped from dividendParadigm
      * works as a regular balance (not per token)

    doubleEntryParadigm: taking care of transfer and transferFroms
      * receivedBalances[adr] - spentBalances[adr]
      * needed in order to track correct balance after transfer/transferFrom
      * receivedBalances used to increment any transfers to an account
        * increments balanceOf
        * needed to accurately track balanceOf after transfers and transferFroms
      * spentBalances
        * decrements balanceOf
        * needed to accurately track balanceOf after transfers and transferFroms

    dividendParadigm, securedFundsParadigm, doubleEntryParadigm combined
      * when all combined, should correctly:
        * show balance using balanceOf
          * balances is set to private (cannot guarantee accuracy of this)
          * balances not updated to correct values unless a
            transfer/transferFrom happens
      * dividendParadigm + securedFundsParadigm + doubleEntryParadigm
        * totalLockedBBK * (totalMintedPerToken - distributedPerBBK[adr]) / 1e18
          + securedTokenDistributions[adr]
          + receivedBalances[adr] - spentBalances[adr]
*/
contract AccessToken is PausableToken {
  uint8 public constant version = 1;
  // instance of registry contract to get contract addresses
  IRegistry internal registry;
  string public constant name = "AccessToken";
  string public constant symbol = "ACT";
  uint8 public constant decimals = 18;

  // total amount of minted ACT that a single BBK token is entitled to
  uint256 internal totalMintedPerToken;
  // total amount of BBK that is currently locked into ACT contract
  // used to calculate how much to increment totalMintedPerToken during minting
  uint256 public totalLockedBBK;

  // used to save information on who has how much BBK locked in
  // used in dividendParadigm (see glossary)
  mapping(address => uint256) internal lockedBBK;
  // used to decrement totalMintedPerToken by amounts that have already been moved to securedTokenDistributions
  // used in dividendParadigm (see glossary)
  mapping(address => uint256) internal distributedPerBBK;
  // used to store ACT balances that have been moved off of:
  // dividendParadigm (see glossary) to securedFundsParadigm
  mapping(address => uint256) internal securedTokenDistributions;
  // ERC20 override... keep private and only use balanceOf instead
  mapping(address => uint256) internal balances;
  // mapping tracking incoming balances in order to have correct balanceOf
  // used in doubleEntryParadigm (see glossary)
  mapping(address => uint256) public receivedBalances;
  // mapping tracking outgoing balances in order to have correct balanceOf
  // used in doubleEntryParadigm (see glossary)
  mapping(address => uint256) public spentBalances;


  event MintEvent(uint256 amount);
  event BurnEvent(address indexed burner, uint256 value);
  event BBKLockedEvent(
    address indexed locker, 
    uint256 lockedAmount, 
    uint256 totalLockedAmount
  );
  event BBKUnlockedEvent(
    address indexed locker, 
    uint256 lockedAmount, 
    uint256 totalLockedAmount
  );

  modifier onlyContract(string _contractName)
  {
    require(
      msg.sender == registry.getContractAddress(_contractName)
    );
    _;
  }

  constructor (
    address _registryAddress
  )
    public
  {
    require(_registryAddress != address(0));
    registry = IRegistry(_registryAddress);
  }

  // check an address for amount of currently locked BBK
  // works similar to basic ERC20 balanceOf
  function lockedBbkOf(
    address _address
  )
    external
    view
    returns (uint256)
  {
    return lockedBBK[_address];
  }

  // transfers BBK from an account to this contract
  // uses settlePerTokenToSecured to move funds in dividendParadigm to securedFundsParadigm
  // keeps a record of transfers in lockedBBK (securedFundsParadigm)
  function lockBBK(
    uint256 _amount
  )
    external
    returns (bool)
  {
    IBrickblockToken _bbk = IBrickblockToken(
      registry.getContractAddress("BrickblockToken")
    );

    require(settlePerTokenToSecured(msg.sender));
    lockedBBK[msg.sender] = lockedBBK[msg.sender].add(_amount);
    totalLockedBBK = totalLockedBBK.add(_amount);
    require(_bbk.transferFrom(msg.sender, this, _amount));
    emit BBKLockedEvent(msg.sender, _amount, totalLockedBBK);
    return true;
  }

  // transfers BBK from this contract to an account
  // uses settlePerTokenToSecured to move funds in dividendParadigm to securedFundsParadigm
  // keeps a record of transfers in lockedBBK (securedFundsParadigm)
  function unlockBBK(
    uint256 _amount
  )
    external
    returns (bool)
  {
    IBrickblockToken _bbk = IBrickblockToken(
      registry.getContractAddress("BrickblockToken")
    );
    require(_amount <= lockedBBK[msg.sender]);
    require(settlePerTokenToSecured(msg.sender));
    lockedBBK[msg.sender] = lockedBBK[msg.sender].sub(_amount);
    totalLockedBBK = totalLockedBBK.sub(_amount);
    require(_bbk.transfer(msg.sender, _amount));
    emit BBKUnlockedEvent(msg.sender, _amount, totalLockedBBK);
    return true;
  }

  // distribute tokens to all BBK token holders
  // uses dividendParadigm to distribute ACT to lockedBBK holders
  // adds delta (integer division remainders) to owner securedFundsParadigm balance
  function distribute(
    uint256 _amount
  )
    external
    onlyContract("FeeManager")
    returns (bool)
  {
    totalMintedPerToken = totalMintedPerToken
      .add(
        _amount
          .mul(1e18)
          .div(totalLockedBBK)
      );

    uint256 _delta = (_amount.mul(1e18) % totalLockedBBK).div(1e18);
    securedTokenDistributions[owner] = securedTokenDistributions[owner].add(_delta);
    totalSupply_ = totalSupply_.add(_amount);
    emit MintEvent(_amount);
    return true;
  }

  // bumps dividendParadigm balance to securedFundsParadigm
  // ensures that BBK transfers will not affect ACT balance accrued
  function settlePerTokenToSecured(
    address _address
  )
    private
    returns (bool)
  {

    securedTokenDistributions[_address] = securedTokenDistributions[_address]
      .add(
        lockedBBK[_address]
        .mul(totalMintedPerToken.sub(distributedPerBBK[_address]))
        .div(1e18)
      );
    distributedPerBBK[_address] = totalMintedPerToken;

    return true;
  }

  //
  // start ERC20 overrides
  //

  // combines dividendParadigm, securedFundsParadigm, and doubleEntryParadigm
  // in order to give a correct balance
  function balanceOf(
    address _address
  )
    public
    view
    returns (uint256)
  {

    return totalMintedPerToken == 0
      ? 0
      : lockedBBK[_address]
      .mul(totalMintedPerToken.sub(distributedPerBBK[_address]))
      .div(1e18)
      .add(securedTokenDistributions[_address])
      .add(receivedBalances[_address])
      .sub(spentBalances[_address]);
  }

  // does the same thing as ERC20 transfer but...
  // uses balanceOf rather than balances[adr] (balances is inaccurate see above)
  // sets correct values for doubleEntryParadigm (see glossary)
  function transfer(
    address _to,
    uint256 _value
  )
    public
    whenNotPaused
    returns (bool)
  {
    require(_to != address(0));
    require(_value <= balanceOf(msg.sender));
    spentBalances[msg.sender] = spentBalances[msg.sender].add(_value);
    receivedBalances[_to] = receivedBalances[_to].add(_value);
    emit Transfer(msg.sender, _to, _value);
    return true;
  }

  // does the same thing as ERC20 transferFrom but...
  // uses balanceOf rather than balances[adr] (balances is inaccurate see above)
  // sets correct values for doubleEntryParadigm (see glossary)
  function transferFrom(
    address _from,
    address _to,
    uint256 _value
  )
    public
    whenNotPaused
    returns (bool)
  {
    require(_to != address(0));
    require(_value <= balanceOf(_from));
    require(_value <= allowed[_from][msg.sender]);
    spentBalances[_from] = spentBalances[_from].add(_value);
    receivedBalances[_to] = receivedBalances[_to].add(_value);
    allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_value);
    emit Transfer(_from, _to, _value);
    return true;
  }

  //
  // end ERC20 overrides
  //

  // callable only by FeeManager contract
  // burns tokens through incrementing spentBalances[adr] and decrements totalSupply
  // works with doubleEntryParadigm (see glossary)
  function burn(
    address _address,
    uint256 _value
  )
    external
    onlyContract("FeeManager")
    returns (bool)
  {
    require(_value <= balanceOf(_address));
    spentBalances[_address] = spentBalances[_address].add(_value);
    totalSupply_ = totalSupply_.sub(_value);
    emit BurnEvent(_address, _value);
    return true;
  }

  // prevent anyone from sending funds other than selfdestructs of course :)
  // SWC-135-Code With No Effects: L302-307
  function()
    public
    payable
  {
    revert();
  }
}
