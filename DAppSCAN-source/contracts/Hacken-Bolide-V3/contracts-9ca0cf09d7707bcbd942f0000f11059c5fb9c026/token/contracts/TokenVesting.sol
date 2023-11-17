// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract TokenVesting {
    using SafeERC20 for IERC20;

    event TokensReleased(address token, uint256 amount);

    IERC20 public _token;
    address private _beneficiary;

    // Durations and timestamps are expressed in UNIX time, the same units as block.timestamp.
    uint256 private _durationCount;
    uint256 private _startTimestamp;
    uint256 private _duration;
    uint256 private _endTimestamp;

    uint256 private _released;

    /**
     * @dev Creates a vesting contract that vests its balance of any ERC20 token to the
     * beneficiary. By then all
     * of the balance will have vested.
     * @param tokenValue Address of vesting token
     * @param beneficiaryValue Address of beneficiary
     * @param startTimestampValue Timstamp when start vesting
     * @param durationValue Duration one period of vesit
     * @param durationCountValue Count duration one period of vesit
     */
    constructor(
        address tokenValue,
        address beneficiaryValue,
        uint256 startTimestampValue,
        uint256 durationValue,
        uint256 durationCountValue
    ) {
        require(beneficiaryValue != address(0), "TokenVesting: beneficiary is the zero address");

        _token = IERC20(tokenValue);
        _beneficiary = beneficiaryValue;
        _duration = durationValue;
        _durationCount = durationCountValue;
        _startTimestamp = startTimestampValue;
    }

    /**
     * @return the beneficiary of the tokens.
     */
    function beneficiary() public view returns (address) {
        return _beneficiary;
    }

    /**
     * @return the end time of the token vesting.
     */
    function end() public view returns (uint256) {
        return _startTimestamp + _duration * _durationCount;
    }

    /**
     * @return the start time of the token vesting.
     */
    function start() public view returns (uint256) {
        return _startTimestamp;
    }

    /**
     * @return the duration of the token vesting.
     */
    function duration() public view returns (uint256) {
        return _duration;
    }

    /**
     * @return the amount of the token released.
     */
    function released() public view returns (uint256) {
        return _released;
    }

    /**
     * @notice Transfers vested tokens to beneficiary.
     */
    function release() public {
        uint256 unreleased = releasableAmount();

        require(unreleased > 0, "TokenVesting: no tokens are due");

        _released = _released + (unreleased);

        _token.safeTransfer(_beneficiary, unreleased);

        emit TokensReleased(address(_token), unreleased);
    }

    /**
     * @dev Calculates the amount that has already vested but hasn't been released yet.
     */
    function releasableAmount() public view returns (uint256) {
        return _vestedAmount() - (_released);
    }

    /**
     * @dev Calculates the amount that has already vested.
     */
    function _vestedAmount() private view returns (uint256) {
        uint256 currentBalance = _token.balanceOf(address(this));
        uint256 totalBalance = currentBalance + (_released);

        if (block.timestamp < _startTimestamp) {
            return 0;
        } else if (block.timestamp >= _startTimestamp + _duration * _durationCount) {
            return totalBalance;
        } else {
            return (totalBalance * ((block.timestamp - _startTimestamp) / (_duration))) / _durationCount;
        }
    }
}
