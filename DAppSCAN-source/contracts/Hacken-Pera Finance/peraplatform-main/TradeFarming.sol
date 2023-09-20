//SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "../interfaces/IUniswapV2Router.sol";
import "../interfaces/ITradeFarming.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @author Ulaş Erdoğan
/// @title Trade Farming Contract for any ETH - Token Pool
/// @dev Can be integrated to any EVM - Uniswap V2 fork DEX' native coin - token pair
contract TradeFarming is ITradeFarming, Ownable {
    /////////// Interfaces & Libraries ///////////

    // DEX router interface
    IUniswapV2Router01 routerContract;
    // Token of pair interface
    IERC20 tokenContract;
    // Rewarding token interface
    IERC20 rewardToken;

    // Using OpenZeppelin's EnumerableSet Util
    using EnumerableSet for EnumerableSet.UintSet;
    // Using OpenZeppelin's SafeERC20 Util
    using SafeERC20 for IERC20;

    /////////// Type Declarations ///////////

    // Track of days' previous volume average
    /// @dev It's the average of previous days and [0, specified day)
    // uint256 day - any day of competition -> uint256 volume - average volume
    mapping(uint256 => uint256) public previousVolumes;
    // Users daily volume records
    // address user -> uint256 day -> uint256 volume
    mapping(address => mapping(uint256 => uint256)) public volumeRecords;
    // Daily total volumes
    // uint256 day -> uint256 volume
    mapping(uint256 => uint256) public dailyVolumes;
    // Daily calculated total rewards
    mapping(uint256 => uint256) public dailyRewards;
    // Users unclaimed traded days
    // address user -> uint256[] days
    mapping(address => EnumerableSet.UintSet) private tradedDays;

    /////////// State Variables ///////////

    // Undistributed total rewards
    uint256 public totalRewardBalance = 0;
    // Total days of the competition
    uint256 public totalDays;
    // Deploying time of the competition
    uint256 public immutable deployTime;

    // Considered previous volume of the pair
    uint256 private previousDay;
    // Last calculation time of the competition
    uint256 public lastAddedDay;
    // Address of WETH token
    address private WETH;

    // Precision of reward calculations
    uint256 constant PRECISION = 1e18;
    // Limiting the daily volume changes
    uint256 immutable UP_VOLUME_CHANGE_LIMIT;
    uint256 immutable DOWN_VOLUME_CHANGE_LIMIT;

    /////////// Events ///////////

    // The event will be emitted when a user claims reward
    event RewardClaimed(address _user, uint256 _amount);

    /////////// Functions ///////////

    /**
     * @notice Constructor function - takes the parameters of the competition
     * @dev May need to be configurated for different chains
     * @dev Give parameters for up&down limits in base of 100. for exp: 110 for %10 up limit, 90 for %10 down limit
     * @param _routerAddress IUniswapV2Router01 - address of the DEX router contract
     * @param _tokenAddress IERC20 - address of the token of the pair
     * @param _rewardAddress IERC20 - address of the reward token
     * @param _previousVolume uint256 - average of previous days
     * @param _previousDay uint256 - previous considered days
     * @param _totalDays uint256 - total days of the competition
     * @param _upLimit uint256 - setter to up volume change limit
     * @param _downLimit uint256 - setter to down volume change limit
     */
    constructor(
        address _routerAddress,
        address _tokenAddress,
        address _rewardAddress,
        uint256 _previousVolume,
        uint256 _previousDay,
        uint256 _totalDays,
        uint256 _upLimit,
        uint256 _downLimit
    ) {
        require(
            _routerAddress != address(0) && _tokenAddress != address(0) && _rewardAddress != address(0),
            "[] Addresses can not be 0 address."
        );

        deployTime = block.timestamp;
        routerContract = IUniswapV2Router01(_routerAddress);
        tokenContract = IERC20(_tokenAddress);
        rewardToken = IERC20(_rewardAddress);
        previousVolumes[0] = _previousVolume;
        previousDay = _previousDay;
        totalDays = _totalDays;
        WETH = routerContract.WETH();
        UP_VOLUME_CHANGE_LIMIT = (PRECISION * _upLimit) / 100;
        DOWN_VOLUME_CHANGE_LIMIT = (PRECISION * _downLimit) / 100;
    }

    /////////// Contract Management Functions ///////////

    /**
     * @notice Increase the reward amount of the competition by Owner
     * @dev The token need to be approved to the contract by Owner
     * @param amount uint256 - amount of the reward token to be added
     */
    function depositRewardTokens(uint256 amount) external onlyOwner {
        totalRewardBalance += amount;
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @notice Decrease and claim the "undistributed" reward amount of the competition by Owner
     * @param amount uint256 - amount of the reward token to be added
     */
    function withdrawRewardTokens(uint256 amount) external onlyOwner {
        require(
            totalRewardBalance >= amount,
            "[withdrawRewardTokens] Not enough balance!"
        );
        totalRewardBalance -= amount;
        rewardToken.safeTransfer(msg.sender, amount);
    }

    /**
     * @notice Change the total time of the competition
     * @param newTotalDays uint256 - new time of the competition
     */
    function changeTotalDays(uint256 newTotalDays) external onlyOwner {
        totalDays = newTotalDays;
    }

    /////////// Reward Viewing and Claiming Functions ///////////

    /**
     * @notice Claim the calculated rewards of the previous days
     * @notice The rewards until the current day can be claimed
     */
    function claimAllRewards() external virtual override {
        // Firstly calculates uncalculated days rewards if there are
        if (lastAddedDay + 1 <= calcDay() && lastAddedDay != totalDays) {
            addNextDaysToAverage();
        }

        uint256 totalRewardOfUser = 0;
        uint256 rewardRate = PRECISION;

        uint256 len = tradedDays[msg.sender].length();
        if(tradedDays[msg.sender].contains(lastAddedDay)) len -= 1;
        // Keep the claimed days to remove from the traded days set
        uint256[] memory _removeDays = new uint256[](len);

        for (uint256 i = 0; i < len; i++) {
            if (tradedDays[msg.sender].at(i) < lastAddedDay) {
                // Calulates how much of the daily rewards the user can claim
                rewardRate = muldiv(
                    volumeRecords[msg.sender][tradedDays[msg.sender].at(i)],
                    PRECISION,
                    dailyVolumes[tradedDays[msg.sender].at(i)]
                );
                // Adds the daily progress payment to total rewards
                totalRewardOfUser += muldiv(
                    rewardRate,
                    dailyRewards[tradedDays[msg.sender].at(i)],
                    PRECISION
                );
                _removeDays[i] = tradedDays[msg.sender].at(i);
            }
        }

        // Remove the claimed days from the set
        for (uint256 i = 0; i < len; i++) {
            require(tradedDays[msg.sender].remove(_removeDays[i]), "[claimAllRewards] Unsuccessful set operation");
        }

        require(totalRewardOfUser > 0, "[claimAllRewards] No reward!");
        rewardToken.safeTransfer(msg.sender, totalRewardOfUser);

        // User claimed rewards
        emit RewardClaimed(msg.sender, totalRewardOfUser);
    }

    /**
     * @notice Checks if the previous days rewards have been calculated
     * @dev If it is false there might be some rewards that can be claimedu unseen
     * @return bool - true if the previous days rewards have been calculated
     */
    function isCalculated() external view returns (bool) {
        return (!(lastAddedDay + 1 <= calcDay() && lastAddedDay != totalDays) ||
            lastAddedDay == totalDays);
    }

    /**
     * @notice Calculates the calculated rewards of the users
     * @dev If isCalculated function returns false, it might be bigger than the return of this function
     * @return uint256 - total reward of the user
     */
    function calculateUserRewards() external view returns (uint256) {
        uint256 totalRewardOfUser = 0;
        uint256 rewardRate = PRECISION;
        for (uint256 i = 0; i < tradedDays[msg.sender].length(); i++) {
            if (tradedDays[msg.sender].at(i) < lastAddedDay) {
                rewardRate = muldiv(
                    volumeRecords[msg.sender][tradedDays[msg.sender].at(i)],
                    PRECISION,
                    dailyVolumes[tradedDays[msg.sender].at(i)]
                );
                totalRewardOfUser += muldiv(
                    rewardRate,
                    dailyRewards[tradedDays[msg.sender].at(i)],
                    PRECISION
                );
            }
        }
        return totalRewardOfUser;
    }

    /**
     * @notice Calculates the daily reward of an user if its calculated
     * @param day uint256 - speciifed day of the competition
     * @dev It returns 0 if the day is not calculated or its on the future
     * @return uint256 - specified days daily reward of the user
     */
    function calculateDailyUserReward(uint256 day)
        external
        view
        returns (uint256)
    {
        uint256 rewardOfUser = 0;
        uint256 rewardRate = PRECISION;

        if (tradedDays[msg.sender].contains(day)) {
            rewardRate = muldiv(
                volumeRecords[msg.sender][day],
                PRECISION,
                dailyVolumes[day]
            );
            uint256 dailyReward;
            if (day < lastAddedDay) {
                dailyReward = dailyRewards[day];
            } else if (day == lastAddedDay) {
                uint256 volumeChange = calculateDayVolumeChange(lastAddedDay);
                if (volumeChange > UP_VOLUME_CHANGE_LIMIT) {
                    volumeChange = UP_VOLUME_CHANGE_LIMIT;
                } else if (volumeChange == 0) {
                    volumeChange = 0;
                } else if (volumeChange < DOWN_VOLUME_CHANGE_LIMIT) {
                    volumeChange = DOWN_VOLUME_CHANGE_LIMIT;
                }
                dailyReward = muldiv(
                    totalRewardBalance / (totalDays - lastAddedDay),
                    volumeChange,
                    PRECISION
                );
            }
            rewardOfUser += muldiv(rewardRate, dailyReward, PRECISION);
        }

        return rewardOfUser;
    }

    /////////// UI Helper Functions ///////////

    /**
     @dev Interacts with the router contract and allows reading in-out values without connecting to the router
     @dev @param @return See the details at: https://docs.uniswap.org/protocol/V2/reference/smart-contracts/router-01#getamountsout
     */
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts)
    {
        return routerContract.getAmountsOut(amountIn, path);
    }

    /**
     @dev Interacts with the router contract and allows reading in-out values without connecting to the router
     @dev @param @return See the details at: https://docs.uniswap.org/protocol/V2/reference/smart-contracts/router-01#getamountsin
     */
    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts)
    {
        return routerContract.getAmountsIn(amountOut, path);
    }

    /////////// Swap Functions ///////////

    /**
     * @notice Swaps the specified amount of ETH for some tokens by connecting to the DEX Router and records the trade volumes
     * @dev Exact amount of the value has to be sended as "value"
     * @dev @param @return Takes and returns the same parameters and values with router functions. 
                           See at: https://docs.uniswap.org/protocol/V2/reference/smart-contracts/router-01#swapexactethfortokens
     */
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable virtual override returns (uint256[] memory out) {
        // Checking the pairs path
        require(path[0] == WETH, "[swapExactETHForTokens] Invalid path!");
        require(
            path[path.length - 1] == address(tokenContract),
            "[swapExactETHForTokens] Invalid path!"
        );
        // Checking exact swapping value
        require(msg.value > 0, "[swapExactETHForTokens] Not a msg.value!");

        // Add the current day if not exists on the traded days set
        if (
            !tradedDays[msg.sender].contains(calcDay()) && calcDay() < totalDays
        ) require(tradedDays[msg.sender].add(calcDay()), "[swapExactETHForTokens] Unsuccessful set operation");

        // Interacting with the router contract and returning the in-out values
        out = routerContract.swapExactETHForTokens{value: msg.value}(
            amountOutMin,
            path,
            to,
            deadline
        );
        //Recording the volumes if the competition is not finished
        if (lastAddedDay != totalDays) tradeRecorder(out[out.length - 1]);
    }

    /**
     * @notice Swaps some amount of ETH for specified amounts of tokens by connecting to the DEX Router and 
               records the trade volumes
     * @dev Equal or bigger amount of value -to be protected from slippage- has to be sended as "value", 
            unused part of the value will be returned.
     * @dev @param @return Takes and returns the same parameters and values with router functions. 
                           See at: https://docs.uniswap.org/protocol/V2/reference/smart-contracts/router-01#swapethforexacttokens
     */
//    SWC-126-Insufficient Gas Griefing:L351-389
    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable virtual override returns (uint256[] memory) {
        // Checking the pairs path
        require(path[0] == WETH, "[swapExactETHForTokens] Invalid path!");
        require(
            path[path.length - 1] == address(tokenContract),
            "[swapExactETHForTokens] Invalid path!"
        );

        // Calculating the exact ETH input value
        uint256 volume = routerContract.getAmountsIn(amountOut, path)[0];
        require(
            msg.value >= volume,
            "[swapETHForExactTokens] Not enough msg.value!"
        );

        // Add the current day if not exists on the traded days set
        if (
            !tradedDays[msg.sender].contains(calcDay()) && calcDay() < totalDays
        ) require(tradedDays[msg.sender].add(calcDay()), "[swapETHForExactTokens] Unsuccessful set operation");

        //Recording the volumes if the competition is not finished
        if (lastAddedDay != totalDays) tradeRecorder(amountOut);
        // Refunding the over-value
        if (msg.value > volume)
            payable(msg.sender).transfer(msg.value - volume);
        // Interacting with the router contract and returning the in-out values
        return
            routerContract.swapETHForExactTokens{value: volume}(
                amountOut,
                path,
                to,
                deadline
            );
    }

    /**
     * @notice Swaps the specified amount of tokens for some ETH by connecting to the DEX Router and records the trade volumes
     * @dev The token in the pair need to be approved to the contract by the users
     * @dev @param @return Takes and returns the same parameters and values with router functions. 
                           See at: https://docs.uniswap.org/protocol/V2/reference/smart-contracts/router-01#swapexacttokensforeth
     */
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override returns (uint256[] memory) {
        // Checking the pairs path
        require(
            path[path.length - 1] == WETH,
            "[swapExactETHForTokens] Invalid path!"
        );
        require(
            path[0] == address(tokenContract),
            "[swapExactETHForTokens] Invalid path!"
        );

        // Add the current day if not exists on the traded days set
        if (
            !tradedDays[msg.sender].contains(calcDay()) && calcDay() < totalDays
        ) require(tradedDays[msg.sender].add(calcDay()), "[swapExactTokensForETH] Unsuccessful set operation");
        tokenContract.safeTransferFrom(msg.sender, address(this), amountIn);

        // Approve the pair token to the router
        tokenContract.safeIncreaseAllowance(address(routerContract), amountIn);

        //Recording the volumes if the competition is not finished
        if (lastAddedDay != totalDays) tradeRecorder(amountIn);
        // Interacting with the router contract and returning the in-out values
        return
            routerContract.swapExactTokensForETH(
                amountIn,
                amountOutMin,
                path,
                to,
                deadline
            );
    }

    /**
     * @notice Swaps some amount of tokens for specified amounts of ETH by connecting to the DEX Router
               and records the trade volumes
     * @dev The token in the pair need to be approved to the contract by the users
     * @dev @param @return Takes and returns the same parameters and values with router functions. 
                           See at: https://docs.uniswap.org/protocol/V2/reference/smart-contracts/router-01#swaptokensforexacteth
     */
    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override returns (uint256[] memory out) {
        // Checking the pairs path
        require(
            path[path.length - 1] == WETH,
            "[swapExactETHForTokens] Invalid path!"
        );
        require(
            path[0] == address(tokenContract),
            "[swapExactETHForTokens] Invalid path!"
        );

        // Add the current day if not exists on the traded days set
        if (
            !tradedDays[msg.sender].contains(calcDay()) && calcDay() < totalDays
        ) require(tradedDays[msg.sender].add(calcDay()), "[swapTokensForExactETH] Unsuccessful set operation");
        tokenContract.safeTransferFrom(
            msg.sender,
            address(this),
            routerContract.getAmountsIn(amountOut, path)[0]
        );

        // Approve the pair token to the router
        tokenContract.safeIncreaseAllowance(
            address(routerContract),
            amountInMax
        );

        // Interacting with the router contract and returning the in-out values
        out = routerContract.swapTokensForExactETH(
            amountOut,
            amountInMax,
            path,
            to,
            deadline
        );
        //Recording the volumes if the competition is not finished
        if (lastAddedDay != totalDays) tradeRecorder(out[0]);

        // Resetting the approval amount the pair token to the router
        tokenContract.safeApprove(address(routerContract), 0);
    }

    /////////// Get Public Data ///////////

    /**
     * @notice Get the current day of the competition
     * @return uint256 - current day of the competition
     */
    function calcDay() public view returns (uint256) {
        return (block.timestamp - deployTime) / 1 days;
    }

    /////////// Volume Calculation Functions ///////////

    /**
     * @notice Records the trade volumes if the competition is not finished.
     * @notice If there are untraded or uncalculated days until the current days, calculate these days
     * @param volume uint256 - the volume of the trade
     */
    function tradeRecorder(uint256 volume) private {
        // Record the volume if the competition is not finished
        if (calcDay() < totalDays) {
            volumeRecords[msg.sender][calcDay()] += volume;
            dailyVolumes[calcDay()] += volume;
        }

        // Calculate the untraded or uncalculated days until the current day
        if (lastAddedDay + 1 <= calcDay() && lastAddedDay != totalDays) {
            addNextDaysToAverage();
        }
    }

    /**
     * @notice Calculates the average volume change of the specified day from the previous days
     * @param day uin256 - day to calculate the average volume change
     * @return uint256 - average volume change of the specified day over PRECISION
     * @dev Returns PRECISION +- (changed value)
     */
    function calculateDayVolumeChange(uint256 day)
        private
        view
        returns (uint256)
    {
        return muldiv(dailyVolumes[day], PRECISION, previousVolumes[day]);
    }

    /**
     * @notice Calculates the rewards for the untraded or uncalculated days until the current day
     */
    function addNextDaysToAverage() private {
        uint256 _cd = calcDay();
        // Previous day count of the calculating day
        uint256 _pd = previousDay + lastAddedDay + 1;
        assert(lastAddedDay + 1 <= _cd);
        // Recording the average of previous days and [0, _cd)
        previousVolumes[lastAddedDay + 1] =
            muldiv(previousVolumes[lastAddedDay], (_pd - 1), _pd) +
            dailyVolumes[lastAddedDay] /
            _pd;

        uint256 volumeChange = calculateDayVolumeChange(lastAddedDay);
        // Limiting the volume change between 90% - 110%
        if (volumeChange > UP_VOLUME_CHANGE_LIMIT) {
            volumeChange = UP_VOLUME_CHANGE_LIMIT;
        } else if (volumeChange == 0) {
            volumeChange = 0;
        } else if (volumeChange < DOWN_VOLUME_CHANGE_LIMIT) {
            volumeChange = DOWN_VOLUME_CHANGE_LIMIT;
        }

        // Calculating the daily rewards to be distributed - set to the remaining balance if there are an overflow for the last day
        if (lastAddedDay == totalDays - 1 && volumeChange > PRECISION) {
            dailyRewards[lastAddedDay] = totalRewardBalance;
        } else {
            dailyRewards[lastAddedDay] = muldiv(
                (totalRewardBalance / (totalDays - lastAddedDay)),
                volumeChange,
                PRECISION
            );
        }
        totalRewardBalance = totalRewardBalance - dailyRewards[lastAddedDay];

        // Moving up the calculated days
        lastAddedDay += 1;

        // Continue to calculating if still there are uncalculated or untraded days
        if (lastAddedDay + 1 <= _cd && lastAddedDay != totalDays)
            addNextDaysToAverage();
    }

    /**
     * @notice Used in the functions which have the risks of overflow on a * b / c situation
     * @notice Kindly thanks to Remco Bloemen for this muldiv function
     * @dev See the function details at: https://2π.com/21/muldiv/
     * @param a, @param b uint256 - the multipliying values
     * @param denominator uint256 - the divisor value
     */
    function muldiv(
        uint256 a,
        uint256 b,
        uint256 denominator
    ) private pure returns (uint256 result) {
        require(denominator > 0);

        uint256 prod0;
        uint256 prod1;
        assembly {
            let mm := mulmod(a, b, not(0))
            prod0 := mul(a, b)
            prod1 := sub(sub(mm, prod0), lt(mm, prod0))
        }

        if (prod1 == 0) {
            assembly {
                result := div(prod0, denominator)
            }
            return result;
        }
        require(prod1 < denominator);
        uint256 remainder;
        assembly {
            remainder := mulmod(a, b, denominator)
        }
        assembly {
            prod1 := sub(prod1, gt(remainder, prod0))
            prod0 := sub(prod0, remainder)
        }

        uint256 twos = denominator & (~denominator + 1);
        assembly {
            denominator := div(denominator, twos)
        }

        assembly {
            prod0 := div(prod0, twos)
        }

        assembly {
            twos := add(div(sub(0, twos), twos), 1)
        }
        prod0 |= prod1 * twos;

        uint256 inv = (3 * denominator) ^ 2;

        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;

        result = prod0 * inv;
        return result;
    }
}
