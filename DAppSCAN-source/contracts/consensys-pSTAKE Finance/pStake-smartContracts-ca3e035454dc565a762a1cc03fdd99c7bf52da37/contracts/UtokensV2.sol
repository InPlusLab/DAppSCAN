// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./interfaces/IUTokens.sol";

contract UTokensV2 is
	ERC20Upgradeable,
	IUTokens,
	PausableUpgradeable,
	AccessControlUpgradeable
{
	// constants defining access control ROLES
	bytes32 public constant BRIDGE_ADMIN_ROLE = keccak256("BRIDGE_ADMIN_ROLE");
	bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

	// variables capturing data of other contracts in the product
	address public _stokenContract;
	address public _liquidStakingContract;
	address public _wrapperContract;

	/**
	 * @dev Constructor for initializing the UToken contract.
	 * @param bridgeAdminAddress - address of the bridge admin.
	 * @param pauserAddress - address of the pauser admin.
	 */
	function initialize(address bridgeAdminAddress, address pauserAddress)
		public
		virtual
		initializer
	{
		__ERC20_init("pSTAKE Pegged ATOM", "pATOM");
		__AccessControl_init();
		__Pausable_init();
		_setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
		_setupRole(BRIDGE_ADMIN_ROLE, bridgeAdminAddress);
		_setupRole(PAUSER_ROLE, pauserAddress);
		_setupDecimals(6);
	}

	/**
	 * @dev Mint new utokens for the provided 'address' and 'amount'
	 * @param to: account address, tokens: number of tokens
	 *
	 * Emits a {MintTokens} event with 'to' set to address and 'tokens' set to amount of tokens.
	 *
	 * Requirements:
	 *
	 * - `amount` cannot be less than zero.
	 *
	 */
	function mint(address to, uint256 tokens)
		public
		virtual
		override
		returns (bool success)
	{
		require(
			(hasRole(BRIDGE_ADMIN_ROLE, tx.origin) &&
				_msgSender() == _wrapperContract) || // minted by bridge
				_msgSender() == _stokenContract || // minted by STokens contract during reward generation
				_msgSender() == _liquidStakingContract,
			"UT1"
		); // minted by LS contract withdrawUnstakedTokens()

		_mint(to, tokens);
		return true;
	}

	/*
	 * @dev Burn utokens for the provided 'address' and 'amount'
	 * @param from: account address, tokens: number of tokens
	 *
	 * Emits a {BurnTokens} event with 'from' set to address and 'tokens' set to amount of tokens.
	 *
	 * Requirements:
	 *
	 * - `amount` cannot be less than zero.
	 *
	 */
	function burn(address from, uint256 tokens)
		public
		virtual
		override
		returns (bool success)
	{
		require(
			_msgSender() == _liquidStakingContract || // staking operation
				_msgSender() == _wrapperContract,
			"UT2"
		); // unwrap operation

		_burn(from, tokens);
		return true;
	}

	/*
	 * @dev Set 'contract address', called for stokens smart contract
	 * @param stokenContract: stoken contract address
	 *
	 * Emits a {SetSTokensContract} event with '_contract' set to the stoken contract address.
	 *
	 */
	//These functions need to be called after deployment, only admin can call the same
	function setSTokenContract(address stokenContract) public virtual override {
		require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "UT3");
		_stokenContract = stokenContract;
		emit SetSTokensContract(stokenContract);
	}

	/*
	 * @dev Set 'contract address', for liquid staking smart contract
	 * @param liquidStakingContract: liquidStaking contract address
	 *
	 * Emits a {SetLiquidStakingContract} event with '_contract' set to the liquidStaking contract address.
	 *
	 */
	function setLiquidStakingContract(address liquidStakingContract)
		public
		virtual
		override
	{
		require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "UT4");
		_liquidStakingContract = liquidStakingContract;
		emit SetLiquidStakingContract(liquidStakingContract);
	}

	/*
	 * @dev Set 'contract address', called for token wrapper smart contract
	 * @param wrapperTokensContract: tokenWrapper contract address
	 *
	 * Emits a {SetWrapperContract} event with '_contract' set to the tokenWrapper contract address.
	 *
	 */
	function setWrapperContract(address wrapperTokensContract)
		public
		virtual
		override
	{
		require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "UT5");
		_wrapperContract = wrapperTokensContract;
		emit SetWrapperContract(wrapperTokensContract);
	}

	/**
	 * @dev Triggers stopped state.
	 *
	 * Requirements:
	 *
	 * - The contract must not be paused.
	 */
	function pause() public virtual returns (bool success) {
		require(hasRole(PAUSER_ROLE, _msgSender()), "UT6");
		_pause();
		return true;
	}

	/**
	 * @dev Returns to normal state.
	 *
	 * Requirements:
	 *
	 * - The contract must be paused.
	 */
	function unpause() public virtual returns (bool success) {
		require(hasRole(PAUSER_ROLE, _msgSender()), "UT7");
		_unpause();
		return true;
	}

	/**
	 * @dev Hook that is called before any transfer of tokens. This includes
	 * minting and burning.
	 *
	 * Calling conditions:
	 *
	 * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
	 * will be to transferred to `to`.
	 * - when `from` is zero, `amount` tokens will be minted for `to`.
	 * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
	 * - `from` and `to` are never both zero.
	 *
	 */
	function _beforeTokenTransfer(
		address from,
		address to,
		uint256 amount
	) internal virtual override {
		require(!paused(), "UT8");
		super._beforeTokenTransfer(from, to, amount);
	}
}
