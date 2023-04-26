pragma solidity ^0.4.18;

import "./OMIToken.sol";
import "../node_modules/zeppelin-solidity/contracts/ownership/Ownable.sol";
import "../node_modules/zeppelin-solidity/contracts/math/SafeMath.sol";
import "../node_modules/zeppelin-solidity/contracts/lifecycle/Pausable.sol";

/// @title OMITokenLock
/// @author Mikel Duffy - <mikel@ecomi.com>
/// @dev OMITokenLock is a token holder contract that will allow multiple beneficiaries to extract the tokens after a given release time. It is a modification of the OpenZeppenlin TokenLock to allow for one token lock smart contract for many beneficiaries.
contract OMITokenLock is Ownable, Pausable {
  using SafeMath for uint256;

  /*
   *  Storage
   */
  OMIToken public token;
  address public allowanceProvider;
  address public crowdsale;
  bool public crowdsaleFinished = false;
  uint256 public crowdsaleEndTime;

  struct Lock {
    uint256 amount;
    uint256 lockDuration;
    bool released;
    bool revoked;
  }
  struct TokenLockVault {
    address beneficiary;
    uint256 tokenBalance;
    uint256 lockIndex;
    Lock[] locks;
  }
  mapping(address => TokenLockVault) public tokenLocks;
  address[] public lockIndexes;
  uint256 public totalTokensLocked;

  /*
   *  Modifiers
   */
  modifier ownerOrCrowdsale () {
    require(msg.sender == owner || msg.sender == crowdsale);
    _;
  }

  /*
   *  Events
   */
  event LockedTokens(address indexed beneficiary, uint256 amount, uint256 releaseTime);
  event UnlockedTokens(address indexed beneficiary, uint256 amount);
  event FinishedCrowdsale();

  /*
   *  Public Functions
   */
  /// @dev Constructor function
  function OMITokenLock (OMIToken _token) public {
    token = _token;
  }

  /// @dev Sets the crowdsale address to allow authorize locking permissions
  /// @param _crowdsale The address of the crowdsale
  function setCrowdsaleAddress (address _crowdsale)
    public
    onlyOwner
    returns (bool)
  {
    crowdsale = _crowdsale;
    return true;
  }

  /// @dev Sets the token allowance provider address
  /// @param _allowanceProvider The address of the token allowance provider
  function setAllowanceAddress (address _allowanceProvider)
    public
    onlyOwner
    returns (bool)
  {
    allowanceProvider = _allowanceProvider;
    return true;
  }

  /// @dev Marks the crowdsale as being finished and sets the crowdsale finish date
  function finishCrowdsale()
    public
    ownerOrCrowdsale
    whenNotPaused
  {
    require(!crowdsaleFinished);
    crowdsaleFinished = true;
    crowdsaleEndTime = now;
    FinishedCrowdsale();
  }

  /// @dev Gets the total amount of tokens for a given address
  /// @param _beneficiary The address for which to look up the total token amount
  function getTokenBalance(address _beneficiary)
    public
    view
    returns (uint)
  {
    return tokenLocks[_beneficiary].tokenBalance;
  }

  /// @dev Gets the total number of locks for a given address
  /// @param _beneficiary The address for which to look up the total number of locks
  function getNumberOfLocks(address _beneficiary)
    public
    view
    returns (uint)
  {
    return tokenLocks[_beneficiary].locks.length;
  }

  /// @dev Gets the lock at a given index for a given address
  /// @param _beneficiary The address used to look up the lock
  /// @param _lockIndex The index used to look up the lock
  function getLockByIndex(address _beneficiary, uint256 _lockIndex)
    public
    view
    returns (uint256 amount, uint256 lockDuration, bool released, bool revoked)
  {
    require(_lockIndex >= 0);
    require(_lockIndex <= tokenLocks[_beneficiary].locks.length.sub(1));

    return (
      tokenLocks[_beneficiary].locks[_lockIndex].amount,
      tokenLocks[_beneficiary].locks[_lockIndex].lockDuration,
      tokenLocks[_beneficiary].locks[_lockIndex].released,
      tokenLocks[_beneficiary].locks[_lockIndex].revoked
    );
  }

  /// @dev Revokes the lock at a given index for a given address
  /// @param _beneficiary The address used to look up the lock
  /// @param _lockIndex The lock index to be revoked
  function revokeLockByIndex(address _beneficiary, uint256 _lockIndex)
    public
    onlyOwner
    returns (bool)
  {
    require(_lockIndex >= 0);
    require(_lockIndex <= tokenLocks[_beneficiary].locks.length.sub(1));
    require(!tokenLocks[_beneficiary].locks[_lockIndex].revoked);

    tokenLocks[_beneficiary].locks[_lockIndex].revoked = true;

    return true;
  }

  /// @dev Locks tokens for a given beneficiary
  /// @param _beneficiary The address to which the tokens will be released
  /// @param _lockDuration The duration of time that must elapse after the crowdsale end date
  /// @param _tokens The amount of tokens to be locked
  function lockTokens(address _beneficiary, uint256 _lockDuration, uint256 _tokens)
    external
    ownerOrCrowdsale
    whenNotPaused
  {
    // Lock duration must be greater than zero seconds
    require(_lockDuration >= 0);
    // Token amount must be greater than zero
    require(_tokens > 0);

    // Token Lock must have a sufficient allowance prior to creating locks
    uint256 tokenAllowance = token.allowance(allowanceProvider, address(this));
    require(_tokens.add(totalTokensLocked) <= tokenAllowance);

    TokenLockVault storage lock = tokenLocks[_beneficiary];

    // If this is the first lock for this beneficiary, add their address to the lock indexes
    if (lock.beneficiary == 0) {
      lock.beneficiary = _beneficiary;
      lock.lockIndex = lockIndexes.length;
      lockIndexes.push(_beneficiary);
    }

    // Add the lock
    lock.locks.push(Lock(_tokens, _lockDuration, false, false));

    // Update the total tokens for this beneficiary
    lock.tokenBalance = lock.tokenBalance.add(_tokens);

    // Update the number of locked tokens
    totalTokensLocked = _tokens.add(totalTokensLocked);

    LockedTokens(_beneficiary, _tokens, _lockDuration);
  }

  /// @dev Transfers any tokens held in a timelock vault to beneficiary if they are due for release.
  function releaseTokens()
    public
    whenNotPaused
    returns(bool)
  {
    require(crowdsaleFinished);
    require(_release(msg.sender));
    return true;
  }

  /// @dev Transfers tokens held by timelock to all beneficiaries within the provided range.
  /// @param _from the start lock index
  /// @param _to the end lock index
  function releaseAll(uint256 _from, uint256 _to)
    external
    whenNotPaused
    onlyOwner
    returns (bool)
  {
    require(_from >= 0);
    require(_from < _to);
    require(_to <= lockIndexes.length);
    require(crowdsaleFinished);

    for (uint256 i = _from; i < _to; i = i.add(1)) {
      address _beneficiary = lockIndexes[i];

      //Skip any previously removed locks
      if (_beneficiary == 0x0) {
        continue;
      }

      require(_release(_beneficiary));
    }
    return true;
  }

  /*
   *  Internal Functions
   */
  /// @dev Reviews and releases token for a given beneficiary
  /// @param _beneficiary address for which a token release should be attempted
  function _release(address _beneficiary)
    internal
    whenNotPaused
    returns (bool)
  {
    TokenLockVault memory lock = tokenLocks[_beneficiary];
    require(lock.beneficiary == _beneficiary);

    bool hasUnDueLocks = false;
    bool hasReleasedToken = false;

    for (uint256 i = 0; i < lock.locks.length; i = i.add(1)) {
      Lock memory currentLock = lock.locks[i];
      // Skip any locks which are already released or revoked
      if (currentLock.released || currentLock.revoked) {
        continue;
      }

      // Skip any locks that are not due for release
      if (crowdsaleEndTime.add(currentLock.lockDuration) >= now) {
        hasUnDueLocks = true;
        continue;
      }

      // The amount of tokens to transfer must be less than the number of locked tokens
      require(currentLock.amount <= token.allowance(allowanceProvider, address(this)));

      // Release Tokens
      UnlockedTokens(msg.sender, currentLock.amount);
      hasReleasedToken = true;
      tokenLocks[_beneficiary].locks[i].released = true;
      tokenLocks[_beneficiary].tokenBalance = tokenLocks[_beneficiary].tokenBalance.sub(currentLock.amount);
      totalTokensLocked = totalTokensLocked.sub(currentLock.amount);
      assert(token.transferFrom(allowanceProvider, msg.sender, currentLock.amount));
    }

    // If there are no future locks to be released, delete the lock vault
    if (!hasUnDueLocks) {
      delete tokenLocks[msg.sender];
      lockIndexes[lock.lockIndex] = 0x0;
    }

    return hasReleasedToken;
  }
}
