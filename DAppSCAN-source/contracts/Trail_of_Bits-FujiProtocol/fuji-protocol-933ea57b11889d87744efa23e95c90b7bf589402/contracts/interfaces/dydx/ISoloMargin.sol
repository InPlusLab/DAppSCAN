// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../libraries/FlashLoans.sol";

interface ISoloMargin {
  struct Price {
    uint256 value;
  }

  struct Value {
    uint256 value;
  }

  struct Rate {
    uint256 value;
  }

  struct Wei {
    bool sign;
    uint256 value;
  }

  function operate(Account.Info[] calldata _accounts, Actions.ActionArgs[] calldata _actions) external;

  function getAccountWei(Account.Info calldata _account, uint256 _marketId)
    external
    view
    returns (Wei memory);

  function getNumMarkets() external view returns (uint256);

  function getMarketTokenAddress(uint256 _marketId) external view returns (address);

  function getAccountValues(Account.Info memory _account)
    external
    view
    returns (Value memory, Value memory);

  function getMarketInterestRate(uint256 _marketId) external view returns (Rate memory);
}
