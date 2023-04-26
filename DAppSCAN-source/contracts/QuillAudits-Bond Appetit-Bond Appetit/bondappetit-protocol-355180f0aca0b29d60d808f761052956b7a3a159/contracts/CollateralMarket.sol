// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "./utils/OwnablePausable.sol";
import "./Issuer.sol";
import "./Treasury.sol";

contract CollateralMarket is OwnablePausable {
    using SafeMath for uint256;
    using SafeERC20 for ERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Address of issuer contract.
    Issuer public issuer;

    /// @notice Address of treasury contract.
    Treasury public treasury;

    /// @notice Address of depositary contract.
    address public depositary;

    /// @dev Allowed tokens list.
    EnumerableSet.AddressSet private _allowedTokens;

    /// @notice An event emitted when token allowed.
    event TokenAllowed(address token);

    /// @notice An event emitted when token denied.
    event TokenDenied(address token);

    /// @notice An event thats emitted when an Issuer contract address changed.
    event IssuerChanged(address newIssuer);

    /// @notice An event thats emitted when an Treasury contract address changed.
    event TreasuryChanged(address newTreasury);

    /// @notice An event thats emitted when an Depositary contract address changed.
    event DepositaryChanged(address newDepositary);

    /// @notice An event thats emitted when an account buyed token.
    event Buy(address customer, address token, uint256 amount, uint256 buy);

    constructor(
        address _issuer,
        address payable _treasury,
        address _depositary
    ) public {
        issuer = Issuer(_issuer);
        treasury = Treasury(_treasury);
        depositary = _depositary;
    }

    /**
     * @notice Allow token.
     * @param token Allowable token.
     */
    function allowToken(address token) external onlyOwner {
        _allowedTokens.add(token);
        emit TokenAllowed(token);
    }

    /**
     * @notice Deny token.
     * @param token Denied token.
     */
    function denyToken(address token) external onlyOwner {
        _allowedTokens.remove(token);
        emit TokenDenied(token);
    }

    /**
     * @return Allowed tokens list.
     */
    function allowedTokens() external view returns (address[] memory) {
        address[] memory result = new address[](_allowedTokens.length());

        for (uint256 i = 0; i < _allowedTokens.length(); i++) {
            result[i] = _allowedTokens.at(i);
        }

        return result;
    }

    /**
     * @notice Change Issuer contract address.
     * @param _issuer New address Issuer contract.
     */
    function changeIssuer(address _issuer) external onlyOwner {
        issuer = Issuer(_issuer);
        emit IssuerChanged(_issuer);
    }

    /**
     * @notice Change Treasury contract address.
     * @param _treasury New address Treasury contract.
     */
    function changeTreasury(address payable _treasury) external onlyOwner {
        treasury = Treasury(_treasury);
        emit TreasuryChanged(_treasury);
    }

    /**
     * @notice Change Depositary contract address.
     * @param _depositary New address Depositary contract.
     */
    function changeDepositary(address _depositary) external onlyOwner {
        require(issuer.hasDepositary(_depositary), "CollateralMarket::changeDepositary: collateral depositary is not allowed");
        depositary = _depositary;
        emit DepositaryChanged(depositary);
    }

    /**
     * @notice Buy stable token with ERC20 payment token amount.
     * @param token Payment token.
     * @param amount Amount of payment token.
     */
    function buy(ERC20 token, uint256 amount) external whenNotPaused {
        require(_allowedTokens.contains(address(token)), "CollateralMarket::buy: token is not allowed");
        require(issuer.hasDepositary(depositary), "CollateralMarket::buy: collateral depositary is not allowed");

        token.safeTransferFrom(_msgSender(), address(this), amount);
        token.transfer(depositary, amount);

        ERC20 stableToken = ERC20(issuer.stableToken());
        uint256 stableTokenDecimals = stableToken.decimals();
        uint256 tokenDecimals = token.decimals();
        uint256 reward = amount.mul(10**(stableTokenDecimals.sub(tokenDecimals)));
        issuer.rebalance();
        treasury.transfer(address(stableToken), _msgSender(), reward);

        emit Buy(_msgSender(), address(token), amount, reward);
    }
}
