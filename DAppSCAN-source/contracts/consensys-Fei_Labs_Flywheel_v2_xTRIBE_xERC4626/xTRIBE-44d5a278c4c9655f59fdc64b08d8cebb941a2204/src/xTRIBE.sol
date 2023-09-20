// SPDX-License-Identifier: MIT
// Voting logic inspired by OpenZeppelin Contracts v4.4.1 (token/ERC20/extensions/ERC20Votes.sol)

pragma solidity ^0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Auth, Authority} from "solmate/auth/Auth.sol";

import {Multicall} from "ERC4626/external/Multicall.sol";
import {xERC4626, ERC4626} from "ERC4626/xERC4626.sol";
import {ERC20MultiVotes} from "flywheel/token/ERC20MultiVotes.sol";
import {ERC20Gauges} from "flywheel/token/ERC20Gauges.sol";

interface ITribe {
    function getPriorVotes(address account, uint256 blockNumber)
        external
        view
        returns (uint96);

    function getCurrentVotes(address account) external view returns (uint96);
}

/**
 @title xTribe: Yield bearing, voting, and gauge enabled TRIBE
 @notice xTribe is an ERC-4626 compliant TRIBE token which:
         * distributes TRIBE rewards to stakers in a manipulation resistant manner.
         * allows on-chain voting with both xTRIBE and TRIBE voting power.
         * includes gauges for reward direction
    
    The xTRIBE owner/authority ONLY control the maximum number and approved overrides of gauges and delegates, as well as the live gauge list.
 */
contract xTRIBE is ERC20MultiVotes, ERC20Gauges, xERC4626, Multicall {
    constructor(
        ERC20 _tribe,
        address _owner,
        Authority _authority,
        uint32 _rewardsCycleLength,
        uint32 _incrementFreezeWindow
    )
        Auth(_owner, _authority)
        xERC4626(_rewardsCycleLength)
        ERC20Gauges(_rewardsCycleLength, _incrementFreezeWindow)
        ERC4626(_tribe, "xTribe: Gov + Yield", "xTRIBE")
    {}

    function tribe() public view returns (ITribe) {
        return ITribe(address(asset));
    }

    /*///////////////////////////////////////////////////////////////
                             VOTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     @notice calculate voting power of xTRIBE AND underlying TRIBE voting power for user, converted to xTRIBE shares.
     @param account the user to calculate voting power of.
     @return the voting power of `account`.
     */
    function getVotes(address account) public view override returns (uint256) {
        return
            super.getVotes(account) +
            convertToShares(tribe().getCurrentVotes(account));
    }

    /**
     @notice calculate past voting power at a given block of xTRIBE AND underlying TRIBE voting power for user, converted to xTRIBE shares.
     @param account the user to calculate voting power of.
     @param blockNumber the block in the past to get voting power from.
     @return the voting power of `account` at block `blockNumber`.
     @dev TRIBE voting power is included converted to xTRIBE shares at the CURRENT conversion rate.
     Because xTRIBE shares should monotonically increase in value relative to TRIBE, this makes TRIBE historical voting power decay.
     */
    function getPastVotes(address account, uint256 blockNumber)
        public
        view
        override
        returns (uint256)
    {
        return
            super.getPastVotes(account, blockNumber) +
            convertToShares(tribe().getPriorVotes(account, blockNumber));
    }

    /**
     @notice an event for manually emitting voting balances.

     This is important because this contract cannot be synchronously notified of Tribe delegations.
     */
    // SWC-105-Unprotected Ether Withdrawal: L90-L100
    function emitVotingBalances(address[] calldata accounts) external {
        uint256 size = accounts.length;

        for (uint256 i = 0; i < size; ) {
            emit DelegateVotesChanged(accounts[i], 0, getVotes(accounts[i]));

            unchecked {
                i++;
            }
        }
    }

    /*///////////////////////////////////////////////////////////////
                             ERC20 LOGIC
    //////////////////////////////////////////////////////////////*/

    function _burn(address from, uint256 amount)
        internal
        virtual
        override(ERC20, ERC20Gauges, ERC20MultiVotes)
    {
        _decrementWeightUntilFree(from, amount);
        _decrementVotesUntilFree(from, amount);
        ERC20._burn(from, amount);
    }

    function transfer(address to, uint256 amount)
        public
        virtual
        override(ERC20, ERC20Gauges, ERC20MultiVotes)
        returns (bool)
    {
        _decrementWeightUntilFree(msg.sender, amount);
        _decrementVotesUntilFree(msg.sender, amount);
        return ERC20.transfer(to, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    )
        public
        virtual
        override(ERC20, ERC20Gauges, ERC20MultiVotes)
        returns (bool)
    {
        _decrementWeightUntilFree(from, amount);
        _decrementVotesUntilFree(from, amount);
        return ERC20.transferFrom(from, to, amount);
    }
}
