// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.6.11;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./aave/ILendingPoolAddressesProvider.sol";
import "./aave/ILendingPool.sol";
import "./aave/AToken.sol";
import "./aave/IncentiveController.sol";
import "./GoodGhosting.sol";

/// @title GoodGhosting Game Contract
/// @author Francis Odisi & Viraz Malhotra
/// @notice Used for the games deployed on Polygon using Aave as the underlying external pool.
contract GoodGhostingPolygon is GoodGhosting {
    IncentiveController public incentiveController;
    IERC20 public immutable matic;
    uint256 public rewardsPerPlayer;

    /**
        Creates a new instance of GoodGhosting game
        @param _inboundCurrency Smart contract address of inbound currency used for the game.
        @param _lendingPoolAddressProvider Smart contract address of the lending pool adddress provider.
        @param _segmentCount Number of segments in the game.
        @param _segmentLength Lenght of each segment, in seconds (i.e., 180 (sec) => 3 minutes).
        @param _segmentPayment Amount of tokens each player needs to contribute per segment (i.e. 10*10**18 equals to 10 DAI - note that DAI uses 18 decimal places).
        @param _earlyWithdrawalFee Fee paid by users on early withdrawals (before the game completes). Used as an integer percentage (i.e., 10 represents 10%). Does not accept "decimal" fees like "0.5".
        @param _customFee performance fee charged by admin. Used as an integer percentage (i.e., 10 represents 10%). Does not accept "decimal" fees like "0.5".
        @param _dataProvider id for getting the data provider contract address 0x1 to be passed.
        @param _maxPlayersCount max quantity of players allowed to join the game
        @param _incentiveToken optional token address used to provide additional incentives to users. Accepts "0x0" adresses when no incentive token exists.
        @param _incentiveController matic reward claim contract.
        @param _matic matic token address.
     */
    constructor(
        IERC20 _inboundCurrency,
        ILendingPoolAddressesProvider _lendingPoolAddressProvider,
        uint256 _segmentCount,
        uint256 _segmentLength,
        uint256 _segmentPayment,
        uint256 _earlyWithdrawalFee,
        uint256 _customFee,
        address _dataProvider,
        uint256 _maxPlayersCount,
        IERC20 _incentiveToken,
        address _incentiveController,
        IERC20 _matic
    )
        public
        GoodGhosting(
            _inboundCurrency,
            _lendingPoolAddressProvider,
            _segmentCount,
            _segmentLength,
            _segmentPayment,
            _earlyWithdrawalFee,
            _customFee,
            _dataProvider,
            _maxPlayersCount,
            _incentiveToken
        )
    {
        require(_incentiveController != address(0), "invalid _incentiveController address");
        require(address(_matic) != address(0), "invalid _matic address");
        // initializing incentiveController contract
        incentiveController = IncentiveController(_incentiveController);
        matic = _matic;
    }

    /// @notice Allows the admin to withdraw the performance fee, if applicable. This function can be called only by the contract's admin.
    /// @dev Cannot be called before the game ends.
    function adminFeeWithdraw()
        external
        override
        onlyOwner
        whenGameIsCompleted
    {
        require(redeemed, "Funds not redeemed from external pool");
        require(!adminWithdraw, "Admin has already withdrawn");
        adminWithdraw = true;

        // when there are no winners, admin will be able to withdraw the
        // additional incentives sent to the pool, avoiding locking the funds.
        uint256 adminIncentiveAmount = 0;
        if (winners.length == 0 && totalIncentiveAmount > 0) {
            adminIncentiveAmount = totalIncentiveAmount;
        }

        emit AdminWithdrawal(owner(), totalGameInterest, adminFeeAmount, adminIncentiveAmount);

        if (adminFeeAmount > 0) {
            require(
                IERC20(daiToken).transfer(owner(), adminFeeAmount),
                "Fail to transfer ER20 tokens to admin"
            );
        }

        if (adminIncentiveAmount > 0) {
            require(
                IERC20(incentiveToken).transfer(owner(), adminIncentiveAmount),
                "Fail to transfer ER20 incentive tokens to admin"
            );
        }

        if (rewardsPerPlayer == 0) {
            uint256 balance = IERC20(matic).balanceOf(address(this));
            require(
                IERC20(matic).transfer(owner(), balance),
                "Fail to transfer ERC20 rewards tokens to admin"
            );
        }
    }

    /// @notice Allows player to withdraw their funds after the game ends with no loss (fee). Winners get a share of the interest earned.
    function withdraw() external override {
        Player storage player = players[msg.sender];
        require(player.amountPaid > 0, "Player does not exist");
        require(!player.withdrawn, "Player has already withdrawn");
        player.withdrawn = true;

        // First player to withdraw redeems everyone's funds
        if (!redeemed) {
            redeemFromExternalPool();
        }

        uint256 payout = player.amountPaid;
        uint256 playerIncentive = 0;
        uint256 playerReward = 0;
        if (player.mostRecentSegmentPaid == lastSegment.sub(1)) {
            // Player is a winner and gets a bonus!
            payout = payout.add(totalGameInterest.div(winners.length));
            playerReward = rewardsPerPlayer;
            // If there's additional incentives, distributes them to winners
            if (totalIncentiveAmount > 0) {
                playerIncentive = totalIncentiveAmount.div(winners.length);
            }
        }
        emit Withdrawal(msg.sender, payout, playerReward, playerIncentive);

        require(
            IERC20(daiToken).transfer(msg.sender, payout),
            "Fail to transfer ERC20 tokens on withdraw"
        );

        if (playerIncentive > 0) {
            require(
                IERC20(incentiveToken).transfer(msg.sender, playerIncentive),
                "Fail to transfer ERC20 incentive tokens on withdraw"
            );
        }

        if (playerReward > 0) {
            require(
                IERC20(matic).transfer(msg.sender, playerReward),
                "Fail to transfer ERC20 rewards on withdraw"
            );
        }
    }

    /// @notice Redeems funds from the external pool and updates the internal accounting controls related to the game stats.
    /// @dev Can only be called after the game is completed.
    function redeemFromExternalPool() public override whenGameIsCompleted {
        require(!redeemed, "Redeem operation already happened for the game");
        redeemed = true;
        // Withdraws funds (principal + interest + rewards) from external pool
        if (adaiToken.balanceOf(address(this)) > 0) {
            lendingPool.withdraw(
                address(daiToken),
                type(uint256).max,
                address(this)
            );
            // Claims the rewards from the external pool
            address[] memory assets = new address[](1);
            assets[0] = address(adaiToken);
            uint256 claimableRewards = incentiveController.getRewardsBalance(
                assets,
                address(this)
            );
            if (claimableRewards > 0) {
                incentiveController.claimRewards(
                    assets,
                    claimableRewards,
                    address(this)
                );
            }
        }

        uint256 totalBalance = IERC20(daiToken).balanceOf(address(this));
        uint256 rewardsAmount = IERC20(matic).balanceOf(address(this));
        // If there's an incentive token address defined, sets the total incentive amount to be distributed among winners.
        if (address(incentiveToken) != address(0)) {
            totalIncentiveAmount = IERC20(incentiveToken).balanceOf(address(this));
        }
        // calculates gross interest
        uint256 grossInterest = 0;
        // Sanity check to avoid reverting due to overflow in the "subtraction" below.
        // This could only happen in case Aave changes the 1:1 ratio between
        // aToken vs. Token in the future (i.e., 1 aDAI is worth less than 1 DAI)
        if (totalBalance > totalGamePrincipal) {
            grossInterest = totalBalance.sub(totalGamePrincipal);
        }
        // calculates the performance/admin fee (takes a cut - the admin percentage fee - from the pool's interest).
        // calculates the "gameInterest" (net interest) that will be split among winners in the game
        uint256 _adminFeeAmount;
        if (customFee > 0) {
            _adminFeeAmount = (grossInterest.mul(customFee)).div(100);
            totalGameInterest = grossInterest.sub(_adminFeeAmount);
        } else {
            _adminFeeAmount = 0;
            totalGameInterest = grossInterest;
        }

        // when there's no winners, admin takes all the interest + rewards
        if (winners.length == 0) {
            rewardsPerPlayer = 0;
            adminFeeAmount = grossInterest;
        } else {
            rewardsPerPlayer = rewardsAmount.div(winners.length);
            adminFeeAmount = _adminFeeAmount;
        }

        emit FundsRedeemedFromExternalPool(
            totalBalance,
            totalGamePrincipal,
            totalGameInterest,
            rewardsAmount,
            totalIncentiveAmount
        );
        emit WinnersAnnouncement(winners);
    }
}
