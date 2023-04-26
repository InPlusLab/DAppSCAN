pragma solidity ^0.5.16;

import "./SafeMath.sol";
import "./ReentrancyGuard.sol";
import "./CloneFactory.sol";
import "./IERC20.sol";
import "./VestingDepositAccount.sol";

/// @author BlockRocket
contract VestingContract is CloneFactory, ReentrancyGuard {
    using SafeMath for uint256;

    /// @notice event emitted when a vesting schedule is created
    event ScheduleCreated(address indexed _beneficiary, uint256 indexed _amount);

    /// @notice event emitted when a successful drawn down of vesting tokens is made
    event DrawDown(address indexed _beneficiary, uint256 indexed _amount, uint256 indexed _time);

    /// @notice struct to define the total amount vested (this never changes) and the associated deposit account
    struct Schedule {
        uint256 amount;
        VestingDepositAccount depositAccount;
    }

    /// @notice owner address set on construction
    address public owner;

    /// @notice beneficiary to schedule mapping. Note beneficiary address can not be reused
    mapping(address => Schedule) public vestingSchedule;

    /// @notice cumulative total of tokens drawn down (and transferred from the deposit account) per beneficiary
    mapping(address => uint256) public totalDrawn;

    /// @notice last drawn down time (seconds) per beneficiary
    mapping(address => uint256) public lastDrawnAt;

    /// @notice set when updating beneficiary (via owner) to indicate a voided/completed schedule
    mapping(address => bool) public voided;

    /// @notice ERC20 token we are vesting
    IERC20 public token;

    /// @notice the blueprint deposit account to clone using CloneFactory (https://eips.ethereum.org/EIPS/eip-1167)
    address public baseVestingDepositAccount;

    /// @notice start of vesting period as a timestamp
    uint256 public start;

    /// @notice end of vesting period as a timestamp
    uint256 public end;

    /// @notice cliff duration in seconds
    uint256 public cliffDuration;

    /**
     * @notice Construct a new vesting contract
     * @param _token ERC20 token
     * @param _baseVestingDepositAccount address of the VestingDepositAccount to clone
     * @param _start start timestamp
     * @param _end end timestamp
     * @param _cliffDurationInSecs cliff duration in seconds
     * @dev caller on constructor set as owner; this can not be changed
     */
    constructor(
        IERC20 _token,
        address _baseVestingDepositAccount,
        uint256 _start,
        uint256 _end,
        uint256 _cliffDurationInSecs
    ) public {
        require(address(_token) != address(0), "VestingContract::constructor: Invalid token");
        require(_end >= _start, "VestingContract::constructor: Start must be before end");

        token = _token;
        owner = msg.sender;
        baseVestingDepositAccount = _baseVestingDepositAccount;

        start = _start;
        end = _end;
        cliffDuration = _cliffDurationInSecs;
    }

    /**
     * @notice Create a new vesting schedule
     * @notice A transfer is used to bring tokens into the VestingDepositAccount so pre-approval is required
     * @notice Delegation is set for the beneficiary on the token during schedule creation
     * @param _beneficiary beneficiary of the vested tokens
     * @param _amount amount of tokens (in wei)
     */
    function createVestingSchedule(address _beneficiary, uint256 _amount) external returns (bool) {
        require(msg.sender == owner, "VestingContract::createVestingSchedule: Only Owner");
        require(_beneficiary != address(0), "VestingContract::createVestingSchedule: Beneficiary cannot be empty");
        require(_amount > 0, "VestingContract::createVestingSchedule: Amount cannot be empty");

        // Ensure only one per address
        require(
            vestingSchedule[_beneficiary].amount == 0,
            "VestingContract::createVestingSchedule: Schedule already in flight"
        );

        // Set up the vesting deposit account for the _beneficiary
        address depositAccountAddress = createClone(baseVestingDepositAccount);
        VestingDepositAccount depositAccount = VestingDepositAccount(depositAccountAddress);
        depositAccount.init(address(token), address(this), _beneficiary);

        // Create schedule
        vestingSchedule[_beneficiary] = Schedule({
            amount : _amount,
            depositAccount : depositAccount
            });

        // Vest the tokens into the deposit account and delegate to the beneficiary
        require(
            token.transferFrom(msg.sender, address(depositAccount), _amount),
            "VestingContract::createVestingSchedule: Unable to transfer tokens to VDA"
        );

        emit ScheduleCreated(_beneficiary, _amount);

        return true;
    }

    /**
     * @notice Draws down any vested tokens due
     * @dev Must be called directly by the beneficiary assigned the tokens in the schedule
     */
    function drawDown() nonReentrant external returns (bool) {
        return _drawDown(msg.sender);
    }

    /**
     * @notice Updates a schedule beneficiary
     * @notice Voids the old schedule and transfers remaining amount to new beneficiary via a new schedule
     * @dev Only owner
     * @param _currentBeneficiary beneficiary to be replaced
     * @param _newBeneficiary beneficiary to vest remaining tokens to
     */
    function updateScheduleBeneficiary(address _currentBeneficiary, address _newBeneficiary) external {
        require(msg.sender == owner, "VestingContract::updateScheduleBeneficiary: Only owner");

        // retrieve existing schedule
        Schedule memory schedule = vestingSchedule[_currentBeneficiary];
        require(
            schedule.amount > 0,
            "VestingContract::updateScheduleBeneficiary: There is no schedule currently in flight"
        );
        require(_drawDown(_currentBeneficiary), "VestingContract::_updateScheduleBeneficiary: Unable to drawn down");

        // the old schedule is now void
        voided[_currentBeneficiary] = true;

        // setup new schedule with the amount left after the previous beneficiary's draw down
        vestingSchedule[_newBeneficiary] = Schedule({
            amount : schedule.amount.sub(totalDrawn[_currentBeneficiary]),
            depositAccount : schedule.depositAccount
            });

        vestingSchedule[_newBeneficiary].depositAccount.switchBeneficiary(_newBeneficiary);
    }

    // Accessors

    /**
     * @notice Vested token balance for a beneficiary
     * @dev Must be called directly by the beneficiary assigned the tokens in the schedule
     * @return _tokenBalance total balance proxied via the ERC20 token
     */
    function tokenBalance() external view returns (uint256 _tokenBalance) {
        return token.balanceOf(address(vestingSchedule[msg.sender].depositAccount));
    }

    /**
     * @notice Vesting schedule and associated data for a beneficiary
     * @dev Must be called directly by the beneficiary assigned the tokens in the schedule
     * @return _amount
     * @return _totalDrawn
     * @return _lastDrawnAt
     * @return _drawDownRate
     * @return _remainingBalance
     * @return _depositAccountAddress
     */
    function vestingScheduleForBeneficiary(address _beneficiary)
    external view
    returns (
        uint256 _amount,
        uint256 _totalDrawn,
        uint256 _lastDrawnAt,
        uint256 _drawDownRate,
        uint256 _remainingBalance,
        address _depositAccountAddress
    ) {
        Schedule memory schedule = vestingSchedule[_beneficiary];
        return (
        schedule.amount,
        totalDrawn[_beneficiary],
        lastDrawnAt[_beneficiary],
        schedule.amount.div(end.sub(start)),
        schedule.amount.sub(totalDrawn[_beneficiary]),
        address(schedule.depositAccount)
        );
    }

    /**
     * @notice Draw down amount currently available (based on the block timestamp)
     * @param _beneficiary beneficiary of the vested tokens
     * @return _amount tokens due from vesting schedule
     */
    function availableDrawDownAmount(address _beneficiary) external view returns (uint256 _amount) {
        return _availableDrawDownAmount(_beneficiary);
    }

    /**
     * @notice Balance remaining in vesting schedule
     * @param _beneficiary beneficiary of the vested tokens
     * @return _remainingBalance tokens still due (and currently locked) from vesting schedule
     */
    function remainingBalance(address _beneficiary) external view returns (uint256 _remainingBalance) {
        Schedule memory schedule = vestingSchedule[_beneficiary];
        return schedule.amount.sub(totalDrawn[_beneficiary]);
    }

    // Internal

    function _drawDown(address _beneficiary) internal returns (bool) {
        Schedule memory schedule = vestingSchedule[_beneficiary];
        require(schedule.amount > 0, "VestingContract::_drawDown: There is no schedule currently in flight");

        uint256 amount = _availableDrawDownAmount(_beneficiary);
        require(amount > 0, "VestingContract::_drawDown: No allowance left to withdraw");

        // Update last drawn to now
        lastDrawnAt[_beneficiary] = _getNow();

        // Increase total drawn amount
        totalDrawn[_beneficiary] = totalDrawn[_beneficiary].add(amount);

        // Safety measure - this should never trigger
        require(
            totalDrawn[_beneficiary] <= schedule.amount,
            "VestingContract::_drawDown: Safety Mechanism - Drawn exceeded Amount Vested"
        );

        // Issue tokens to beneficiary
        require(
            schedule.depositAccount.transferToBeneficiary(amount),
            "VestingContract::_drawDown: Unable to transfer tokens"
        );

        emit DrawDown(_beneficiary, amount, _getNow());

        return true;
    }

    function _getNow() internal view returns (uint256) {
        return block.timestamp;
    }

    function _availableDrawDownAmount(address _beneficiary) internal view returns (uint256 _amount) {
        Schedule memory schedule = vestingSchedule[_beneficiary];

        // voided contract should not allow any draw downs
        if (voided[_beneficiary]) {
            return 0;
        }

        // cliff
        if (_getNow() <= start.add(cliffDuration)) {
            // the cliff period has not ended, no tokens to draw down
            return 0;
        }

        // schedule complete
        if (_getNow() > end) {
            return schedule.amount.sub(totalDrawn[_beneficiary]);
        }

        // Schedule is active

        // Work out when the last invocation was
        uint256 timeLastDrawnOrStart = lastDrawnAt[_beneficiary] == 0 ? start : lastDrawnAt[_beneficiary];

        // Find out how much time has past since last invocation
        uint256 timePassedSinceLastInvocation = _getNow().sub(timeLastDrawnOrStart);

        // Work out how many due tokens - time passed * rate per second
        uint256 drawDownRate = schedule.amount.div(end.sub(start));
        uint256 amount = timePassedSinceLastInvocation.mul(drawDownRate);

        return amount;
    }
}
