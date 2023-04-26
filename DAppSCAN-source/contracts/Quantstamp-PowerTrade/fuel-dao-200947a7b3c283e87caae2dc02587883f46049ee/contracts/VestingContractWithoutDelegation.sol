pragma solidity ^0.5.16;

import "./SafeMath.sol";
import "./ReentrancyGuard.sol";
import "./IERC20.sol";

/// @author BlockRocket
contract VestingContractWithoutDelegation is ReentrancyGuard {
    using SafeMath for uint256;

    /// @notice event emitted when a vesting schedule is created
    event ScheduleCreated(address indexed _beneficiary);

    /// @notice event emitted when a successful drawn down of vesting tokens is made
    event DrawDown(address indexed _beneficiary, uint256 indexed _amount);

    /// @notice start of vesting period as a timestamp
    uint256 public start;

    /// @notice end of vesting period as a timestamp
    uint256 public end;

    /// @notice cliff duration in seconds
    uint256 public cliffDuration;

    /// @notice owner address set on construction
    address public owner;

    /// @notice amount vested for a beneficiary. Note beneficiary address can not be reused
    mapping(address => uint256) public vestedAmount;

    /// @notice cumulative total of tokens drawn down (and transferred from the deposit account) per beneficiary
    mapping(address => uint256) public totalDrawn;

    /// @notice last drawn down time (seconds) per beneficiary
    mapping(address => uint256) public lastDrawnAt;

    /// @notice ERC20 token we are vesting
    IERC20 public token;

    /**
     * @notice Construct a new vesting contract
     * @param _token ERC20 token
     * @param _start start timestamp
     * @param _end end timestamp
     * @param _cliffDurationInSecs cliff duration in seconds
     * @dev caller on constructor set as owner; this can not be changed
     */
    constructor(IERC20 _token, uint256 _start, uint256 _end, uint256 _cliffDurationInSecs) public {
        require(address(_token) != address(0), "VestingContract::constructor: Invalid token");
        require(_end >= _start, "VestingContract::constructor: Start must be before end");

        token = _token;
        owner = msg.sender;

        start = _start;
        end = _end;
        cliffDuration = _cliffDurationInSecs;
    }

    /**
     * @notice Create new vesting schedules in a batch
     * @notice A transfer is used to bring tokens into the VestingDepositAccount so pre-approval is required
     * @param _beneficiaries array of beneficiaries of the vested tokens
     * @param _amounts array of amount of tokens (in wei)
     * @dev array index of address should be the same as the array index of the amount
     */
    function createVestingSchedules(
        address[] calldata _beneficiaries,
        uint256[] calldata _amounts
    ) external returns (bool) {
        require(msg.sender == owner, "VestingContract::createVestingSchedules: Only Owner");
        require(_beneficiaries.length > 0, "VestingContract::createVestingSchedules: Empty Data");
        require(
            _beneficiaries.length == _amounts.length,
            "VestingContract::createVestingSchedules: Array lengths do not match"
        );

        bool result = true;

        for(uint i = 0; i < _beneficiaries.length; i++) {
            address beneficiary = _beneficiaries[i];
            uint256 amount = _amounts[i];
            _createVestingSchedule(beneficiary, amount);
        }

        return result;
    }

    /**
     * @notice Create a new vesting schedule
     * @notice A transfer is used to bring tokens into the VestingDepositAccount so pre-approval is required
     * @param _beneficiary beneficiary of the vested tokens
     * @param _amount amount of tokens (in wei)
     */
    function createVestingSchedule(address _beneficiary, uint256 _amount) external returns (bool) {
        require(msg.sender == owner, "VestingContract::createVestingSchedule: Only Owner");
        return _createVestingSchedule(_beneficiary, _amount);
    }

    /**
     * @notice Draws down any vested tokens due
     * @dev Must be called directly by the beneficiary assigned the tokens in the schedule
     */
    function drawDown() nonReentrant external returns (bool) {
        return _drawDown(msg.sender);
    }


    // Accessors

    /**
     * @notice Vested token balance for a beneficiary
     * @dev Must be called directly by the beneficiary assigned the tokens in the schedule
     * @return _tokenBalance total balance proxied via the ERC20 token
     */
    function tokenBalance() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    /**
     * @notice Vesting schedule and associated data for a beneficiary
     * @dev Must be called directly by the beneficiary assigned the tokens in the schedule
     * @return _amount
     * @return _totalDrawn
     * @return _lastDrawnAt
     * @return _remainingBalance
     */
    function vestingScheduleForBeneficiary(address _beneficiary)
    external view
    returns (uint256 _amount, uint256 _totalDrawn, uint256 _lastDrawnAt, uint256 _remainingBalance) {
        return (
        vestedAmount[_beneficiary],
        totalDrawn[_beneficiary],
        lastDrawnAt[_beneficiary],
        vestedAmount[_beneficiary].sub(totalDrawn[_beneficiary])
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
    function remainingBalance(address _beneficiary) external view returns (uint256) {
        return vestedAmount[_beneficiary].sub(totalDrawn[_beneficiary]);
    }

    // Internal

    function _createVestingSchedule(address _beneficiary, uint256 _amount) internal returns (bool) {
        require(_beneficiary != address(0), "VestingContract::createVestingSchedule: Beneficiary cannot be empty");
        require(_amount > 0, "VestingContract::createVestingSchedule: Amount cannot be empty");

        // Ensure one per address
        require(vestedAmount[_beneficiary] == 0, "VestingContract::createVestingSchedule: Schedule already in flight");

        vestedAmount[_beneficiary] = _amount;

        // Vest the tokens into the deposit account and delegate to the beneficiary
        require(
            token.transferFrom(msg.sender, address(this), _amount),
            "VestingContract::createVestingSchedule: Unable to escrow tokens"
        );

        emit ScheduleCreated(_beneficiary);

        return true;
    }

    function _drawDown(address _beneficiary) internal returns (bool) {
        require(vestedAmount[_beneficiary] > 0, "VestingContract::_drawDown: There is no schedule currently in flight");

        uint256 amount = _availableDrawDownAmount(_beneficiary);
        require(amount > 0, "VestingContract::_drawDown: No allowance left to withdraw");

        // Update last drawn to now
        lastDrawnAt[_beneficiary] = _getNow();

        // Increase total drawn amount
        totalDrawn[_beneficiary] = totalDrawn[_beneficiary].add(amount);

        // Safety measure - this should never trigger
        require(
            totalDrawn[_beneficiary] <= vestedAmount[_beneficiary],
            "VestingContract::_drawDown: Safety Mechanism - Drawn exceeded Amount Vested"
        );

        // Issue tokens to beneficiary
        require(token.transfer(_beneficiary, amount), "VestingContract::_drawDown: Unable to transfer tokens");

        emit DrawDown(_beneficiary, amount);

        return true;
    }

    function _getNow() internal view returns (uint256) {
        return block.timestamp;
    }

    function _availableDrawDownAmount(address _beneficiary) internal view returns (uint256 _amount) {

        // Cliff Period
        if (_getNow() <= start.add(cliffDuration)) {
            // the cliff period has not ended, no tokens to draw down
            return 0;
        }

        // Schedule complete
        if (_getNow() > end) {
            return vestedAmount[_beneficiary].sub(totalDrawn[_beneficiary]);
        }

        // Schedule is active

        // Work out when the last invocation was
        uint256 timeLastDrawnOrStart = lastDrawnAt[_beneficiary] == 0 ? start : lastDrawnAt[_beneficiary];

        // Find out how much time has past since last invocation
        uint256 timePassedSinceLastInvocation = _getNow().sub(timeLastDrawnOrStart);

        // Work out how many due tokens - time passed * rate per second
        uint256 drawDownRate = vestedAmount[_beneficiary].div(end.sub(start));
        uint256 amount = timePassedSinceLastInvocation.mul(drawDownRate);

        return amount;
    }
}
