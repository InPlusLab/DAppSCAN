// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

library Account {
  enum Status {
    Normal,
    Liquid,
    Vapor
  }
  struct Info {
    address owner; // The address that owns the account
    uint256 number; // A nonce that allows a single address to control many accounts
  }
}

library Actions {
  enum ActionType {
    Deposit, // supply tokens
    Withdraw, // borrow tokens
    Transfer, // transfer balance between accounts
    Buy, // buy an amount of some token (publicly)
    Sell, // sell an amount of some token (publicly)
    Trade, // trade tokens against another account
    Liquidate, // liquidate an undercollateralized or expiring account
    Vaporize, // use excess tokens to zero-out a completely negative account
    Call // send arbitrary data to an address
  }

  struct ActionArgs {
    ActionType actionType;
    uint256 accountId;
    Types.AssetAmount amount;
    uint256 primaryMarketId;
    uint256 secondaryMarketId;
    address otherAddress;
    uint256 otherAccountId;
    bytes data;
  }
}

library Types {
  enum AssetDenomination {
    Wei, // the amount is denominated in wei
    Par // the amount is denominated in par
  }

  enum AssetReference {
    Delta, // the amount is given as a delta from the current value
    Target // the amount is given as an exact number to end up at
  }

  struct AssetAmount {
    bool sign; // true if positive
    AssetDenomination denomination;
    AssetReference ref;
    uint256 value;
  }
}

library FlashLoan {
  /**
   * @dev Used to determine which vault's function to call post-flashloan:
   * - Switch for executeSwitch(...)
   * - Close for executeFlashClose(...)
   * - Liquidate for executeFlashLiquidation(...)
   * - BatchLiquidate for executeFlashBatchLiquidation(...)
   */
  enum CallType {
    Switch,
    Close,
    BatchLiquidate
  }

  /**
   * @dev Struct of params to be passed between functions executing flashloan logic
   * @param asset: Address of asset to be borrowed with flashloan
   * @param amount: Amount of asset to be borrowed with flashloan
   * @param vault: Vault's address on which the flashloan logic to be executed
   * @param newProvider: New provider's address. Used when callType is Switch
   * @param userAddrs: User's address array Used when callType is BatchLiquidate
   * @param userBals:  Array of user's balances, Used when callType is BatchLiquidate
   * @param userliquidator: The user's address who is  performing liquidation. Used when callType is Liquidate
   * @param fliquidator: Fujis Liquidator's address.
   */
  struct Info {
    CallType callType;
    address asset;
    uint256 amount;
    address vault;
    address newProvider;
    address[] userAddrs;
    uint256[] userBalances;
    address userliquidator;
    address fliquidator;
  }
}
