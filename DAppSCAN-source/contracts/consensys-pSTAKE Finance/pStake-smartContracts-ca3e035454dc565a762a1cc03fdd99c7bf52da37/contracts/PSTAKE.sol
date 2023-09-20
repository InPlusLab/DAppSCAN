// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./interfaces/IPSTAKE.sol";

contract PSTAKE is
	IPSTAKE,
	ERC20Upgradeable,
	PausableUpgradeable,
	AccessControlUpgradeable
{
	// constants defining access control ROLES
	bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

	// variables capturing data of other contracts in the product
	address public _stakeLPCoreContract;

	/**
	 * @dev Constructor for initializing the UToken contract.
	 * @param pauserAddress - address of the pauser admin.
	 */
	function initialize(address pauserAddress) public virtual initializer {
		__ERC20_init("pSTAKE Token", "PSTAKE");
		__AccessControl_init();
		__Pausable_init();
		_setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
		_setupRole(PAUSER_ROLE, pauserAddress);
		// PSTAKE IS A SIMPLE ERC20 TOKEN HENCE 18 DECIMAL PLACES
		_setupDecimals(18);
		// pre-allocate some tokens to an admin address which will air drop PSTAKE tokens
		// to each of holder contracts. This is only for testnet purpose. in Mainnet, we
		// will use a vesting contract to allocate tokens to admin in a certain schedule
		_mint(_msgSender(), 5000000000000000000000000);
	}

	/**
	 * @dev Mint new PSTAKE for the provided 'address' and 'amount'
	 *
	 *
	 * Emits a {MintTokens} event with 'to' set to address and 'tokens' set to amount of tokens.
	 *
	 * Requirements:
	 *
	 * - `amount` cannot be less than zero.
	 *
	 */
	/* function mint(address to, uint256 tokens) public virtual override returns (bool success) {
        require(_msgSender() == _stakeLPCoreContract, "PS1");  // minted by STokens contract

        _mint(to, tokens);
        return true;
    } */

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
	/* function burn(address from, uint256 tokens) public virtual override returns (bool success) {
        require((tx.origin == from && _msgSender()==_liquidStakingContract) ||  // staking operation
        (tx.origin == from && _msgSender() == _wrapperContract), "UT2"); // unwrap operation
        _burn(from, tokens);
        return true;
    } */

	/*
	 * @dev Set 'contract address', for liquid staking smart contract
	 * @param liquidStakingContract: liquidStaking contract address
	 *
	 * Emits a {SetLiquidStakingContract} event with '_contract' set to the liquidStaking contract address.
	 *
	 */
	function setStakeLPCoreContract(address stakeLPCoreContract)
		public
		virtual
		override
	{
		require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "PS2");
		_stakeLPCoreContract = stakeLPCoreContract;
		emit SetStakeLPCoreContract(stakeLPCoreContract);
	}

	/**
	 * @dev Triggers stopped state.
	 *
	 * Requirements:
	 *
	 * - The contract must not be paused.
	 */
	function pause() public virtual returns (bool success) {
		require(hasRole(PAUSER_ROLE, _msgSender()), "PS3");
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
		require(hasRole(PAUSER_ROLE, _msgSender()), "PS4");
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
		require(!paused(), "PS5");
		super._beforeTokenTransfer(from, to, amount);
	}
}
