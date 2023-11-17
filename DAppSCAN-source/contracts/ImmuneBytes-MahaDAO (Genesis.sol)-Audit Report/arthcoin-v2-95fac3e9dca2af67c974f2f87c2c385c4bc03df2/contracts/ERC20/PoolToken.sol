// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {ERC20} from './ERC20.sol';
import {IERC20} from './IERC20.sol';
import {Math} from '../utils/math/Math.sol';
import {SafeMath} from '../utils/math/SafeMath.sol';
import {AccessControl} from '../access/AccessControl.sol';

/**
 * @title  PoolToken
 * @author MahaDAO.
 */
contract PoolToken is AccessControl, ERC20 {
    using SafeMath for uint256;

    /**
     * State variables.
     */

    IERC20[] public poolTokens;
    bool public enableWithdrawals = false;
    bytes32 public constant GOVERNANCE_ROLE = keccak256('GOVERNANCE_ROLE');

    /**
     * Event.
     */
    event ToggleWithdrawals(bool state);
    event TokenAdded(address indexed token);
    event Withdraw(address indexed who, uint256 amount);
    event TokenReplaced(address indexed token, uint256 index);
    event TokensRetrieved(address indexed token, address who, uint256 amount);

    /**
     * Modifier.
     */

    modifier onlyAdmin {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()));
        _;
    }

    modifier onlyGovernance() {
        require(hasRole(GOVERNANCE_ROLE, msg.sender));
        _;
    }

    /**
     * Constructor.
     */
    constructor(
        string memory tokenName,
        string memory tokenSymbol,
        IERC20[] memory poolTokens_
    ) ERC20(tokenName, tokenSymbol) {
        poolTokens = poolTokens_;

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(GOVERNANCE_ROLE, _msgSender());
    }

    /**
     * External.
     */

    function addPoolToken(IERC20 token) external onlyGovernance {
        poolTokens.push(token);
        emit TokenAdded(address(token));
    }

    function replacePoolToken(uint256 index, IERC20 token)
        external
        onlyGovernance
    {
        poolTokens[index] = token;
        emit TokenReplaced(address(token), index);
    }

    function mint(address to, uint256 amount) external onlyGovernance {
        _mint(to, amount);
    }

    function withdraw(uint256 amount) external {
        require(enableWithdrawals, 'PoolToken: withdrawals disabled');
        require(amount > 0, 'PoolToken: amount = 0');
        require(amount <= balanceOf(msg.sender), 'PoolToken: amount > balance');

        // calculate how much share of the supply the user has
        uint256 percentage = amount.mul(1e8).div(totalSupply());

        // proportionately send each of the pool tokens to the user
        for (uint256 i = 0; i < poolTokens.length; i++) {
            if (address(poolTokens[i]) == address(0)) continue;
            uint256 balance = poolTokens[i].balanceOf(address(this));
            uint256 shareAmount = balance.mul(percentage).div(1e8);
            if (shareAmount > 0)
                poolTokens[i].transfer(msg.sender, shareAmount);
        }

        _burn(msg.sender, amount);
        emit Withdraw(msg.sender, amount);
    }

    function toggleWithdrawals() external onlyAdmin {
        enableWithdrawals = !enableWithdrawals;
        emit ToggleWithdrawals(enableWithdrawals);
    }

    function retrieveTokens(IERC20 token) external onlyAdmin {
        uint256 balance = token.balanceOf(address(this));
        token.transfer(msg.sender, balance);
        emit TokensRetrieved(address(token), msg.sender, balance);
    }
}
