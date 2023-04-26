// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./depositary/AgregateDepositaryBalanceView.sol";
import "./StableToken.sol";

contract Issuer is AgregateDepositaryBalanceView {
    using Math for uint256;
    using SafeMath for uint256;

    /// @notice Stable token contract address.
    StableToken public stableToken;

    /// @notice Treasury contract address.
    address public treasury;

    /// @notice An event thats emitted when an Treasury contract transfered.
    event TransferTreasury(address newTreasury);

    /// @notice An event thats emitted when an stable token total supply rebalanced.
    event Rebalance();

    /**
     * @param _stableToken Stable token contract address.
     * @param _treasury Treasury contract address.
     */
    constructor(address _stableToken, address _treasury) public AgregateDepositaryBalanceView(StableToken(_stableToken).decimals(), 50) {
        stableToken = StableToken(_stableToken);
        treasury = _treasury;
    }

    /**
     * @notice Transfer Treasury contract to new address.
     * @param _treasury New address Treasury contract.
     */
    function changeTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
        emit TransferTreasury(treasury);
    }

    /**
     * @notice Rebalance stable token total supply by depositary balance. Mint stable token if depositary balance greater token total supply and burn otherwise.
     */
    function rebalance() external whenNotPaused {
        uint256 currentDepositaryBalance = this.balance();
        uint256 stableTokenTotalSupply = stableToken.totalSupply();

        if (stableTokenTotalSupply > currentDepositaryBalance) {
            uint256 burningBalance = stableToken.balanceOf(address(this));

            if (burningBalance > 0) {
                stableToken.burn(address(this), burningBalance.min(stableTokenTotalSupply.sub(currentDepositaryBalance)));
                emit Rebalance();
            }
        } else if (stableTokenTotalSupply < currentDepositaryBalance) {
            stableToken.mint(treasury, currentDepositaryBalance.sub(stableTokenTotalSupply));
            emit Rebalance();
        }
    }
}
