// SPDX-License-Identifier: MIT
pragma solidity 0.7.5;

import "./IVaultHandler.sol";
import "./Orchestrator.sol";

/**
 * @title ERC-20 TCAP Vault
 * @author Cryptex.finance
 * @notice Contract in charge of handling the TCAP Vault and stake using a Collateral ERC20
 */
contract ERC20VaultHandler is IVaultHandler {
	/**
	 * @notice Constructor
   * @param _orchestrator address
   * @param _divisor uint256
   * @param _ratio uint256
   * @param _burnFee uint256
   * @param _liquidationPenalty uint256
   * @param _tcapOracle address
   * @param _tcapAddress address
   * @param _collateralAddress address
   * @param _collateralOracle address
   * @param _ethOracle address
   * @param _treasury address
   * @param _minimumTCAP uint256
   */
	constructor(
		Orchestrator _orchestrator,
		uint256 _divisor,
		uint256 _ratio,
		uint256 _burnFee,
		uint256 _liquidationPenalty,
		address _tcapOracle,
		TCAP _tcapAddress,
		address _collateralAddress,
		address _collateralOracle,
		address _ethOracle,
		address _treasury,
		uint256 _minimumTCAP
	)
	IVaultHandler(
		_orchestrator,
		_divisor,
		_ratio,
		_burnFee,
		_liquidationPenalty,
		_tcapOracle,
		_tcapAddress,
		_collateralAddress,
		_collateralOracle,
		_ethOracle,
		_treasury,
		_minimumTCAP
	)
	{}
}
