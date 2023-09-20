// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;
//SWC-102-Outdated Compiler Version: L2
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import './interfaces/Decimals.sol';
import './interfaces/INFT.sol';


/**
 * @title HedgeyOTC is an over the counter contract with time locking abilitiy
 * @notice This contract allows for a seller to generate a unique over the counter deal, which can be private or public
 * @notice The public deals allow anyone to participate and purchase tokens from the seller, whereas a private deal allows only a single whitelisted address to participate
 * @notice The Seller chooses whether or not the tokens being sold will be locked, as well as the price for the offer
 */
contract CeloHedgeyOTC is ReentrancyGuard {
  using SafeERC20 for IERC20;

  /// @dev d is a strict uint for indexing the OTC deals one at a time
  uint256 public d = 0;
  /// @dev we use this address to store a single futures contract, which is our NFT ERC721 contract address, which we point to for the minting process
  address public futureContract;

  constructor(address _fc) {
    futureContract = _fc;
  }

  /**
   * @notice Deal is the struct that defines a single OTC offer, created by a seller
   * @param  Deal struct contains the following parameter definitions:
   * @param 1) seller: This is the creator and seller of the deal
   * @param 2) token: This is the token that the seller deposits into the contract and which they are selling over the counter. The address defines this ERC20
   * @param ... the token ERC20 contract is required to have a public call function decimals() that returns a uint. This is required to price the amount of tokens being purchase
   * @param ... by the buyer - calculating exactly how much to deliver to the seller.
   * @param 3) paymentCurrency: This is also an ERC20 which the seller will get paid in, during the act of a buyer buying tokens, and paying the seller in the paymentCurrency
   * @param 4) remainingAmount: This initially is the entire deposit the seller is selling, but as people purchase chunks of the deal, the remaining amount is decreased to 0
   * @param 5) minimumPurchase: This is the minimum chunk size that a buyer can purchase, defined by the seller. this prevents security issues of
   * @param ... buyers purchasing 1wei worth of the token which can cause a 0 payment amount, resulting in a conflict.
   * @param 6) price: The Price is the per token cost which buyers pay to the seller, denominated in the payment currency. This is not the total price of the deal
   * @param ... the total price is calculated by the remainingAmount * price (then adjusting for the decimals of the payment currency)
   * @param 7) maturity: this is the unix block time for up until this deal is valid. After the maturity no purchases can be made.
   * @param 8) unlockDate: this is the unix block time which may be used to time lock tokens that are sold. If the unlock date is 0 or less than current block time
   * @param ... at the time of purchase, the tokens are not locked but rather delivered directly to the buyer from the contract
   * @param 9) open: boolean for security purposes to check if this deal is still open and can be purchsed. When the remainingAmount == 0 or it has been cancelled by the seller open == false and no purcahses can be made
   * @param 10) buyer: this is a whitelist address for the buyer. It can either be the Zero address - which indicates that Anyone can purchase
   * @param ... or it is a single address that only that owner of the address can participate in purchasing the tokens
   */
  struct Deal {
    address seller;
    address token;
    address paymentCurrency;
    uint256 remainingAmount;
    uint256 minimumPurchase;
    uint256 price;
    uint256 maturity;
    uint256 unlockDate;
    bool open;
    address buyer;
  }

  /// @dev the Deals are all mapped via the indexer d to deals mapping
  mapping(uint256 => Deal) public deals;

  

  /**
   * @notice This function is what the seller uses to create a new OTC offering
   * @dev this function will pull in tokens from the seller, create a new struct as Deal indexed by the current uint d
   * @dev this function does not allow for taxed / deflationary tokens - as the amount that is pulled into the contract must match with what is being sent
   * @dev this function requires that the _token has a decimals() public function on its ERC20 contract to be called
   * @param _token address is the token that the seller is going to create the over the counter offering for
   * @param _paymentCurrency is the address of the opposite ERC20 that the seller wants to get paid in when selling the token (use WETH for ETH)
   * @param _amount is the amount of tokens that you as the seller want to sell
   * @param _min is the minimum amount of tokens that a buyer can purchase from you. this should be less than or equal to the total amount
   * @param _price is the price per token which you would like to get paid, denominated in the payment currency
   * @param _maturity is how long you would like to allow buyers to purchase tokens from this deal, in unix block time. this needs to be beyond current time
   * @param _unlockDate is used if you are requiring that tokens purchased by buyers are locked. If this is set to 0 or anything less than current time
   * ... any tokens purchased will not be locked but immediately delivered to the buyers. Otherwise the unlockDate will lock the tokens in the associated
   * ... futures NFT contract - which will hold the tokens in escrow until the unlockDate has passed - whereupon the owner of the NFT can redeem the tokens
   * @param _buyer is a special option to make this a private deal - where only the buyer's address can participate and make the purchase. If this is set to the
   * ... Zero address - then it is publicly available and anyone can purchase tokens from this deal
   */
  function create(
    address _token,
    address _paymentCurrency,
    uint256 _amount,
    uint256 _min,
    uint256 _price,
    uint256 _maturity,
    uint256 _unlockDate,
    address _buyer
  ) external {
    require(_maturity > block.timestamp, 'HEC01: Maturity before block timestamp');
    require(_amount >= _min, 'HEC02: Amount less than minium');
    /// @dev this checks to make sure that if someone purchases the minimum amount, it is never equal to 0
    /// @dev where someone could find a small enough minimum to purchase all of the tokens for free.
    require((_min * _price) / (10**Decimals(_token).decimals()) > 0, 'HEC03: Minimum smaller than 0');
    /// @dev we check the before balance of this address for security - this includes checking the WETH balance
    uint256 currentBalance = IERC20(_token).balanceOf(address(this));
    /// @dev this function physically pulls the tokens into the contract for escrow
    require(IERC20(_token).balanceOf(msg.sender) >= _amount, 'HECB: Insufficient Balance');
    SafeERC20.safeTransferFrom(IERC20(_token), msg.sender, address(this), _amount);
    /// @dev check the current balance now that the tokens should be in the contract address, including WETH balance to ensure the deposit function worked
    /// @dev we need to ensure that the balance matches the amount input into the parameters - since that amount is recorded on the Deal struct
    uint256 postBalance = IERC20(_token).balanceOf(address(this));
    assert(postBalance - currentBalance == _amount);
    /// @dev creates the Deal struct with all of the parameters for inputs - and set the bool 'open' to true so that this offer can now be purchased
    deals[d++] = Deal(
      msg.sender,
      _token,
      _paymentCurrency,
      _amount,
      _min,
      _price,
      _maturity,
      _unlockDate,
      true,
      _buyer
    );
    emit NewDeal(
      d - 1,
      msg.sender,
      _token,
      _paymentCurrency,
      _amount,
      _min,
      _price,
      _maturity,
      _unlockDate,
      true,
      _buyer
    );
  }

  /**
   * @notice This function lets a seller cancel their existing deal anytime they would like to
   * @notice there is no requirement that the deal have expired
   * @notice all that is required is that the deal is still open, and that there is still a reamining balance
   * @dev you need to know the index _d of the deal you are trying to close and that is it
   * @dev only the seller can close this deal
   */
  function close(uint256 _d) external nonReentrant {
    Deal storage deal = deals[_d];
    require(msg.sender == deal.seller, 'HEC04: Only Seller Can Close');
    require(deal.remainingAmount > 0, 'HEC05: All tokens have been sold');
    require(deal.open, 'HEC06: Deal has been closed');
    /// @dev once we have confirmed it is the seller and there are remaining tokens - physically pull the remaining balances and deliver to the seller
    SafeERC20.safeTransfer(IERC20(deal.token), msg.sender, deal.remainingAmount);
    /// @dev we now set the remaining amount to 0 and ensure the open flag is set to false, thus this deal can no longer be interacted with
    deal.remainingAmount = 0;
    deal.open = false;
    emit DealClosed(_d);
  }

  /**
   * @notice This function is what buyers use to make their OTC purchases
   * @param _d is the index of the deal that a buyer wants to participate in and make a purchase
   * @param _amount is the amount of tokens the buyer is willing to purchase, which must be at least the minimumPurchase and at most the remainingAmount for this deal
   * @notice ensure when using this function that you are aware of the minimums, and price per token to ensure sufficient balances to make a purchase
   * @notice if the deal has an unlockDate that is beyond the current block time - no tokens will be received by the buyer, but rather they will receive
   * @notice an NFT, which represents their ability to redeem and claim the locked tokens after the unlockDate has passed
   * @notice the NFT received is a separate smart contract, which also contains the locked tokens
   * @notice the Seller will receive payment in full immediately when triggering this function, there is no lock on payments
   */
  function buy(uint256 _d, uint256 _amount) external nonReentrant {
    /// @dev pull the deal details from storage
    Deal storage deal = deals[_d];
    /// @dev we do not let the seller sell to themselves, must be a separate buyer
    require(msg.sender != deal.seller, 'HEC07: Buyer cannot be seller');
    /// @dev require that the deal order is still valid by checking the open bool, as well as the maturity of the deal being in the future block time
    require(deal.open && deal.maturity >= block.timestamp, 'HEC06: Deal has been closed');
    /// @dev if the deal had a whitelist - then require the msg.sender to be that buyer, otherwise if there was no whitelist, anyone can buy
    require(msg.sender == deal.buyer || deal.buyer == address(0x0), 'HEC08: Whitelist or buyer allowance error');
    /// @dev require that the amount being purchased is greater than the deal minimum, or that the amount being purchased is the entire remainder of whats left
    /// @dev AND require that the remaining amount in the deal actually equals or exceeds what the buyer wants to purchase
    require(
      (_amount >= deal.minimumPurchase || _amount == deal.remainingAmount) && deal.remainingAmount >= _amount,
      'HEC09: Insufficient Purchase Size'
    );
    /// @dev we calculate the purchase amount taking the decimals from the token first
    /// @dev then multiply the amount by the per token price, and now to get back to an amount denominated in the payment currency divide by the factor of token decimals
    uint256 decimals = Decimals(deal.token).decimals();
    uint256 purchase = (_amount * deal.price) / (10**decimals);
    /// @dev check to ensure the buyer actually has enough money to make the purchase
    require(IERC20(deal.paymentCurrency).balanceOf(msg.sender) >= purchase, 'HECB: Insufficient Balance');
    /// @dev transfer the purchase to the deal seller
    SafeERC20.safeTransferFrom(IERC20(deal.paymentCurrency), msg.sender, deal.seller, purchase);
    if (deal.unlockDate > block.timestamp) {
      /// @dev if the unlockdate is the in future, then we call our internal function lockTokens to lock those in the NFT contract
      _lockTokens(msg.sender, deal.token, _amount, deal.unlockDate);
    } else {
      /// @dev if the unlockDate is in the past or now - then tokens are already unlocked and delivered directly to the buyer
      SafeERC20.safeTransfer(IERC20(deal.token), msg.sender, _amount);
    }
    /// @dev reduce the deal remaining amount by how much was purchased. If the remainder is 0, then we consider this deal closed and set our open bool to false
    deal.remainingAmount -= _amount;
    if (deal.remainingAmount == 0) deal.open = false;
    emit TokensBought(_d, _amount, deal.remainingAmount);
  }

  /// @dev internal function that handles the locking of the tokens in the NFT Futures contract
  /// @param _owner address here becomes the owner of the NFT
  /// @param _token address here is the asset that is locked in the NFT Future
  /// @param _amount is the amount of tokens that will be locked
  /// @param _unlockDate provides the unlock date which is the expiration date for the Future generated
  function _lockTokens(
    address _owner,
    address _token,
    uint256 _amount,
    uint256 _unlockDate
  ) internal {
    require(_unlockDate > block.timestamp, 'HEC10: Unlocked');
    /// @dev similar to checking the balances for the OTC contract when creating a new deal - we check the current and post balance in the NFT contract
    /// @dev to ensure that 100% of the amount of tokens to be locked are in fact locked in the contract address
    uint256 currentBalance = IERC20(_token).balanceOf(futureContract);
    /// @dev increase allowance so that the NFT contract can pull the total funds
    /// @dev this is a safer way to ensure that the entire amount is delivered to the NFT contract
    SafeERC20.safeIncreaseAllowance(IERC20(_token), futureContract, _amount);
    /// @dev this function points to the NFT Futures contract and calls its function to mint an NFT and generate the locked tokens future struct
    INFT(futureContract).createNFT(_owner, _amount, _token, _unlockDate);
    /// @dev check to make sure that what is received by the futures contract equals the total amount we have delivered
    /// @dev this prevents functionality with deflationary or tax tokens that have not whitelisted these address
    uint256 postBalance = IERC20(_token).balanceOf(futureContract);
    assert(postBalance - currentBalance == _amount);
    emit FutureCreated(_owner, _token, _unlockDate, _amount);
  }

  /// @dev events for each function
  event NewDeal(
    uint256 _d,
    address _seller,
    address _token,
    address _paymentCurrency,
    uint256 _remainingAmount,
    uint256 _minimumPurchase,
    uint256 _price,
    uint256 _maturity,
    uint256 _unlockDate,
    bool open,
    address _buyer
  );
  event TokensBought(uint256 _d, uint256 _amount, uint256 _remainingAmount);
  event DealClosed(uint256 _d);
  event FutureCreated(address _owner, address _token, uint256 _unlockDate, uint256 _amount);
}
