// SPDX-FileCopyrightText: 2021 Tenderize <info@tenderize.me>

// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "../tenderizer/ITotalStakedReader.sol";

/**
 * @title Interest-bearing ERC20-like token for Tenderize protocol.
 * @author Tenderize <info@tenderize.me>
 * @dev TenderToken balances are dynamic and are calculated based on the accounts' shares
 * and the total amount of Tokens controlled by the protocol. Account shares aren't
 * normalized, so the contract also stores the sum of all shares to calculate
 * each account's token balance which equals to:
 *
 * shares[account] * _getTotalPooledTokens() / _getTotalShares()
 */
interface ITenderToken {
    /**
     * @notice Initilize the TenderToken Contract
     * @param _name name of the token (steak)
     * @param _symbol symbol of the token (steak)
     * @param _stakedReader contract address implementing the ITotalStakedReader interface
     * @return a boolean value indicating whether the init succeeded.
     */
    function initialize(
        string memory _name,
        string memory _symbol,
        ITotalStakedReader _stakedReader
    ) external returns (bool);

    /**
     * @notice The number of decimals the TenderToken uses.
     * @return decimals the number of decimals for getting user representation of a token amount.
     */
    function decimals() external pure returns (uint8);

    /**
     * @notice The total supply of tender tokens in existence.
     * @dev Always equals to `_getTotalPooledTokens()` since token amount
     * is pegged to the total amount of Tokens controlled by the protocol.
     * @return totalSupply total supply
     */
    function totalSupply() external view returns (uint256);

    /**
     * @notice Total amount of underlying tokens controlled by the Tenderizer.
     * @dev The sum of all Tokens balances in the protocol, equals to the total supply of TenderToken.
     * @return totalPooledTokens total amount of pooled tokens
     */
    function getTotalPooledTokens() external view returns (uint256);

    /**
     * @notice The total amount of shares in existence.
     * @dev The sum of all accounts' shares can be an arbitrary number, therefore
     * it is necessary to store it in order to calculate each account's relative share.
     * @return totalShares total amount of shares
     */
    function getTotalShares() external view returns (uint256);

    /**
     * @notice the amount of tokens owned by the `_account`.
     * @dev Balances are dynamic and equal the `_account`'s share in the amount of the
        total Tokens controlled by the protocol. See `sharesOf`.
     * @param _account address of the account to check the balance for
     * @return balance token balance of `_account`
     */
    function balanceOf(address _account) external view returns (uint256);

    /**
     * @notice The amount of shares owned by an account
     * @param _account address of the account
     * @return shares the amount of shares owned by `_account`.
     */
    function sharesOf(address _account) external view returns (uint256);

    /**
     * @notice The remaining number of tokens that `_spender` is allowed to spend
     * behalf of `_owner` through `transferFrom`. This is zero by default.
     * @dev This value changes when `approve` or `transferFrom` is called.
     * @param _owner address that approved the allowance
     * @param _spender address that is allowed to spend the allowance
     * @return allowance amount '_spender' is allowed to spend from '_owner'
     */
    function allowance(address _owner, address _spender) external view returns (uint256);

    /**
     * @notice The amount of shares that corresponds to `_tokens` protocol-controlled Tokens.
     * @param _tokens amount of tokens to calculate shares for
     * @return shares nominal amount of shares the tokens represent
     */
    function tokensToShares(uint256 _tokens) external view returns (uint256);

    /**
     * @notice The amount of tokens that corresponds to `_shares` token shares.
     * @param _shares the amount of shares to calculate the amount of tokens for
     * @return tokens the amount of tokens represented by the shares
     */
    function sharesToTokens(uint256 _shares) external view returns (uint256);

    /**
     * @notice Transfers `_amount` tokens from the caller's account to the `_recipient` account.
     * @param _recipient address of the recipient
     * @param _amount amount of tokens to transfer
     * @return success a boolean value indicating whether the operation succeeded.
     * @dev Emits a `Transfer` event.
     * @dev Requirements:
     * - `_recipient` cannot be the zero address.
     * - the caller must have a balance of at least `_amount`.
     * @dev The `_amount` argument is the amount of tokens, not shares.
     */
    function transfer(address _recipient, uint256 _amount) external returns (bool);

    /**
     * @notice Sets `_amount` as the allowance of `_spender` over the caller's tokens.
     * @param _spender address of the spender allowed to approve tokens from caller
     * @param _amount amount of tokens to allow '_spender' to spend
     * @return success a boolean value indicating whether the operation succeeded.
     * @dev Emits an `Approval` event.
     * @dev Requirements:
     * - `_spender` cannot be the zero address.
     * @dev The `_amount` argument is the amount of tokens, not shares.
     */
    function approve(address _spender, uint256 _amount) external returns (bool);

    /**
     * @notice Transfers `_amount` tokens from `_sender` to `_recipient` using the
     * allowance mechanism. `_amount` is then deducted from the caller's allowance.
     * @param _sender address of the account to transfer tokens from
     * @param _recipient address of the recipient
     * @return success a boolean value indicating whether the operation succeeded.
     * @dev Emits a `Transfer` event.
     * @dev Emits an `Approval` event indicating the updated allowance.
     * @dev Requirements:
     * - `_sender` and `_recipient` cannot be the zero addresses.
     * - `_sender` must have a balance of at least `_amount`.
     * - the caller must have allowance for `_sender`'s tokens of at least `_amount`.
     * @dev The `_amount` argument is the amount of tokens, not shares.
     */
    function transferFrom(
        address _sender,
        address _recipient,
        uint256 _amount
    ) external returns (bool);

    /**
     * @notice Atomically increases the allowance granted to `_spender` by the caller by `_addedValue`.
     * @param _spender address of the spender allowed to approve tokens from caller
     * @param _addedValue amount to add to allowance
     * @return success a boolean value indicating whether the operation succeeded.
     * @dev This is an alternative to `approve` that can be used as a mitigation for problems described in:
     * https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol#L42
     * @dev Emits an `Approval` event indicating the updated allowance.
     * @dev Requirements:
     * - `_spender` cannot be the the zero address.
     */
    function increaseAllowance(address _spender, uint256 _addedValue) external returns (bool);

    /**
     * @notice Atomically decreases the allowance granted to `_spender` by the caller by `_subtractedValue`.
     * @param _spender address of the spender allowed to approve tokens from caller
     * @param _subtractedValue amount to subtract from current allowance
     * @return success a boolean value indicating whether the operation succeeded.
     * @dev This is an alternative to `approve` that can be used as a mitigation for problems described in:
     * https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol#L42
     * @dev Emits an `Approval` event indicating the updated allowance.
     * @dev Requirements:
     * - `_spender` cannot be the zero address.
     * - `_spender` must have allowance for the caller of at least `_subtractedValue`.
     */
    function decreaseAllowance(address _spender, uint256 _subtractedValue) external returns (bool);

    /**
     * @notice Mints '_amount' of tokens for '_recipient'
     * @param _recipient address to mint tokens for
     * @param _amount amount to mint
     * @return success a boolean value indicating whether the operation succeeded.
     * @dev Only callable by contract owner
     * @dev Calculates the amount of shares to create based on the specified '_amount'
     * and creates new shares rather than minting actual tokens
     * @dev '_recipient' should also deposit into Tenderizer
     * atomically to prevent diluation of existing particpants
     */
    function mint(address _recipient, uint256 _amount) external returns (bool);

    /**
     * @notice Burns '_amount' of tokens from '_recipient'
     * @param _account address to burn the tokens from
     * @param _amount amount to burn
     * @return success a boolean value indicating whether the operation succeeded.
     * @dev Only callable by contract owner
     * @dev Calculates the amount of shares to destroy based on the specified '_amount'
     * and destroy shares rather than burning tokens
     * @dev '_recipient' should also withdraw from Tenderizer atomically
     */
    function burn(address _account, uint256 _amount) external returns (bool);

    /**
     * @notice sets a TotalStakedReader to read the total staked tokens from
     * @param _stakedReader contract address implementing the ITotalStakedReader interface
     * @dev Only callable by contract owner.
     * @dev Used to determine TenderToken total supply.
     */
    function setTotalStakedReader(ITotalStakedReader _stakedReader) external;
}
