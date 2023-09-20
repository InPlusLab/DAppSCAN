// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;
//SWC-102-Outdated Compiler Version: L2
import '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import '@openzeppelin/contracts/utils/Counters.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import './interfaces/IWETH.sol';


/**
 * @title An NFT representation of ownership of time locked tokens
 * @notice The time locked tokens are redeemable by the owner of the NFT
 * @notice The NFT is basic ERC721 with an ownable usage to ensure only a single owner call mint new NFTs
 * @notice it uses the Enumerable extension to allow for easy lookup to pull balances of one account for multiple NFTs
 */
contract Hedgeys is ERC721Enumerable, ReentrancyGuard {
  using SafeERC20 for IERC20;
  using Counters for Counters.Counter;
  Counters.Counter private _tokenIds;

  address payable public weth;
  string private baseURI;
  uint8 private uriSet = 0;

  /// @dev the Future is the storage in a struct of the tokens that are time locked
  /// @dev the Future contains the information about the amount of tokens, the underlying token address (asset), and the date in which they are unlocked
  struct Future {
    uint256 amount;
    address token;
    uint256 unlockDate;
  }

  /// @dev this maping maps the same uint from Counters that is used to mint an NFT to the Future struct
  mapping(uint256 => Future) public futures;

  constructor(address payable _weth, string memory uri) ERC721('Hedgeys', 'HDGY') {
    weth = _weth;
    baseURI = uri;
  }

  receive() external payable {}

  /**
   * @notice The external function creates a Future position
   * @notice This funciton does not accept ETH, must send in wrapped ETH to lock ETH
   * @notice A Future position is the combination of an NFT and a Future struct with the same index uint storing both information separately but with the same index
   * @notice Anyone can mint an NFT & create a futures Struct, so long as they have sufficient tokens to lock up
   * @notice A user can mint the NFT to themselves, passing in their address to the first parameter, or they can directly assign and mint it to another wallet
   * @param _holder is the owner of the minted NFT and the owner of the locked tokens
   * @param _amount is the amount with full decimals of the tokens being locked into the future
   * @param _token is the address of the tokens that are being delivered to this contract to be held and locked
   * @param _unlockDate is the date in UTC in which the tokens can become redeemed - evaluated based on the block.timestamp
   */
  function createNFT(
    address _holder,
    uint256 _amount,
    address _token,
    uint256 _unlockDate
  ) external returns (uint256) {
    _tokenIds.increment();
    uint256 newItemId = _tokenIds.current();
    /// @dev record the NFT miting with the newItemID coming from Counters library
    _safeMint(_holder, newItemId);
    /// @dev require that the amount is not 0, address is not the 0 address, and that the expiration date is actually beyond today
    require(_amount > 0 && _token != address(0) && _unlockDate > block.timestamp, 'HEC01: NFT Minting Error');
    /// @dev check our initial balance of this asset
    uint256 currentBalance = IERC20(_token).balanceOf(address(this));
    /// @dev pull the funds from the message sender
    require(IERC20(_token).balanceOf(address(msg.sender)) >= _amount, 'HNEC02: Insufficient Balance');
    SafeERC20.safeTransferFrom(IERC20(_token), msg.sender, address(this), _amount);
    uint256 postBalance = IERC20(_token).balanceOf(address(this));
    require(postBalance - currentBalance == _amount, 'HNEC03: Wrong amount');
    /// @dev using the same newItemID we generate a Future struct recording the token address (asset), the amount of tokens (amount), and time it can be unlocked (_expiry)
    futures[newItemId] = Future(_amount, _token, _unlockDate);
    emit NFTCreated(newItemId, _holder, _amount, _token, _unlockDate);
    return newItemId;
  }

  /// @dev internal function used by the standard ER721 function tokenURI to retrieve the baseURI privately held to visualize and get the metadata
  function _baseURI() internal view override returns (string memory) {
    return baseURI;
  }

  /// @dev onlyOwner function to set the base URI after the contract has been launched
  /// @dev there is no actual on-chain functions that require this URI to be anything beyond a blank string ("")
  /// @dev there are no vulnerabilities should this be changed as it is for astetic purposes only
  function updateBaseURI(string memory _uri) external {
    require(uriSet == 0, 'HNEC06: uri already set');
    baseURI = _uri;
    uriSet = 1;
  }

  /// @notice this is the external function that actually redeems an NFT position
  /// @dev this function calls the _redeemFuture(...) internal function which handles the requirements and checks
  function redeemNFT(uint256 _id) external nonReentrant returns (bool) {
    _redeemNFT(payable(msg.sender), _id);
    return true;
  }

  /**
   * @notice This internal function, called by redeemNFT to physically burn the NFT and distribute the locked tokens to its owner
   * @dev this function does five things: 1) Checks to ensure only the owner of the NFT can call this function
   * @dev 2) it checks that the tokens can actually be unlocked based on the time from the expiration
   * @dev 3) it burns the NFT - removing it from storage entirely
   * @dev 4) it also deletes the futures struct from storage so that nothing can be redeemed from that storage index again
   * @dev 5) it withdraws the tokens that have been locked - delivering them to the current owner of the NFT
   */
  function _redeemNFT(address payable _holder, uint256 _id) internal {
    require(ownerOf(_id) == _holder, 'HNEC04: Only the NFT Owner');
    Future storage future = futures[_id];
    require(future.unlockDate < block.timestamp && future.amount > 0, 'HNEC05: Tokens are still locked');
    //delivers the vested tokens to the vester
    emit NFTRedeemed(_id, _holder, future.amount, future.token, future.unlockDate);
    _burn(_id);
    _withdraw(future.token, _holder, future.amount);
    delete futures[_id];
  }

  /// @dev internal function used to withdraw locked tokens and send them to an address
  /// @dev this contract stores WETH instead of ETH to represent ETH
  /// @dev which means that if we are delivering ETH back out, we will convert the WETH first and then transfer the ETH to the recipiient
  /// @dev if the tokens are not WETH, then we simply safely transfer them back out to the address
  function _withdraw(
    address _token,
    address payable to,
    uint256 _amt
  ) internal {
    if (_token == weth) {
      IWETH(weth).withdraw(_amt);
      to.transfer(_amt);
    } else {
      SafeERC20.safeTransfer(IERC20(_token), to, _amt);
    }
  }

  ///@notice Events when a new NFT (future) is created and one with a Future is redeemed (burned)
  event NFTCreated(uint256 _i, address _holder, uint256 _amount, address _token, uint256 _unlockDate);
  event NFTRedeemed(uint256 _i, address _holder, uint256 _amount, address _token, uint256 _unlockDate);
}
