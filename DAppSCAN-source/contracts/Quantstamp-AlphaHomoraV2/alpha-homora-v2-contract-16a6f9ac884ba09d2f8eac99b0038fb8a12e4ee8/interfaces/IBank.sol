pragma solidity 0.6.12;

interface IBank {
  /// The governor adds a new bank gets added to the system.
  event AddBank(address token, address cToken);
  /// The governor upgrades the cToken address for the given bank.
  event SetCToken(address token, address cToken);
  /// The governor sets the address of the oracle smart contract.
  event SetOracle(address oracle);
  /// The governor sets the basis point fee of the bank.
  event SetFeeBps(uint feeBps);
  /// The governor withdraw tokens from the reserve of a bank.
  event WithdrawReserve(address user, address token, uint amount);
  /// Someone borrows tokens from a bank via a spell caller.
  event Borrow(uint positionId, address caller, address token, uint amount, uint share);
  /// Someone repays tokens to a bank via a spell caller.
  event Repay(uint positionId, address caller, address token, uint amount, uint share);
  /// Someone puts tokens as collateral via a spell caller.
  event PutCollateral(uint positionId, address caller, address token, uint id, uint amount);
  /// Someone takes tokens from collateral via a spell caller.
  event TakeCollateral(uint positionId, address caller, address token, uint id, uint amount);
  /// Someone calls liquidatation on a position, paying debt and taking collateral tokens.
  event Liquidate(
    uint positionId,
    address liquidator,
    address debtToken,
    uint amount,
    uint share,
    uint bounty
  );

  /// @dev Return the current position while under execution.
  function POSITION_ID() external view returns (uint);

  /// @dev Return the current target while under execution.
  function SPELL() external view returns (address);

  /// @dev Return the current executor (the owner of the current position).
  function EXECUTOR() external view returns (address);

  /// @dev Return bank information for the given token.
  function getBankInfo(address token)
    external
    view
    returns (
      bool isListed,
      address cToken,
      uint reserve,
      uint totalDebt,
      uint totalShare
    );

  /// @dev Return position information for the given position id.
  function getPositionInfo(uint positionId)
    external
    view
    returns (
      address owner,
      address collToken,
      uint collId,
      uint collateralSize
    );

  /// @dev Return the borrow balance for given positon and token without trigger interest accrual.
  function borrowBalanceStored(uint positionId, address token) external view returns (uint);

  /// @dev Trigger interest accrual and return the current borrow balance.
  function borrowBalanceCurrent(uint positionId, address token) external returns (uint);

  /// @dev Borrow tokens from the bank.
  function borrow(address token, uint amount) external;

  /// @dev Repays tokens to the bank.
  function repay(address token, uint amountCall) external;

  /// @dev Transmit user assets to the spell.
  function transmit(address token, uint amount) external;

  /// @dev Put more collateral for users.
  function putCollateral(
    address collToken,
    uint collId,
    uint amountCall
  ) external;

  /// @dev Take some collateral back.
  function takeCollateral(
    address collToken,
    uint collId,
    uint amount
  ) external;
}
