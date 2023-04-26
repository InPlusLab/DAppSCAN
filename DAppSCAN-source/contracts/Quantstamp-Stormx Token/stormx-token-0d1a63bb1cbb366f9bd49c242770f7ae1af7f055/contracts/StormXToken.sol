pragma solidity 0.5.16;

import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Mintable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./StormXGSNRecipient.sol";


contract StormXToken is 
  StormXGSNRecipient,         
  ERC20Mintable, 
  ERC20Detailed("StormX", "STMX", 18) {    

  using SafeMath for uint256;

  bool public transfersEnabled;
  bool public initialized = false;
  address public validMinter;

  mapping(address => bool) public recipients;

  // Variables for staking feature
  mapping(address => uint256) public lockedBalanceOf;

  event TokenLocked(address indexed account, uint256 amount);
  event TokenUnlocked(address indexed account, uint256 amount);
  event TransfersEnabled(bool newStatus);
  event ValidMinterAdded(address minter);

  // Testing that GSN is supported properly 
  event GSNRecipientAdded(address recipient);
  event GSNRecipientDeleted(address recipient);

  modifier transfersAllowed {
    require(transfersEnabled, "Transfers not available");
    _;
  }
  
  /**
   * @param reserve address of the StormX's reserve that receives
   * GSN charged fees and remaining tokens
   * after the token migration is closed
   */
  constructor(address reserve) 
    // solhint-disable-next-line visibility-modifier-order
    StormXGSNRecipient(address(this), reserve) public { 
      recipients[address(this)] = true;
      emit GSNRecipientAdded(address(this));
      transfersEnabled = true;
    }

  /**
   * @dev Adds GSN recipient that will charge users in this StormX token
   * @param recipient address of the new recipient
   * @return success status of the adding
   */
  function addGSNRecipient(address recipient) public onlyOwner returns (bool) {
    recipients[recipient] = true;
    emit GSNRecipientAdded(recipient);
    return true;
  }

  /**
   * @dev Deletes a GSN recipient from the list
   * @param recipient address of the recipient to be deleted
   * @return success status of the deleting
   */
  function deleteGSNRecipient(address recipient) public onlyOwner returns (bool) {
    recipients[recipient] = false;
    emit GSNRecipientDeleted(recipient);
    return true;
  }

  /**
   * @param account address of the user this function queries unlocked balance for
   * @return the amount of unlocked tokens of the given address
   *         i.e. the amount of manipulable tokens of the given address
   */
  function unlockedBalanceOf(address account) public view returns (uint256) {
    return balanceOf(account).sub(lockedBalanceOf[account]);
  }

  /**
   * @dev Locks specified amount of tokens for the user
   *      Locked tokens are not manipulable until being unlocked
   *      Locked tokens are still reported as owned by the user 
   *      when ``balanceOf()`` is called
   * @param amount specified amount of tokens to be locked
   * @return success status of the locking 
   */
  function lock(uint256 amount) public returns (bool) {
    address account = _msgSender();
    require(unlockedBalanceOf(account) >= amount, "Not enough unlocked tokens");
    lockedBalanceOf[account] = lockedBalanceOf[account].add(amount);
    emit TokenLocked(account, amount);
    return true;
  }

  /**
   * @dev Unlocks specified amount of tokens for the user
   *      Unlocked tokens are manipulable until being locked
   * @param amount specified amount of tokens to be unlocked
   * @return success status of the unlocking 
   */
  function unlock(uint256 amount) public returns (bool) {
    address account = _msgSender();
    require(lockedBalanceOf[account] >= amount, "Not enough locked tokens");
    lockedBalanceOf[account] = lockedBalanceOf[account].sub(amount);
    emit TokenUnlocked(account, amount);
    return true;
  }
  
  /**
   * @dev The only difference from standard ERC20 ``transferFrom()`` is that
   *     it only succeeds if the sender has enough unlocked tokens
   *     Note: this function is also used by every StormXGSNRecipient
   *           when charging.
   * @param sender address of the sender
   * @param recipient address of the recipient
   * @param amount specified amount of tokens to be transferred
   * @return success status of the transferring
   */
  function transferFrom(address sender, address recipient, uint256 amount) public returns (bool) {
    require(unlockedBalanceOf(sender) >= amount, "Not enough unlocked token balance of sender");
    // if the msg.sender is charging ``sender`` for a GSN fee
    // allowance does not apply
    // so that no user approval is required for GSN calls
    if (recipients[_msgSender()] == true) {
      _transfer(sender, recipient, amount);
      return true;
    } else {
      return super.transferFrom(sender, recipient, amount);
    }
  }

  /**
   * @dev The only difference from standard ERC20 ``transfer()`` is that
   *     it only succeeds if the user has enough unlocked tokens
   * @param recipient address of the recipient
   * @param amount specified amount of tokens to be transferred
   * @return success status of the transferring
   */
  function transfer(address recipient, uint256 amount) public returns (bool) {
    require(unlockedBalanceOf(_msgSender()) >= amount, "Not enough unlocked token balance");
    return super.transfer(recipient, amount);
  }

  /**
   * @dev Transfers tokens in batch
   * @param recipients an array of address of the recipient
   * @param values an array of specified amount of tokens to be transferred
   * @return success status of the batch transferring
   */
  function transfers(
    address[] memory recipients, 
    uint256[] memory values
  ) public transfersAllowed returns (bool) {
    require(recipients.length == values.length, "Input lengths do not match");
    
    for (uint256 i = 0; i < recipients.length; i++) {
      transfer(recipients[i], values[i]);
    }
    return true;
  }

  /**
   * @dev Enables the method ``transfers()`` if ``enable=true``, 
   * and disables ``transfers()`` otherwise
   * @param enable the expected new availability of the method ``transfers()``
   */
  function enableTransfers(bool enable) public onlyOwner returns (bool) {
    transfersEnabled = enable;
    emit TransfersEnabled(enable);
    return true;
  }

  function mint(address account, uint256 amount) public onlyMinter returns (bool) {
    require(initialized, "The contract is not initialized yet");
    require(_msgSender() == validMinter, "not authorized to mint");
    super.mint(account, amount);
    return true;
  }

  /**
   * @dev Initializes this contract
   *      Sets address ``swap`` as the only valid minter for this token
   *      Note: must be called before token migration opens in ``Swap.sol``
   * @param swap address of the deployed contract ``Swap.sol``
   */
  function initialize(address swap) public onlyOwner {
    require(!initialized, "cannot initialize twice");
    require(swap != address(0), "invalid swap address");
    addMinter(swap);
    validMinter = swap;
    initialized = true;
    emit ValidMinterAdded(swap);
  }
}
