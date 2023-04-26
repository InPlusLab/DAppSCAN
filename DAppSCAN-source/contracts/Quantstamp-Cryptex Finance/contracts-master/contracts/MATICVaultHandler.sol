// SPDX-License-Identifier: MIT
pragma solidity 0.7.5;

import "./IVaultHandler.sol";
import "./Orchestrator.sol";
import "./IWMATIC.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

/**
 * @title MATIC TCAP Vault
 * @author Cryptex.finance
 * @notice Contract in charge of handling the TCAP Vault and stake using a MATIC and WMATIC
 */
contract MATICVaultHandler is IVaultHandler {
	/// @notice Open Zeppelin libraries
	using SafeMath for uint256;

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
		address _maticOracle,
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
		_maticOracle,
		_treasury,
		_minimumTCAP

	)
	{}

	/**
	 * @notice only accept MATIC via fallback from the WMATIC contract
	 */
	receive() external payable {
		assert(msg.sender == address(collateralContract));
	}

	/**
	 * @notice Adds collateral to vault using MATIC
	 * @dev value should be higher than 0
	 * @dev MATIC is turned into WMATIC
	 */
	function addCollateralMATIC()
	external
	payable
	nonReentrant
	vaultExists
	whenNotPaused
	{
		require(
			msg.value > 0,
			"MATICVaultHandler::addCollateralMATIC: value can't be 0"
		);
		IWMATIC(address(collateralContract)).deposit{value : msg.value}();
		Vault storage vault = vaults[userToVault[msg.sender]];
		vault.Collateral = vault.Collateral.add(msg.value);
		emit CollateralAdded(msg.sender, vault.Id, msg.value);
	}

	/**
	 * @notice Removes not used collateral from vault
	 * @param _amount of collateral to remove
	 * @dev _amount should be higher than 0
	 * @dev WMATIC is turned into MATIC
	 */
	function removeCollateralMATIC(uint256 _amount)
	external
	nonReentrant
	vaultExists
	whenNotPaused
	{
		require(
			_amount > 0,
			"MATICVaultHandler::removeCollateralMATIC: value can't be 0"
		);
		Vault storage vault = vaults[userToVault[msg.sender]];
		uint256 currentRatio = getVaultRatio(vault.Id);
		require(
			vault.Collateral >= _amount,
			"WMATICVaultHandler::removeCollateralMATIC: retrieve amount higher than collateral"
		);
		vault.Collateral = vault.Collateral.sub(_amount);
		if (currentRatio != 0) {
			require(
				getVaultRatio(vault.Id) >= ratio,
				"MATICVaultHandler::removeCollateralMATIC: collateral below min required ratio"
			);
		}

		IWMATIC(address(collateralContract)).withdraw(_amount);
		safeTransferETH(msg.sender, _amount);
		emit CollateralRemoved(msg.sender, vault.Id, _amount);
	}
}
