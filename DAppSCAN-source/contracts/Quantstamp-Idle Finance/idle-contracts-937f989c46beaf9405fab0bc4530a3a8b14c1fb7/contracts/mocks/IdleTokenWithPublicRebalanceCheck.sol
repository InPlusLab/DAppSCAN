/**
 * @title: Idle Token main contract
 * @summary: ERC20 that holds pooled user funds together
 *           Each token rapresent a share of the underlying pools
 *           and with each token user have the right to redeem a portion of these pools
 * @author: William Bergamo, idle.finance
 */
pragma solidity 0.5.11;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/lifecycle/Pausable.sol";

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../interfaces/iERC20Fulcrum.sol";
import "../interfaces/ILendingProtocol.sol";
import "../interfaces/IIdleToken.sol";

import "../IdleRebalancer.sol";
import "../IdlePriceCalculator.sol";

contract IdleTokenWithPublicRebalanceCheck is ERC20, ERC20Detailed, ReentrancyGuard, Ownable, Pausable, IIdleToken {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  // protocolWrappers may be changed/updated/removed do not rely on their
  // addresses to determine where funds are allocated

  // eg. cTokenAddress => IdleCompoundAddress
  mapping(address => address) public protocolWrappers;
  // eg. DAI address
  address public token;
  // eg. iDAI address
  address public iToken; // used for claimITokens and userClaimITokens
  // Min thresold of APR difference between protocols to trigger a rebalance
  uint256 public minRateDifference;
  // Idle rebalancer current implementation address
  address public rebalancer;
  // Idle rebalancer current implementation address
  address public priceCalculator;
  // Last iToken price, used to pause contract in case of a black swan event
  uint256 public lastITokenPrice;
  // Manual trigger for unpausing contract in case of a black swan event that caused the iToken price to not
  // return to the normal level
  bool public manualPlay = false;

  // no one can directly change this
  // Idle pool current investments eg. [cTokenAddress, iTokenAddress]
  address[] public currentTokensUsed;
  // eg. [cTokenAddress, iTokenAddress, ...]
  address[] public allAvailableTokens;

  struct TokenProtocol {
    address tokenAddr;
    address protocolAddr;
  }

  event Rebalance(uint256 amount);

  /**
   * @dev constructor, initialize some variables, mainly addresses of other contracts
   *
   * @param _name : IdleToken name
   * @param _symbol : IdleToken symbol
   * @param _decimals : IdleToken decimals
   * @param _token : underlying token address
   * @param _cToken : cToken address
   * @param _iToken : iToken address
   * @param _rebalancer : Idle Rebalancer address
   * @param _idleCompound : Idle Compound address
   * @param _idleFulcrum : Idle Fulcrum address
   */
  constructor(
    string memory _name, // eg. IdleDAI
    string memory _symbol, // eg. IDLEDAI
    uint8 _decimals, // eg. 18
    address _token,
    address _cToken,
    address _iToken,
    address _rebalancer,
    address _priceCalculator,
    address _idleCompound,
    address _idleFulcrum)
    public
    ERC20Detailed(_name, _symbol, _decimals) {
      token = _token;
      iToken = _iToken; // used for claimITokens and userClaimITokens methods
      rebalancer = _rebalancer;
      priceCalculator = _priceCalculator;
      protocolWrappers[_cToken] = _idleCompound;
      protocolWrappers[_iToken] = _idleFulcrum;
      allAvailableTokens = [_cToken, _iToken];
      minRateDifference = 100000000000000000; // 0.1% min
  }

  modifier whenITokenPriceHasNotDecreased() {
    uint256 iTokenPrice = iERC20Fulcrum(iToken).tokenPrice();
    require(
      iTokenPrice >= lastITokenPrice || manualPlay,
      "Paused: iToken price decreased"
    );

    _;

    if (iTokenPrice > lastITokenPrice) {
      lastITokenPrice = iTokenPrice;
    }
  }

  // onlyOwner
  /**
   * It allows owner to set the underlying token address
   *
   * @param _token : underlying token address tracked by this contract (eg DAI address)
   */
  function setToken(address _token)
    external onlyOwner {
      token = _token;
  }
  /**
   * It allows owner to set the iToken (Fulcrum) address
   *
   * @param _iToken : iToken address
   */
  function setIToken(address _iToken)
    external onlyOwner {
      iToken = _iToken;
  }
  /**
   * It allows owner to set the IdleRebalancer address
   *
   * @param _rebalancer : new IdleRebalancer address
   */
  function setRebalancer(address _rebalancer)
    external onlyOwner {
      rebalancer = _rebalancer;
  }
  /**
   * It allows owner to set the IdlePriceCalculator address
   *
   * @param _priceCalculator : new IdlePriceCalculator address
   */
  function setPriceCalculator(address _priceCalculator)
    external onlyOwner {
      priceCalculator = _priceCalculator;
  }
  /**
   * It allows owner to set a protocol wrapper address
   *
   * @param _token : underlying token address (eg. DAI)
   * @param _wrapper : Idle protocol wrapper address
   */
  function setProtocolWrapper(address _token, address _wrapper)
    external onlyOwner {
      // update allAvailableTokens if needed
      if (protocolWrappers[_token] == address(0)) {
        allAvailableTokens.push(_token);
      }
      protocolWrappers[_token] = _wrapper;
  }

  function setMinRateDifference(uint256 _rate)
    external onlyOwner {
      minRateDifference = _rate;
  }
  /**
   * It allows owner to unpause the contract when iToken price decreased and didn't return to the expected level
   *
   * @param _manualPlay : new IdleRebalancer address
   */
  function setManualPlay(bool _manualPlay)
    external onlyOwner {
      manualPlay = _manualPlay;
  }

  // view
  /**
   * IdleToken price calculation, in underlying
   *
   * @return : price in underlying token
   */
  function tokenPrice()
    public view
    returns (uint256 price) {
      address[] memory protocolWrappersAddresses = new address[](currentTokensUsed.length);
      for (uint8 i = 0; i < currentTokensUsed.length; i++) {
        protocolWrappersAddresses[i] = protocolWrappers[currentTokensUsed[i]];
      }
      price = IdlePriceCalculator(priceCalculator).tokenPrice(
        this.totalSupply(), address(this), currentTokensUsed, protocolWrappersAddresses
      );
  }

  /**
   * Get APR of every ILendingProtocol
   *
   * @return addresses: array of token addresses
   * @return aprs: array of aprs (ordered in respect to the `addresses` array)
   */
  function getAPRs()
    public view
    returns (address[] memory addresses, uint256[] memory aprs) {
      address currToken;
      addresses = new address[](allAvailableTokens.length);
      aprs = new uint256[](allAvailableTokens.length);
      for (uint8 i = 0; i < allAvailableTokens.length; i++) {
        currToken = allAvailableTokens[i];
        addresses[i] = currToken;
        aprs[i] = ILendingProtocol(protocolWrappers[currToken]).getAPR();
      }
  }

  // external
  // We should save the amount one has deposited to calc interests

  /**
   * Used to mint IdleTokens, given an underlying amount (eg. DAI).
   * This method triggers a rebalance of the pools if needed
   * NOTE: User should 'approve' _amount of tokens before calling mintIdleToken
   * NOTE 2: this method can be paused
   *
   * @param _amount : amount of underlying token to be lended
   * @param _clientProtocolAmounts : client side calculated amounts to put on each lending protocol
   * @return mintedTokens : amount of IdleTokens minted
   */
  function mintIdleToken(uint256 _amount, uint256[] calldata _clientProtocolAmounts)
    external nonReentrant whenNotPaused whenITokenPriceHasNotDecreased
    returns (uint256 mintedTokens) {
      // Get current IdleToken price
      uint256 idlePrice = tokenPrice();
      // transfer tokens to this contract
      IERC20(token).safeTransferFrom(msg.sender, address(this), _amount);
      // Rebalance the current pool if needed and mint new supplyied amount
      rebalance(_amount, _clientProtocolAmounts);

      mintedTokens = _amount.mul(10**18).div(idlePrice);
      _mint(msg.sender, mintedTokens);
  }

  /**
   * Here we calc the pool share one can withdraw given the amount of IdleToken they want to burn
   * This method triggers a rebalance of the pools if needed
   * NOTE: If the contract is paused or iToken price has decreased one can still redeem but no rebalance happens.
   * NOTE 2: If iToken price has decresed one should not redeem (but can do it) otherwise he would capitalize the loss.
   *         Ideally one should wait until the black swan event is terminated
   *
   * @param _amount : amount of IdleTokens to be burned
   * @param _clientProtocolAmounts : client side calculated amounts to put on each lending protocol
   * @return redeemedTokens : amount of underlying tokens redeemed
   */
  function redeemIdleToken(uint256 _amount, bool _skipRebalance, uint256[] calldata _clientProtocolAmounts)
    external nonReentrant
    returns (uint256 redeemedTokens) {
      address currentToken;

      for (uint8 i = 0; i < currentTokensUsed.length; i++) {
        currentToken = currentTokensUsed[i];
        redeemedTokens = redeemedTokens.add(
          _redeemProtocolTokens(
            protocolWrappers[currentToken],
            currentToken,
            // _amount * protocolPoolBalance / idleSupply
            _amount.mul(IERC20(currentToken).balanceOf(address(this))).div(this.totalSupply()), // amount to redeem
            msg.sender
          )
        );
      }

      _burn(msg.sender, _amount);

      // Do not rebalance if contract is paused or iToken price has decreased
      if (this.paused() || iERC20Fulcrum(iToken).tokenPrice() < lastITokenPrice || _skipRebalance) {
        return redeemedTokens;
      }

      rebalance(0, _clientProtocolAmounts);
  }

  /**
   * Here we calc the pool share one can withdraw given the amount of IdleToken they want to burn
   * and send interest-bearing tokens (eg. cDAI/iDAI) directly to the user.
   * Underlying (eg. DAI) is not redeemed here.
   *
   * @param _amount : amount of IdleTokens to be burned
   */
  function redeemInterestBearingTokens(uint256 _amount)
    external nonReentrant {
      uint256 idleSupply = this.totalSupply();
      require(idleSupply > 0, "No IDLEDAI have been issued");

      address currentToken;

      for (uint8 i = 0; i < currentTokensUsed.length; i++) {
        currentToken = currentTokensUsed[i];
        IERC20(currentToken).safeTransfer(
          msg.sender,
          _amount.mul(IERC20(currentToken).balanceOf(address(this))).div(idleSupply) // amount to redeem
        );
      }

      _burn(msg.sender, _amount);
  }

  /**
   * Here we are redeeming unclaimed token from iToken contract to this contracts
   * then allocating claimedTokens with rebalancing
   * Everyone should be incentivized in calling this method
   * NOTE: this method can be paused
   *
   * @param _clientProtocolAmounts : client side calculated amounts to put on each lending protocol
   * @return claimedTokens : amount of underlying tokens claimed
   */
  function claimITokens(uint256[] calldata _clientProtocolAmounts)
    external whenNotPaused whenITokenPriceHasNotDecreased
    returns (uint256 claimedTokens) {
      claimedTokens = iERC20Fulcrum(iToken).claimLoanToken();
      rebalance(claimedTokens, _clientProtocolAmounts);
  }

  /**
   * Dynamic allocate all the pool across different lending protocols if needed
   * Everyone should be incentivized in calling this method
   *
   * If _newAmount == 0 then simple rebalance
   * else rebalance (if needed) and mint (always)
   * NOTE: this method can be paused
   *
   * @param _newAmount : amount of underlying tokens that needs to be minted with this rebalance
   * @param _clientProtocolAmounts : client side calculated amounts to put on each lending protocol
   * @return : whether has rebalanced or not
   */

  function rebalance(uint256 _newAmount, uint256[] memory _clientProtocolAmounts)
    public whenNotPaused whenITokenPriceHasNotDecreased
    returns (bool) {
      // If we are using only one protocol we check if that protocol has still the best apr
      // if yes we check if it can support all `_newAmount` provided and still has the best apr

      bool shouldRebalance;
      address bestToken;

      if (currentTokensUsed.length == 1 && _newAmount > 0) {
        (shouldRebalance, bestToken) = _rebalanceCheck(_newAmount, currentTokensUsed[0]);

        if (!shouldRebalance) {
          // only one protocol is currently used and can support all the new liquidity
          _mintProtocolTokens(protocolWrappers[currentTokensUsed[0]], _newAmount);
          return false; // hasNotRebalanced
        }
      }

      // otherwise we redeem everything from every protocol and check if the protocol with the
      // best apr can support all the liquidity that we redeemed

      // - get current protocol used
      TokenProtocol[] memory tokenProtocols = _getCurrentProtocols();
      // - redeem everything from each protocol
      for (uint8 i = 0; i < tokenProtocols.length; i++) {
        _redeemProtocolTokens(
          tokenProtocols[i].protocolAddr,
          tokenProtocols[i].tokenAddr,
          IERC20(tokenProtocols[i].tokenAddr).balanceOf(address(this)),
          address(this) // tokens are now in this contract
        );
      }
      // remove all elements from `currentTokensUsed`
      delete currentTokensUsed;

      // tokenBalance here has already _newAmount counted
      uint256 tokenBalance = IERC20(token).balanceOf(address(this));

      // (we are re-fetching aprs because after redeeming they changed)
      (shouldRebalance, bestToken) = _rebalanceCheck(tokenBalance, address(0));

      if (!shouldRebalance) {
        // only one protocol is currently used and can support all the new liquidity
        _mintProtocolTokens(protocolWrappers[bestToken], tokenBalance);
        // update current tokens used in IdleToken storage
        currentTokensUsed.push(bestToken);
        return false; // hasNotRebalanced
      }

      // if it's not the case we calculate the dynamic allocation for every protocol
      (address[] memory tokenAddresses, uint256[] memory protocolAmounts) = _calcAmounts(tokenBalance, _clientProtocolAmounts);

      // mint for each protocol and update currentTokensUsed
      uint256 currAmount;
      address currAddr;
      for (uint8 i = 0; i < protocolAmounts.length; i++) {
        currAmount = protocolAmounts[i];
        if (currAmount == 0) {
          continue;
        }
        currAddr = tokenAddresses[i];
        _mintProtocolTokens(protocolWrappers[currAddr], currAmount);
        // update current tokens used in IdleToken storage
        currentTokensUsed.push(currAddr);
      }

      emit Rebalance(tokenBalance);

      return true; // hasRebalanced
  }

  // internal
  /**
   * Check if a rebalance is needed
   * if there is only one protocol and has the best rate then check the nextRateWithAmount()
   * if rate is still the highest then put everything there
   * otherwise rebalance with all amount
   *
   * @param _amount : amount of underlying tokens that needs to be added to the current pools NAV
   * @return : whether should rebalanced or not
   */

  function _rebalanceCheck(uint256 _amount, address currentToken)
    public view
    returns (bool, address) {
      (address[] memory addresses, uint256[] memory aprs) = getAPRs();
      if (aprs.length == 0) {
        return (false, address(0));
      }

      // we are trying to find if the protocol with the highest APR can support all the liquidity
      // we intend to provide
      uint256 maxRate;
      address maxAddress;
      uint256 secondBestRate;
      uint256 currApr;
      address currAddr;

      // find best rate and secondBestRate
      for (uint8 i = 0; i < aprs.length; i++) {
        currApr = aprs[i];
        currAddr = addresses[i];
        if (currApr > maxRate) {
          secondBestRate = maxRate;
          maxRate = currApr;
          maxAddress = currAddr;
        } else if (currApr <= maxRate && currApr >= secondBestRate) {
          secondBestRate = currApr;
        }
      }

      if (currentToken != address(0) && currentToken != maxAddress) {
        return (true, maxAddress);
      }

      if (currentToken == address(0) || currentToken == maxAddress) {
        uint256 nextRate = _getProtocolNextRate(protocolWrappers[maxAddress], _amount);
        if (nextRate.add(minRateDifference) < secondBestRate) {
          return (true, maxAddress);
        }
      }

      return (false, maxAddress);
  }

  /**
   * Calls IdleRebalancer `calcRebalanceAmounts` method
   *
   * @param _amount : amount of underlying tokens that needs to be allocated on lending protocols
   * @return tokenAddresses : array with all token addresses used,
   * @return amounts : array with all amounts for each protocol in order,
   */
  function _calcAmounts(uint256 _amount, uint256[] memory _clientProtocolAmounts)
    internal view
    returns (address[] memory, uint256[] memory) {
      uint256[] memory paramsRebalance = new uint256[](_clientProtocolAmounts.length + 1);
      paramsRebalance[0] = _amount;

      for (uint8 i = 1; i < _clientProtocolAmounts.length; i++) {
        paramsRebalance[i] = _clientProtocolAmounts[i-1];
      }

      return IdleRebalancer(rebalancer).calcRebalanceAmounts(paramsRebalance);
  }

  /**
   * Get addresses of current tokens and protocol wrappers used
   *
   * @return currentProtocolsUsed : array of `TokenProtocol` (currentToken address, protocolWrapper address)
   */
  function _getCurrentProtocols()
    internal view
    returns (TokenProtocol[] memory currentProtocolsUsed) {
      currentProtocolsUsed = new TokenProtocol[](currentTokensUsed.length);
      for (uint8 i = 0; i < currentTokensUsed.length; i++) {
        currentProtocolsUsed[i] = TokenProtocol(
          currentTokensUsed[i],
          protocolWrappers[currentTokensUsed[i]]
        );
      }
  }

  // ILendingProtocols calls
  /**
   * Get next rate of a lending protocol given an amount to be lended
   *
   * @param _wrapperAddr : address of protocol wrapper
   * @param _amount : amount of underlying to be lended
   * @return apr : new apr one will get after lending `_amount`
   */
  function _getProtocolNextRate(address _wrapperAddr, uint256 _amount)
    internal view
    returns (uint256 apr) {
      ILendingProtocol _wrapper = ILendingProtocol(_wrapperAddr);
      apr = _wrapper.nextSupplyRate(_amount);
  }

  /**
   * Mint protocol tokens through protocol wrapper
   *
   * @param _wrapperAddr : address of protocol wrapper
   * @param _amount : amount of underlying to be lended
   * @return tokens : new tokens minted
   */
  function _mintProtocolTokens(address _wrapperAddr, uint256 _amount)
    internal
    returns (uint256 tokens) {
      if (_amount == 0) {
        return tokens;
      }
      ILendingProtocol _wrapper = ILendingProtocol(_wrapperAddr);
      // Transfer _amount underlying token (eg. DAI) to _wrapperAddr
      IERC20(token).safeTransfer(_wrapperAddr, _amount);
      tokens = _wrapper.mint();
  }

  /**
   * Redeem underlying tokens through protocol wrapper
   *
   * @param _wrapperAddr : address of protocol wrapper
   * @param _amount : amount of `_token` to redeem
   * @param _token : protocol token address
   * @param _account : should be msg.sender when rebalancing and final user when redeeming
   * @return tokens : new tokens minted
   */
  function _redeemProtocolTokens(address _wrapperAddr, address _token, uint256 _amount, address _account)
    internal
    returns (uint256 tokens) {
      if (_amount == 0) {
        return tokens;
      }
      ILendingProtocol _wrapper = ILendingProtocol(_wrapperAddr);
      // Transfer _amount of _protocolToken (eg. cDAI) to _wrapperAddr
      IERC20(_token).safeTransfer(_wrapperAddr, _amount);
      tokens = _wrapper.redeem(_account);
  }
}
