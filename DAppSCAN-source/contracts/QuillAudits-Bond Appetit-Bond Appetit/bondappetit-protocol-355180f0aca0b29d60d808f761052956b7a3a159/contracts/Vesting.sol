// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./utils/OwnablePausable.sol";

contract Vesting is OwnablePausable {
    using SafeMath for uint256;
    using SafeERC20 for ERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice The number of periods for a per recipient.
    function maxPeriodsPerRecipient() public pure returns (uint256) {
        return 5;
    } // 5 perios per recipient.

    /// @notice Address of vesting token.
    ERC20 public token;

    struct Period {
        // Identifier.
        uint256 id;
        // Reward amount.
        uint256 amount;
        // Unlockd date.
        uint256 date;
        // Description.
        string description;
        // Reward withdrawal flag.
        bool withdrawal;
    }

    /// @dev Index last period.
    uint256 internal currentPeriod = 0;

    /// @dev Participants list.
    EnumerableSet.AddressSet internal participants;

    /// @dev All registered periods.
    mapping(address => mapping(uint256 => Period)) internal periods;

    /// @dev Period identifiers index.
    mapping(address => uint256[]) internal periodsIndex;

    /// @notice An event emitted when all votes delegate to.
    event DelegateVotes(address delegatee);

    /// @notice An event emitted when locking a period.
    event Locked(uint256 periodId);

    /// @notice An event emitted when revoked a period.
    event Revoked(uint256 periodId);

    /// @notice An event emitted when withdrawal a period.
    event Withdrawal(address recipient, uint256 periodId);

    /**
     * @param _token Address of vesting token contract.
     */
    constructor(address _token) public {
        token = ERC20(_token);
    }

    /**
     * @notice Delegate votes to delegatee.
     * @param delegatee The address to delegate votes to
     */
    function delegate(address governanceToken, address delegatee) external onlyOwner {
        GovernanceTokenInterface(governanceToken).delegate(delegatee);
        emit DelegateVotes(delegatee);
    }

    /**
     * @notice Add new period.
     * @param recipient Recipient of reward.
     * @param amount Reward amount.
     * @param date Date of unlockd period.
     * @return Added period identifier.
     */
    function lock(
        address recipient,
        uint256 amount,
        string memory description,
        uint256 date
    ) external onlyOwner returns (uint256) {
        require(periodsIndex[recipient].length <= maxPeriodsPerRecipient(), "Vesting::lock: too many periods");

        token.safeTransferFrom(_msgSender(), address(this), amount);

        currentPeriod += 1;
        participants.add(recipient);
        periods[recipient][currentPeriod] = Period(currentPeriod, amount, date, description, false);
        periodsIndex[recipient].push(currentPeriod);
        emit Locked(currentPeriod);

        return currentPeriod;
    }

    /**
     * @notice Revoke period.
     * @param recipient Recipient of reward.
     * @param periodId Period identifier.
     */
    function revoke(address recipient, uint256 periodId) external onlyOwner {
        Period storage period = periods[recipient][periodId];
        require(!period.withdrawal, "Vesting::revoke: already withdraw");

        address owner = _msgSender();
        uint256 amount = period.amount;
        period.amount = 0;
        token.safeTransfer(owner, amount);

        emit Revoked(periodId);
    }

    /**
     * @notice Return all participants addresses.
     * @return Participants addresses.
     */
    function getParticipants() external view returns (address[] memory) {
        address[] memory result = new address[](participants.length());

        for (uint256 i = 0; i < participants.length(); i++) {
            result[i] = participants.at(i);
        }

        return result;
    }

    /**
     * @notice Get information of period.
     * @param recipient Recipient address.
     * @return Recipient periods list.
     */
    function info(address recipient) external view returns (Period[] memory) {
        Period[] memory result = new Period[](periodsIndex[recipient].length);

        for (uint256 i = 0; i < periodsIndex[recipient].length; i++) {
            uint256 periodId = periodsIndex[recipient][i];

            result[i] = periods[recipient][periodId];
        }

        return result;
    }

    /**
     * @notice Withdraw reward.
     * @param periodId Target period identifier.
     */
    function withdraw(uint256 periodId) external whenNotPaused {
        address recipient = _msgSender();
        Period storage period = periods[recipient][periodId];
        require(period.amount > 0, "Vesting::withdraw: period is empty");
        require(!period.withdrawal, "Vesting::withdraw: already withdraw");
        require(block.timestamp > period.date, "Vesting::withdraw: access denied");

        period.withdrawal = true;
        token.safeTransfer(recipient, period.amount);
        emit Withdrawal(recipient, periodId);
    }
}

interface GovernanceTokenInterface {
    function delegate(address delegatee) external;
}
