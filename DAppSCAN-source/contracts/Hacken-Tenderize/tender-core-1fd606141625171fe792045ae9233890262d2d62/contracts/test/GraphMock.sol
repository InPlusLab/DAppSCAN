// SPDX-FileCopyrightText: 2021 Tenderize <info@tenderize.me>

// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./MockStaking.sol";

pragma solidity 0.8.4;

contract GraphMock is MockStaking {
    uint32 constant MAX_PPM = 1000000;

    constructor(IERC20 _token) MockStaking(_token) {}

    // -- Delegation Data --

    /**
     * @dev Delegation pool information. One per indexer.
     */
    struct DelegationPool {
        uint32 cooldownBlocks; // Blocks to wait before updating parameters
        uint32 indexingRewardCut; // in PPM
        uint32 queryFeeCut; // in PPM
        uint256 updatedAtBlock; // Block when the pool was last updated
        uint256 tokens; // Total tokens as pool reserves
        uint256 shares; // Total shares minted in the pool
        // mapping(address => Delegation) delegators; // Mapping of delegator => Delegation
    }

    /**
     * @dev Individual delegation data of a delegator in a pool.
     */
    struct Delegation {
        uint256 shares; // Shares owned by a delegator in the pool
        uint256 tokensLocked; // Tokens locked for undelegation
        uint256 tokensLockedUntil; // Block when locked tokens can be withdrawn
    }

    function delegate(address _indexer, uint256 _tokens) external reverted(this.delegate.selector) returns (uint256) {
        require(token.transferFrom(msg.sender, address(this), _tokens));

        staked += _tokens - ((_tokens * this.delegationTaxPercentage()) / MAX_PPM);
    }

    function undelegate(address _indexer, uint256 _shares)
        external
        reverted(this.undelegate.selector)
        returns (uint256)
    {
        unstakeLocks[nextUnstakeLockID] = UnstakeLock({ amount: _shares, account: msg.sender });
        staked -= _shares;
    }

    function withdrawDelegated(address _indexer, address _newIndexer)
        external
        reverted(this.withdrawDelegated.selector)
        returns (uint256)
    {
        token.transfer(unstakeLocks[nextUnstakeLockID].account, unstakeLocks[nextUnstakeLockID].amount);
    }

    function getDelegation(address _indexer, address _delegator) external view returns (Delegation memory) {
        return Delegation({ shares: staked, tokensLocked: 0, tokensLockedUntil: 0 });
    }

    function delegationPools(address _indexer) external view returns (DelegationPool memory) {
        return
            DelegationPool({
                tokens: staked,
                cooldownBlocks: 0,
                indexingRewardCut: 0,
                queryFeeCut: 0,
                updatedAtBlock: 0,
                shares: staked
            });
    }

    function getWithdraweableDelegatedTokens(Delegation memory _delegation) external view returns (uint256) {}

    function thawingPeriod() external view returns (uint256) {}

    function delegationTaxPercentage() external view returns (uint32) {
        return 5000;
    }
}
