//SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interfaces/IApi3Token.sol";
import "./interfaces/IApi3Pool.sol";
import "./interfaces/ITimelockManager.sol";


/// @title Contract that the API3 DAO uses to timelock API3 tokens
/// @notice The owner of TimelockManager (i.e., API3 DAO) can send tokens to
/// TimelockManager to timelock them. These tokens will then be vested to their
/// recipient linearly, starting from releaseStart and ending at releaseEnd of
/// the respective timelock.
/// Alternatively, if the owner of TimelockManager (i.e., API3 DAO) sets the
/// api3Pool address, the token recipients can transfer their locked tokens
/// from TimelockManager to api3Pool. These tokens will remain timelocked
/// (i.e., will not be withdrawable) at api3Pool until they are vested
/// according to their respective schedule.
contract TimelockManager is Ownable, ITimelockManager {
    using SafeMath for uint256;

    /// @dev If an address has permitted the owner of this contract (i.e., the
    /// API3 DAO) to revert (i.e., cancel and withdraw the tokens) their
    /// timelock
    mapping(address => bool) private permittedTimelockToBeReverted;

    struct Timelock {
        uint256 totalAmount;
        uint256 remainingAmount;
        uint256 releaseStart;
        uint256 releaseEnd;
        }

    IApi3Token public immutable api3Token;
    IApi3Pool public api3Pool;
    mapping(address => Timelock) public timelocks;

    /// @dev api3Pool is not initialized in the constructor because this
    /// contract will be deployed before api3Pool
    /// @param api3TokenAddress Address of the API3 token contract
    /// @param timelockManagerOwner Address that will receive the ownership of
    /// the TimelockManager contract (i.e., the API3 DAO)
    constructor(
        address api3TokenAddress,
        address timelockManagerOwner
        )
        public
    {
        api3Token = IApi3Token(api3TokenAddress);
        transferOwnership(timelockManagerOwner);
    }

    /// @notice Called by the owner (i.e., API3 DAO) to set the address of
    /// api3Pool, which token recipients can transfer their tokens to
    /// @param api3PoolAddress Address of the API3 pool contract
    function updateApi3Pool(address api3PoolAddress)
        external
        override
        onlyOwner
    {
        require(
            address(api3Pool) != api3PoolAddress,
            "Input will not update state"
        );
        api3Pool = IApi3Pool(api3PoolAddress);
        emit Api3PoolUpdated(api3PoolAddress);
    }

    /// @notice Called by the owner (i.e., API3 DAO) to revert the timelock of
    /// a recipient, given that they have given permission beforehand
    /// @param recipient Original recipient of tokens
    /// @param destination Destination of the tokens locked by the reverted
    /// timelock
    function revertTimelock(
        address recipient,
        address destination
        )
        external
        override
        onlyOwner
        onlyIfRecipientHasRemainingTokens(recipient)
    {
        require(
            destination != address(0),
            "Invalid destination"
            );
        require(
            permittedTimelockToBeReverted[recipient],
            "Not permitted to revert timelock"
            );
        // Reset permission automatically
        permittedTimelockToBeReverted[recipient] = false;
        uint256 remaining = timelocks[recipient].remainingAmount;
        timelocks[recipient].remainingAmount = 0;
        require(
            api3Token.transfer(destination, remaining),
            "API3 token transfer failed"
            );
        emit RevertedTimelock(recipient, destination, remaining);
    }

    /// @notice Permit the owner (i.e., API3 DAO) to revert the caller's
    /// timelock
    /// @dev To be used when the timelock has been created with incorrect
    /// parameters (for example with releaseEnd at infinity)
    function permitTimelockToBeReverted()
        external
        override
        onlyIfRecipientHasRemainingTokens(msg.sender)
    {
        require(
            !permittedTimelockToBeReverted[msg.sender],
            "Input will not update state"
        );
        permittedTimelockToBeReverted[msg.sender] = true;
        emit PermittedTimelockToBeReverted(msg.sender);
    }

    /// @notice Transfers API3 tokens to this contract and timelocks them
    /// @dev source needs to approve() this contract to transfer amount number
    /// of tokens beforehand.
    /// A recipient cannot have multiple timelocks.
    /// @param source Source of tokens
    /// @param recipient Recipient of tokens
    /// @param amount Amount of tokens
    /// @param releaseStart Start of release time
    /// @param releaseEnd End of release time
    function transferAndLock(
        address source,
        address recipient,
        uint256 amount,
        uint256 releaseStart,
        uint256 releaseEnd
        )
        public
        override
        onlyOwner
    {
        require(
            timelocks[recipient].remainingAmount == 0,
            "Recipient has remaining tokens"
            );
        require(amount != 0, "Amount cannot be 0");
        require(
            releaseEnd > releaseStart,
            "releaseEnd not larger than releaseStart"
            );
        require(
            releaseStart > now,
            "releaseStart not in the future"
            );
        timelocks[recipient] = Timelock({
            totalAmount: amount,
            remainingAmount: amount,
            releaseStart: releaseStart,
            releaseEnd: releaseEnd
            });
        require(
            api3Token.transferFrom(source, address(this), amount),
            "API3 token transferFrom failed"
            );
        emit TransferredAndLocked(
            source,
            recipient,
            amount,
            releaseStart,
            releaseEnd
            );
    }

    /// @notice Convenience function that calls transferAndLock() multiple times
    /// @dev source is expected to be a single address, i.e., the API3 DAO.
    /// source needs to approve() this contract to transfer the sum of the
    /// amounts of tokens to be transferred and locked.
    /// @param source Source of tokens
    /// @param recipients Array of recipients of tokens
    /// @param amounts Array of amounts of tokens
    /// @param releaseStarts Array of starts of release times
    /// @param releaseEnds Array of ends of release times
    function transferAndLockMultiple(
        address source,
        address[] calldata recipients,
        uint256[] calldata amounts,
        uint256[] calldata releaseStarts,
        uint256[] calldata releaseEnds
        )
        external
        override
        onlyOwner
    {
        require(
            recipients.length == amounts.length
                && recipients.length == releaseStarts.length
                && recipients.length == releaseEnds.length,
            "Parameters are of unequal length"
            );
        require(
            recipients.length <= 30,
            "Parameters are longer than 30"
            );
        for (uint256 ind = 0; ind < recipients.length; ind++)
        {
            transferAndLock(
                source,
                recipients[ind],
                amounts[ind],
                releaseStarts[ind],
                releaseEnds[ind]
                );
        }
    }

    /// @notice Used by the recipient to withdraw tokens
    function withdraw()
        external
        override
        onlyIfRecipientHasRemainingTokens(msg.sender)
    {
        address recipient = msg.sender;
        uint256 withdrawable = getWithdrawable(recipient);
        require(
            withdrawable != 0,
            "No withdrawable tokens yet"
            );
        timelocks[recipient].remainingAmount = timelocks[recipient].remainingAmount.sub(withdrawable);
        require(
            api3Token.transfer(recipient, withdrawable),
            "API3 token transfer failed"
            );
        emit Withdrawn(
            recipient,
            withdrawable
            );
    }

    /// @notice Used by the recipient to withdraw their tokens to the API3 pool
    /// @dev We ask the recipient to provide api3PoolAddress as a form of
    /// validation, i.e., the recipient confirms that the API3 pool address set
    /// at this contract is correct
    /// @param api3PoolAddress Address of the API3 pool contract
    /// @param beneficiary Address that the tokens will be deposited to the
    /// pool contract on behalf of
    function withdrawToPool(
        address api3PoolAddress,
        address beneficiary
        )
        external
        override
        onlyIfRecipientHasRemainingTokens(msg.sender)
    {
        require(
            beneficiary != address(0),
            "beneficiary cannot be 0"
            );
        require(address(api3Pool) != address(0), "API3 pool not set yet");
        require(
            address(api3Pool) == api3PoolAddress,
            "API3 pool addresses do not match"
            );
        address recipient = msg.sender;
        uint256 withdrawable = getWithdrawable(recipient);
        uint256 remaining = timelocks[recipient].remainingAmount;
        uint256 timelocked = remaining.sub(withdrawable);
        timelocks[recipient].remainingAmount = 0;
        // Approve the total amount
        api3Token.approve(address(api3Pool), remaining);
        // Deposit the funds that are withdrawable without vesting
        if (withdrawable != 0)
        {
            api3Pool.deposit(
                address(this),
                withdrawable,
                beneficiary
                );
        }
        // Deposit the funds that are still timelocked with vesting.
        // The vesting will continue the same way at the pool, released
        // linearly.
        if (timelocked != 0)
        {
            api3Pool.depositWithVesting(
                address(this),
                timelocked,
                beneficiary,
                now > timelocks[recipient].releaseStart
                    ? now
                    : timelocks[recipient].releaseStart,
                timelocks[recipient].releaseEnd
                );
        }
        emit WithdrawnToPool(
            recipient,
            api3PoolAddress,
            beneficiary
            );
    }

    /// @notice Returns the amount of tokens a recipient can currently withdraw
    /// @param recipient Address of the recipient
    /// @return withdrawable Amount of tokens withdrawable by the recipient
    function getWithdrawable(address recipient)
        public
        view
        override
        returns(uint256 withdrawable)
    {
        Timelock storage timelock = timelocks[recipient];
        uint256 unlocked = getUnlocked(recipient);
        uint256 withdrawn = timelock.totalAmount.sub(timelock.remainingAmount);
        withdrawable = unlocked.sub(withdrawn);
    }

    /// @notice Returns the amount of tokens that was unlocked for the
    /// recipient to date. Includes both withdrawn and non-withdrawn tokens.
    /// @param recipient Address of the recipient
    /// @return unlocked Amount of tokens unlocked for the recipient
    function getUnlocked(address recipient)
        private
        view
        returns(uint256 unlocked)
    {
        Timelock storage timelock = timelocks[recipient];
        if (now <= timelock.releaseStart)
        {
            unlocked = 0;
        }
        else if (now >= timelock.releaseEnd)
        {
            unlocked = timelock.totalAmount;
        }
        else
        {
            uint256 passedTime = now.sub(timelock.releaseStart);
            uint256 totalTime = timelock.releaseEnd.sub(timelock.releaseStart);
            unlocked = timelock.totalAmount.mul(passedTime).div(totalTime);
        }
    }

    /// @notice Returns the details of a timelock
    /// @param recipient Recipient of tokens
    /// @return totalAmount Total amount of tokens
    /// @return remainingAmount Remaining amount of tokens to be withdrawn
    /// @return releaseStart Release start time
    /// @return releaseEnd Release end time
    function getTimelock(address recipient)
        external
        view
        override
        returns (
            uint256 totalAmount,
            uint256 remainingAmount,
            uint256 releaseStart,
            uint256 releaseEnd
            )
    {
        Timelock storage timelock = timelocks[recipient];
        totalAmount = timelock.totalAmount;
        remainingAmount = timelock.remainingAmount;
        releaseStart = timelock.releaseStart;
        releaseEnd = timelock.releaseEnd;
    }

    /// @notice Returns remaining amount of a timelock
    /// @dev Provided separately to be used with Etherscan's "Read"
    /// functionality, in case getTimelock() output is too complicated for the
    /// user.
    /// @param recipient Recipient of tokens
    /// @return remainingAmount Remaining amount of tokens to be withdrawn
    function getRemainingAmount(address recipient)
        external
        view
        override
        returns (uint256 remainingAmount)
    {
        remainingAmount = timelocks[recipient].remainingAmount;
    }

    /// @notice Returns if the recipient's timelock is revertible
    /// @param recipient Recipient of tokens
    /// @return revertStatus If the recipient's timelock is revertible
    function getIfTimelockIsRevertible(address recipient)
        external
        view
        override
        returns (bool revertStatus)
    {
        revertStatus = permittedTimelockToBeReverted[recipient];
    }

    /// @dev Reverts if the recipient does not have remaining tokens
    modifier onlyIfRecipientHasRemainingTokens(address recipient)
    {
        require(
            timelocks[recipient].remainingAmount != 0,
            "Recipient does not have remaining tokens"
            );
        _;
    }
}
