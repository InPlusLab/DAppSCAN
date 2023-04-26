// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.0;

/**
 * @title ILendingPoolLiquidationManager
 * @author Aave
 * @notice Defines the actions involving management of Liquidations in the protocol.
 **/
interface ILendingPoolLiquidationManager {
  /**
   * @dev Emitted when a borrower is liquidated
   * @param collateral The address of the collateral being liquidated
   * @param principal The address of the reserve
   * @param user The address of the user being liquidated
   * @param debtToCover The total amount liquidated
   * @param liquidatedCollateralAmount The amount of collateral being liquidated
   * @param liquidator The address of the liquidator
   * @param receiveAToken true if the liquidator wants to receive aTokens, false otherwise
   **/
  event LiquidationCall(address indexed collateral, address indexed principal, address indexed user, uint256 debtToCover, uint256 liquidatedCollateralAmount, address liquidator, bool receiveAToken);

  /**
   * @dev Emitted when a reserve is disabled as collateral for an user
   * @param reserve The address of the reserve
   * @param user The address of the user
   **/
  event InstrumentUsedAsCollateralDisabled(address indexed reserve, address indexed user);

  /**
   * @dev Emitted when a reserve is enabled as collateral for an user
   * @param reserve The address of the reserve
   * @param user The address of the user
   **/
  event InstrumentUsedAsCollateralEnabled(address indexed reserve, address indexed user);

  /**
   * @dev Emitted with the flash loan
   * @param _user The address of the user making the transaction
   * @param _receiver The address of receiver receiving the funds
   * @param _instrument The address of the instrument
   * @param _amount The loan amount
   * @param protocolFee The fee charged by the protocol
   * @param reserveFee The fee charged which is distributed among the depositors
   * @param boosterID The booster ID to avail discount
   **/
    event FlashLoan(address _user,address _receiver,address _instrument,uint _amount,uint protocolFee,uint reserveFee,uint16 boosterID);


  /**
   * @dev Users can invoke this function to liquidate an undercollateralized position.
   * @param collateral The address of the collateral to liquidated
   * @param principal The address of the principal reserve
   * @param user The address of the borrower
   * @param debtToCover The amount of principal that the liquidator wants to repay
   * @param receiveAToken true if the liquidators wants to receive the aTokens, false if
   * he wants to receive the underlying asset directly
   **/
  function liquidationCall(address collateral, address principal, address user, uint256 debtToCover, bool receiveAToken) external returns (uint256, string memory);
}