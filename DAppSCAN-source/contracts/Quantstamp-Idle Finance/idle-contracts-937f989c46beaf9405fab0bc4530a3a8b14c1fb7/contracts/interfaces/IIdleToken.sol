/**
 * @title: Idle Token interface
 * @author: William Bergamo, idle.finance
 */
pragma solidity 0.5.11;

interface IIdleToken {
  // view
  /**
   * IdleToken price calculation, in underlying
   *
   * @return : price in underlying token
   */
  function tokenPrice() external view returns (uint256 price);

  /**
   * Get APR of every ILendingProtocol
   *
   * @return addresses: array of token addresses
   * @return aprs: array of aprs (ordered in respect to the `addresses` array)
   */
  function getAPRs() external view returns (address[] memory addresses, uint256[] memory aprs);

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
  function mintIdleToken(uint256 _amount, uint256[] calldata _clientProtocolAmounts) external returns (uint256 mintedTokens);

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
    external returns (uint256 redeemedTokens);

  /**
   * Here we calc the pool share one can withdraw given the amount of IdleToken they want to burn
   * and send interest-bearing tokens (eg. cDAI/iDAI) directly to the user.
   * Underlying (eg. DAI) is not redeemed here.
   *
   * @param _amount : amount of IdleTokens to be burned
   */
  function redeemInterestBearingTokens(uint256 _amount) external;

  /**
   * @param _clientProtocolAmounts : client side calculated amounts to put on each lending protocol
   * @return claimedTokens : amount of underlying tokens claimed
   */
  function claimITokens(uint256[] calldata _clientProtocolAmounts) external returns (uint256 claimedTokens);

  /**
   * @param _newAmount : amount of underlying tokens that needs to be minted with this rebalance
   * @param _clientProtocolAmounts : client side calculated amounts to put on each lending protocol
   * @return : whether has rebalanced or not
   */

  function rebalance(uint256 _newAmount, uint256[] calldata _clientProtocolAmounts) external returns (bool);
}
