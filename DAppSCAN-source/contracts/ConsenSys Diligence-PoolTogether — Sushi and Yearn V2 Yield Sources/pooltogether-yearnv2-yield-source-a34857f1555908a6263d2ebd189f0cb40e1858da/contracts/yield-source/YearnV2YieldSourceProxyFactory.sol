// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.6.12;

import "./YearnV2YieldSource.sol";
import "../external/openzeppelin/ProxyFactory.sol";

/// @title YearnV2 Yield Source Proxy Factory
/// @notice Minimal proxy pattern for creating new YearnV2 Yield Sources
contract YearnV2YieldSourceProxyFactory is ProxyFactory {

  /// @notice Contract template for deploying proxied YearnV2 Yield Sources
  YearnV2YieldSource public instance;

  /// @notice Initializes the Factory with an instance of the YearnV2 Yield Source
  constructor () public {
    instance = new YearnV2YieldSource();
  }

  /// @notice Creates a new YearnV2 Yield Source as a proxy of the template instance
  /// @param _vault Vault address
  /// @param _token Underlying Token address
  /// @return A reference to the new proxied YearnV2 Yield Source
  function create(
    IYVaultV2 _vault,
    IERC20Upgradeable _token
  ) public returns (YearnV2YieldSource) {
    YearnV2YieldSource yearnV2YieldSource = YearnV2YieldSource(deployMinimal(address(instance), ""));

    yearnV2YieldSource.initialize(_vault, _token);

    return yearnV2YieldSource;
  }
}
