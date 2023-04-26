// SPDX-FileCopyrightText: 2021 Tenderize <info@tenderize.me>

// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../libs/MathUtils.sol";
import "../tenderizer/ITotalStakedReader.sol";
import "./ITenderToken.sol";
// solhint-disable-next-line max-line-length
import { ERC20Upgradeable, ERC20PermitUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";

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
contract TenderToken is OwnableUpgradeable, ERC20PermitUpgradeable, ITenderToken {
    uint8 internal constant DECIMALS = 18;

    /**
     * @dev Total amount of outstanding shares
     */
    uint256 private totalShares;

    /**
     * @dev Nominal amount of shares held by each account
     */
    mapping(address => uint256) private shares;

    /**
     * @dev Allowances nominated in tokens, not token shares.
     */
    mapping(address => mapping(address => uint256)) private allowances;

    /**
     * @dev Tenderizer address, to read total staked tokens
     */
    ITotalStakedReader public totalStakedReader;

    /// @inheritdoc ITenderToken
    function initialize(
        string memory _name,
        string memory _symbol,
        ITotalStakedReader _totalStakedReader
    ) external override initializer returns (bool) {
        __Context_init_unchained();
        __Ownable_init_unchained();
        __ERC20_init_unchained(string(abi.encodePacked("tender ", _name)), string(abi.encodePacked("t", _symbol)));
        __EIP712_init_unchained(string(abi.encodePacked("tender ", _name)), "1");
        __ERC20Permit_init_unchained(string(abi.encodePacked("tender ", _name)));
        totalStakedReader = _totalStakedReader;
        return true;
    }

    /// @inheritdoc ITenderToken
    function decimals() public pure override(ITenderToken, ERC20Upgradeable) returns (uint8) {
        return DECIMALS;
    }

    /// @inheritdoc ITenderToken
    function totalSupply() public view override(ITenderToken, ERC20Upgradeable) returns (uint256) {
        return _getTotalPooledTokens();
    }

    /// @inheritdoc ITenderToken
    function getTotalPooledTokens() public view override returns (uint256) {
        return _getTotalPooledTokens();
    }

    /// @inheritdoc ITenderToken
    function getTotalShares() public view override returns (uint256) {
        return _getTotalShares();
    }

    /// @inheritdoc ITenderToken
    function balanceOf(address _account) public view override(ITenderToken, ERC20Upgradeable) returns (uint256) {
        return _sharesToTokens(_sharesOf(_account));
    }

    /// @inheritdoc ITenderToken
    function sharesOf(address _account) public view override returns (uint256) {
        return _sharesOf(_account);
    }

    /// @inheritdoc ITenderToken
    function allowance(address _owner, address _spender)
        public
        view
        override(ITenderToken, ERC20Upgradeable)
        returns (uint256)
    {
        return allowances[_owner][_spender];
    }

    /// @inheritdoc ITenderToken
    function tokensToShares(uint256 _tokens) public view override returns (uint256) {
        return _tokensToShares(_tokens);
    }

    /// @inheritdoc ITenderToken
    function sharesToTokens(uint256 _shares) public view override returns (uint256) {
        return _sharesToTokens(_shares);
    }

    /// @inheritdoc ITenderToken
    function transfer(address _recipient, uint256 _amount)
        public
        override(ITenderToken, ERC20Upgradeable)
        returns (bool)
    {
        _transfer(msg.sender, _recipient, _amount);
        return true;
    }

    /// @inheritdoc ITenderToken
    function approve(address _spender, uint256 _amount) public override(ITenderToken, ERC20Upgradeable) returns (bool) {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    /// @inheritdoc ITenderToken
    function transferFrom(
        address _sender,
        address _recipient,
        uint256 _amount
    ) public override(ITenderToken, ERC20Upgradeable) returns (bool) {
        uint256 currentAllowance = allowances[_sender][msg.sender];
        require(currentAllowance >= _amount, "TRANSFER_AMOUNT_EXCEEDS_ALLOWANCE");

        _transfer(_sender, _recipient, _amount);
        _approve(_sender, msg.sender, currentAllowance - _amount);
        return true;
    }

    /// @inheritdoc ITenderToken
    function increaseAllowance(address _spender, uint256 _addedValue)
        public
        override(ITenderToken, ERC20Upgradeable)
        returns (bool)
    {
        _approve(msg.sender, _spender, allowances[msg.sender][_spender] + _addedValue);
        return true;
    }

    /// @inheritdoc ITenderToken
    function decreaseAllowance(address _spender, uint256 _subtractedValue)
        public
        override(ITenderToken, ERC20Upgradeable)
        returns (bool)
    {
        uint256 currentAllowance = allowances[msg.sender][_spender];
        require(currentAllowance >= _subtractedValue, "DECREASED_ALLOWANCE_BELOW_ZERO");
        _approve(msg.sender, _spender, currentAllowance - _subtractedValue);
        return true;
    }

    /// @inheritdoc ITenderToken
    function mint(address _recipient, uint256 _amount) public override onlyOwner returns (bool) {
        _mintShares(_recipient, _tokensToShares(_amount));
        return true;
    }

    /// @inheritdoc ITenderToken
    function burn(address _account, uint256 _amount) public override onlyOwner returns (bool) {
        uint256 _sharesToburn = _tokensToShares(_amount);
        _burnShares(_account, _sharesToburn);
        return true;
    }

    /// @inheritdoc ITenderToken
    function setTotalStakedReader(ITotalStakedReader _totalStakedReader) public override onlyOwner {
        require(address(_totalStakedReader) != address(0));
        totalStakedReader = _totalStakedReader;
    }

    // INTERNAL FUNCTIONS

    /**
     * @return the total amount (in 10e18) of Tokens controlled by the protocol.
     * @dev This is used for calculating tokens from shares and vice versa.
     * @dev This function is required to be implemented in a derived contract.
     */
    function _getTotalPooledTokens() internal view returns (uint256) {
        return totalStakedReader.totalStakedTokens();
    }

    /**
     * @dev Moves `_amount` tokens from `_sender` to `_recipient`.
     * @dev Emits a `Transfer` event.
     */
    function _transfer(
        address _sender,
        address _recipient,
        uint256 _amount
    ) internal override {
        uint256 _sharesToTransfer = _tokensToShares(_amount);
        _transferShares(_sender, _recipient, _sharesToTransfer);
        emit Transfer(_sender, _recipient, _amount);
    }

    /**
     * @dev Sets `_amount` as the allowance of `_spender` over the `_owner` s tokens.
     * @dev Emits an `Approval` event.
     */
    function _approve(
        address _owner,
        address _spender,
        uint256 _amount
    ) internal override {
        require(_owner != address(0), "APPROVE_FROM_ZERO_ADDRESS");
        require(_spender != address(0), "APPROVE_TO_ZERO_ADDRESS");

        allowances[_owner][_spender] = _amount;
        emit Approval(_owner, _spender, _amount);
    }

    /**
     * @dev the total amount of shares in existence.
     */
    function _getTotalShares() internal view returns (uint256) {
        return totalShares;
    }

    /**
     * @dev the amount of shares owned by `_account`.
     */
    function _sharesOf(address _account) internal view returns (uint256) {
        return shares[_account];
    }

    /**
     * @dev Moves `_shares` shares from `_sender` to `_recipient`.
     * @dev Requirements:
     * - `_sender` cannot be the zero address.
     * - `_recipient` cannot be the zero address.
     * - `_sender` must hold at least `_shares` shares.
     */
    function _transferShares(
        address _sender,
        address _recipient,
        uint256 _shares
    ) internal {
        require(_sender != address(0), "TRANSFER_FROM_THE_ZERO_ADDRESS");
        require(_recipient != address(0), "TRANSFER_TO_THE_ZERO_ADDRESS");

        uint256 currentSenderShares = shares[_sender];
        require(_shares <= currentSenderShares, "TRANSFER_AMOUNT_EXCEEDS_BALANCE");

        shares[_sender] = currentSenderShares - _shares;
        shares[_recipient] += _shares;
    }

    /**
     * @dev Creates `_shares` shares and assigns them to `_recipient`, increasing the total amount of shares.
     * @dev This doesn't increase the token total supply.
     * @dev Requirements:
     * - `_recipient` cannot be the zero address.
     */
    function _mintShares(address _recipient, uint256 _shares) internal returns (uint256 newTotalShares) {
        require(_recipient != address(0), "MINT_TO_THE_ZERO_ADDRESS");

        newTotalShares = totalShares + _shares;

        shares[_recipient] += _shares;

        // Notice: we're not emitting a Transfer event from the zero address here since shares mint
        // works by taking the amount of tokens corresponding to the minted shares from all other
        // token holders, proportionally to their share. The total supply of the token doesn't change
        // as the result. This is equivalent to performing a send from each other token holder's
        // address to `address`, but we cannot reflect this as it would require sending an unbounded
        // number of events.
        totalShares = newTotalShares;
    }

    /**
     * @dev Destroys `_shares` shares from `_account`'s holdings, decreasing the total amount of shares.
     * @dev This doesn't decrease the token total supply.
     * @dev Requirements:
     * - `_account` cannot be the zero address.
     * - `_account` must hold at least `_shares` shares.
     */
    function _burnShares(address _account, uint256 _shares) internal returns (uint256 newTotalShares) {
        require(_account != address(0), "BURN_FROM_THE_ZERO_ADDRESS");

        uint256 accountShares = shares[_account];
        require(_shares <= accountShares, "BURN_AMOUNT_EXCEEDS_BALANCE");

        newTotalShares = totalShares - _shares;

        shares[_account] = accountShares - _shares;

        // Notice: we're not emitting a Transfer event to the zero address here since shares burn
        // works by redistributing the amount of tokens corresponding to the burned shares between
        // all other token holders. The total supply of the token doesn't change as the result.
        // This is equivalent to performing a send from `address` to each other token holder address,
        // but we cannot reflect this as it would require sending an unbounded number of events.
        totalShares = newTotalShares;
    }

    function _tokensToShares(uint256 _tokens) internal view returns (uint256) {
        uint256 _totalPooledTokens = _getTotalPooledTokens();
        uint256 _totalShares = _getTotalShares();
        if (_totalShares == 0) {
            return _tokens;
        } else if (_totalPooledTokens == 0) {
            return 0;
        } else {
            return MathUtils.percOf(_tokens, _totalShares, _totalPooledTokens);
        }
    }

    function _sharesToTokens(uint256 _shares) internal view returns (uint256) {
        uint256 _totalShares = _getTotalShares();
        if (_totalShares == 0) {
            return 0;
        } else {
            return MathUtils.percOf(_shares, _getTotalPooledTokens(), _totalShares);
        }
    }
}
