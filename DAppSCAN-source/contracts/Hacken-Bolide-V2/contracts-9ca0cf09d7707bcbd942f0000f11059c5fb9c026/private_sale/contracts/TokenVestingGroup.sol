// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TokenVestingGroup is Ownable {
    using SafeERC20 for IERC20;

    event TokensReleased(address token, uint256 amount);

    mapping(address => uint256) _sumUser;
    mapping(address => uint256) _rateToken;
    mapping(address => uint256) _released;
    mapping(address => address) _userToken;
    address[] _tokens;
    IERC20 public _token;

    // Durations and timestamps are expressed in UNIX time, the same units as block.timestamp.
    uint256 private _durationCount;
    uint256 private _startTimestamp;
    uint256 private _duration;
    uint256 private _endTimestamp;

    /**
     * @dev Creates a vesting contract that vests its balance of any ERC20 token to the
     * beneficiary. By then all
     * of the balance will have vested.
     */
    constructor(
        address tokenValue,
        uint256 durationValue,
        uint256 durationCountValue,
        address[] memory tokensValue
    ) {
        _token = IERC20(tokenValue);
        _duration = durationValue;
        _durationCount = durationCountValue;
        _tokens = tokensValue;
    }

    /**
     * @notice Set amount of token for user deposited token
     */
    function deposit(
        address user,
        address token,
        uint256 amount
    ) external onlyOwner {
        _userToken[user] = token;
        _sumUser[user] = amount;
    }

    /**
     * @notice Transfers vested tokens to beneficiary.
     */
    function finishRound(uint256 startTimestampValue, uint256[] memory tokenRate) external onlyOwner {
        require(_startTimestamp == 0, "Vesting has been started");
        _startTimestamp = startTimestampValue;
        for (uint256 i = 0; i < tokenRate.length; i++) {
            _rateToken[_tokens[i]] = tokenRate[i];
        }
    }

    /**
     * @notice Transfers vested tokens to beneficiary.
     */
    function claim() external {
        uint256 unreleased = releasableAmount();

        require(unreleased > 0, "TokenVesting: no tokens are due");

        _released[msg.sender] = _released[msg.sender] + (unreleased);

        _token.safeTransfer(msg.sender, unreleased);

        emit TokensReleased(address(_token), unreleased);
    }

    /**
     * @notice Set 0 for user deposited token
     */
    function returnDeposit(address user) external onlyOwner {
        require(_startTimestamp == 0, "Vesting has been started");
        _userToken[user] = address(0);
        _sumUser[user] = 0;
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
     * @return the count of duration  of the token vesting.
     */
    function durationCount() public view returns (uint256) {
        return _durationCount;
    }

    /**
     * @return the amount of the token released.
     */
    function released(address account) public view returns (uint256) {
        return _released[account];
    }

    /**
     * @dev Calculates the amount that has already vested but hasn't been released yet.
     */
    function releasableAmount() public view returns (uint256) {
        return _vestedAmount(msg.sender) - (_released[msg.sender]);
    }

    /**
     * @dev Calculates the user dollar deposited.
     */
    function getUserShare(address account) public view returns (uint256) {
        return (_sumUser[account] * _rateToken[_userToken[account]]) / (1 ether);
    }

    /**
     * @dev Calculates the amount that has already vested.
     */
    function _vestedAmount(address account) public view returns (uint256) {
        require(_startTimestamp != 0, "Vesting has not been started");
        uint256 totalBalance = (_sumUser[account] * _rateToken[_userToken[account]]) / (1 ether);
        if (block.timestamp < _startTimestamp) {
            return 0;
        } else if (block.timestamp >= _startTimestamp + _duration * _durationCount) {
            return totalBalance;
        } else {
            return (totalBalance * ((block.timestamp - _startTimestamp) / (_duration))) / (_durationCount);
        }
    }
}
