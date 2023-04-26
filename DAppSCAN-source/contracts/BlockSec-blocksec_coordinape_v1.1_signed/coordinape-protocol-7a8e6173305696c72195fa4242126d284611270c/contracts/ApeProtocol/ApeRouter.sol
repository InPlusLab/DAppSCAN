// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.2;

import {VaultAPI, BaseWrapperImplementation, RegistryAPI} from "./wrapper/beacon/BaseWrapperImplementation.sol";
import {ApeVaultFactoryBeacon} from "./wrapper/beacon/ApeVaultFactory.sol";
import {ApeVaultWrapperImplementation} from "./wrapper/beacon/ApeVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./TimeLock.sol";

contract ApeRouter is TimeLock {
	using SafeERC20 for IERC20;


	uint256 constant MAX_UINT = type(uint256).max;

	address public yearnRegistry;
	address public apeVaultFactory;

	constructor(address _reg, address _factory, uint256 _minDelay) TimeLock(_minDelay)  {
		yearnRegistry = _reg;
		apeVaultFactory = _factory;
	}

	event DepositInVault(address indexed vault, address token, uint256 amount);
	event WithdrawFromVault(address indexed vault, address token, uint256 amount);


	function delegateDepositYvTokens(address _apeVault, address _yvToken, address _token, uint256 _amount) external returns(uint256 deposited) {
		VaultAPI vault = VaultAPI(RegistryAPI(yearnRegistry).latestVault(_token));
		require(address(vault) != address(0), "ApeRouter: No vault for token");
		require(address(vault) == _yvToken, "ApeRouter: yvTokens don't match");
		require(ApeVaultFactoryBeacon(apeVaultFactory).vaultRegistry(_apeVault), "ApeRouter: Vault does not exist");
		require(address(vault) == address(ApeVaultWrapperImplementation(_apeVault).vault()), "ApeRouter: yearn Vault not identical");

		IERC20(_yvToken).safeTransferFrom(msg.sender, _apeVault, _amount);
		deposited = vault.pricePerShare() * _amount / (10**uint256(vault.decimals()));
		ApeVaultWrapperImplementation(_apeVault).addFunds(deposited);
		emit DepositInVault(_apeVault, _token, _amount);

	}

	function delegateDeposit(address _apeVault, address _token, uint256 _amount) external returns(uint256 deposited) {
		VaultAPI vault = VaultAPI(RegistryAPI(yearnRegistry).latestVault(_token));
		require(address(vault) != address(0), "ApeRouter: No vault for token");
		require(ApeVaultFactoryBeacon(apeVaultFactory).vaultRegistry(_apeVault), "ApeRouter: Vault does not exist");
		require(address(vault) == address(ApeVaultWrapperImplementation(_apeVault).vault()), "ApeRouter: yearn Vault not identical");

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

		if (IERC20(_token).allowance(address(this), address(vault)) < _amount) {
            IERC20(_token).safeApprove(address(vault), 0); // Avoid issues with some IERC20(_token)s requiring 0
            IERC20(_token).safeApprove(address(vault), MAX_UINT); // Vaults are trusted
        }

		uint256 beforeBal = IERC20(_token).balanceOf(address(this));
        
		uint256 sharesMinted = vault.deposit(_amount, _apeVault);

        uint256 afterBal = IERC20(_token).balanceOf(address(this));
        deposited = beforeBal - afterBal;


		ApeVaultWrapperImplementation(_apeVault).addFunds(deposited);
		emit DepositInVault(_apeVault, _token, sharesMinted);
	}

	function delegateWithdrawal(address _recipient, address _apeVault, address _token, uint256 _shareAmount, bool _underlying) external{
		VaultAPI vault = VaultAPI(RegistryAPI(yearnRegistry).latestVault(_token));
		require(address(vault) != address(0), "ApeRouter: No vault for token");
		require(ApeVaultFactoryBeacon(apeVaultFactory).vaultRegistry(msg.sender), "ApeRouter: Vault does not exist");
		require(address(vault) == address(ApeVaultWrapperImplementation(_apeVault).vault()), "ApeRouter: yearn Vault not identical");

		if (_underlying)
			vault.withdraw(_shareAmount, _recipient);
		else
			vault.transfer(_recipient, _shareAmount);
		emit WithdrawFromVault(address(vault), vault.token(), _shareAmount);
	}

	function removeTokens(address _token) external onlyOwner {
		IERC20(_token).transfer(msg.sender, IERC20(_token).balanceOf(address(this)));
	}

	 /**
     * @notice
     *  Used to update the yearn registry.
     * @param _registry The new _registry address.
     */
    function setRegistry(address _registry) external itself {
        yearnRegistry = _registry;
    }
}