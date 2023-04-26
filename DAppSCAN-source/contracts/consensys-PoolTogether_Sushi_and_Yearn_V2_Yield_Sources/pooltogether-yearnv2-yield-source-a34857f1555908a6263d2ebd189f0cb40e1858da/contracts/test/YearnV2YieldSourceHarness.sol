// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.6.0 <0.7.0;

import "../yield-source/YearnV2YieldSource.sol";

/* solium-disable security/no-block-members */
contract YearnV2YieldSourceHarness is YearnV2YieldSource {
  function mint(address account, uint256 amount) public returns (bool) {
    _mint(account, amount);
    return true;
  }

  function balanceOfYShares() external view returns (uint256) {
      return _balanceOfYShares();
  }

  function pricePerYShare() external view returns (uint256) {
      return _pricePerYShare();
  }

  function totalAssetsInToken() external view returns (uint256) {
    return _totalAssetsInToken();
  }

  function vaultDecimals() external view returns (uint256) {
    return _vaultDecimals();
  }

  function tokenToShares(uint256 tokens) external view returns (uint256) {
    return _tokenToShares(tokens);
  }

  function sharesToToken(uint256 shares) external view returns (uint256) {
    return _sharesToToken(shares);
  }

  function tokenToYShares(uint256 tokens) external view returns (uint256) {
      return _tokenToYShares(tokens);
  }

  function ySharesToToken(uint256 yShares) external view returns (uint256) {
      return _ySharesToToken(yShares);
  }
}
