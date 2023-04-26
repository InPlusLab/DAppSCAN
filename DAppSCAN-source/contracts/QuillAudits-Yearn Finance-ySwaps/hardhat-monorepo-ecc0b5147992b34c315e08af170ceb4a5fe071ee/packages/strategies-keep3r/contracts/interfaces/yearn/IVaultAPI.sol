// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

struct StrategyParams {
  uint256 performanceFee;
  uint256 activation;
  uint256 debtRatio;
  uint256 rateLimit;
  uint256 lastReport;
  uint256 totalDebt;
  uint256 totalGain;
  uint256 totalLoss;
}

interface VaultAPI is IERC20 {
  function apiVersion() external view returns (string memory);

  function withdraw(uint256 shares, address recipient) external;

  function token() external view returns (address);

  function totalAssets() external view returns (uint256);

  function strategies(address _strategy) external view returns (StrategyParams memory);

  /**
   * View how much the Vault would increase this Strategy's borrow limit,
   * based on its present performance (since its last report). Can be used to
   * determine expectedReturn in your Strategy.
   */
  function creditAvailable(address _strategy) external view returns (uint256);

  /**
   * View how much the Vault would like to pull back from the Strategy,
   * based on its present performance (since its last report). Can be used to
   * determine expectedReturn in your Strategy.
   */
  function debtOutstanding() external view returns (uint256);

  /**
   * View how much the Vault expect this Strategy to return at the current
   * block, based on its present performance (since its last report). Can be
   * used to determine expectedReturn in your Strategy.
   */
  function expectedReturn() external view returns (uint256);

  /**
   * This is the main contact point where the Strategy interacts with the
   * Vault. It is critical that this call is handled as intended by the
   * Strategy. Therefore, this function will be called by BaseStrategy to
   * make sure the integration is correct.
   */
  function report(
    uint256 _gain,
    uint256 _loss,
    uint256 _debtPayment
  ) external returns (uint256);

  /**
   * This function should only be used in the scenario where the Strategy is
   * being retired but no migration of the positions are possible, or in the
   * extreme scenario that the Strategy needs to be put into "Emergency Exit"
   * mode in order for it to exit as quickly as possible. The latter scenario
   * could be for any reason that is considered "critical" that the Strategy
   * exits its position as fast as possible, such as a sudden change in
   * market conditions leading to losses, or an imminent failure in an
   * external dependency.
   */
  function revokeStrategy() external;

  /**
   * View the governance address of the Vault to assert privileged functions
   * can only be called by governance. The Strategy serves the Vault, so it
   * is subject to governance defined by the Vault.
   */
  function governance() external view returns (address);
}
