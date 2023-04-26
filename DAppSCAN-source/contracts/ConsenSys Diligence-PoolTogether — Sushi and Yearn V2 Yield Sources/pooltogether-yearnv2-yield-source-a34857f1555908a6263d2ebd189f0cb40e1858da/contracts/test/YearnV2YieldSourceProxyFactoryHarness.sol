// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.6.0 <0.7.0;

import "./YearnV2YieldSourceHarness.sol";
import "../external/openzeppelin/ProxyFactory.sol";
import "../yield-source/YearnV2YieldSourceProxyFactory.sol";

/// @title YearnV2 Yield Source Proxy Factory
/// @notice Minimal proxy pattern for creating new YearnV2 Yield Sources
contract YearnV2YieldSourceProxyFactoryHarness is ProxyFactory {

  /// @notice Contract template for deploying proxied aToken Yield Sources
  YearnV2YieldSourceHarness public instance;

  /// @notice Initializes the Factory with an instance of the YearnV2 Yield Source
  constructor () public {
    instance = new YearnV2YieldSourceHarness();
  }

  /// @notice Creates a new YearnV2 Yield Source as a proxy of the template instance
  /// @param _vault YearnV2 Vault address
  /// @param _token Underlying Token address
  /// @return A reference to the new proxied YearnV2 Yield Sources
  function create(
    IYVaultV2 _vault,
    IERC20Upgradeable _token
  ) public returns (YearnV2YieldSourceHarness) {
    YearnV2YieldSourceHarness yearnV2YieldSourceHarness = YearnV2YieldSourceHarness(deployMinimal(address(instance), ""));

    yearnV2YieldSourceHarness.initialize(_vault, _token);

    return yearnV2YieldSourceHarness;
  }
}
