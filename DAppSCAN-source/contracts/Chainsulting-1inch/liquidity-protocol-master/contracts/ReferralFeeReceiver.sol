// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IFeeCollector.sol";
import "./libraries/UniERC20.sol";
import "./utils/Converter.sol";

/// @title Referral fee collector
// SWC-107-Reentrancy: L11
contract ReferralFeeReceiver is IFeeCollector, Converter, ReentrancyGuard {
    using UniERC20 for IERC20;

    struct UserInfo {
        uint256 balance;
        mapping(IERC20 => mapping(uint256 => uint256)) share;
        mapping(IERC20 => uint256) firstUnprocessedEpoch;
    }

    struct EpochBalance {
        uint256 totalSupply;
        uint256 token0Balance;
        uint256 token1Balance;
        uint256 inchBalance;
    }

    struct TokenInfo {
        mapping(uint256 => EpochBalance) epochBalance;
        uint256 firstUnprocessedEpoch;
        uint256 currentEpoch;
    }

    mapping(address => UserInfo) public userInfo;
    mapping(IERC20 => TokenInfo) public tokenInfo;

    // solhint-disable-next-line no-empty-blocks
    constructor(IERC20 _inchToken, IMooniswapFactory _mooniswapFactory) public Converter(_inchToken, _mooniswapFactory) {}

    /// @inheritdoc IFeeCollector
    function updateRewards(address[] calldata receivers, uint256[] calldata amounts) external override {
        for (uint i = 0; i < receivers.length; i++) {
            updateReward(receivers[i], amounts[i]);
        }
    }

    /// @inheritdoc IFeeCollector
    function updateReward(address referral, uint256 amount) public override {
        Mooniswap mooniswap = Mooniswap(msg.sender);
        TokenInfo storage token = tokenInfo[mooniswap];
        UserInfo storage user = userInfo[referral];
        uint256 currentEpoch = token.currentEpoch;

        // Add new reward to current epoch
        user.share[mooniswap][currentEpoch] = user.share[mooniswap][currentEpoch].add(amount);
        token.epochBalance[currentEpoch].totalSupply = token.epochBalance[currentEpoch].totalSupply.add(amount);

        // Collect all processed epochs and advance user token epoch
        _collectProcessedEpochs(user, token, mooniswap, currentEpoch);
    }

    /// @notice Freezes current epoch and creates new as an active one
    function freezeEpoch(Mooniswap mooniswap) external nonReentrant validPool(mooniswap) validSpread(mooniswap) {
        TokenInfo storage token = tokenInfo[mooniswap];
        uint256 currentEpoch = token.currentEpoch;
        require(token.firstUnprocessedEpoch == currentEpoch, "Previous epoch is not finalized");

        IERC20[] memory tokens = mooniswap.getTokens();
        uint256 token0Balance = tokens[0].uniBalanceOf(address(this));
        uint256 token1Balance = tokens[1].uniBalanceOf(address(this));
        mooniswap.withdraw(mooniswap.balanceOf(address(this)), new uint256[](0));
        token.epochBalance[currentEpoch].token0Balance = tokens[0].uniBalanceOf(address(this)).sub(token0Balance);
        token.epochBalance[currentEpoch].token1Balance = tokens[1].uniBalanceOf(address(this)).sub(token1Balance);
        token.currentEpoch = currentEpoch.add(1);
    }

    /// @notice Perform chain swap described by `path`. First element of `path` should match either token of the `mooniswap`.
    /// The last token in chain should always be `1INCH`
    function trade(Mooniswap mooniswap, IERC20[] memory path) external nonReentrant validPool(mooniswap) validPath(path) {
        TokenInfo storage token = tokenInfo[mooniswap];
        uint256 firstUnprocessedEpoch = token.firstUnprocessedEpoch;
        EpochBalance storage epochBalance = token.epochBalance[firstUnprocessedEpoch];
        require(firstUnprocessedEpoch.add(1) == token.currentEpoch, "Prev epoch already finalized");

        IERC20[] memory tokens = mooniswap.getTokens();
        uint256 availableBalance;
        if (path[0] == tokens[0]) {
            availableBalance = epochBalance.token0Balance;
        } else if (path[0] == tokens[1]) {
            availableBalance = epochBalance.token1Balance;
        } else {
            revert("Invalid first token");
        }

        (uint256 amount, uint256 returnAmount) = _maxAmountForSwap(path, availableBalance);
        if (returnAmount == 0) {
            // get rid of dust
            if (availableBalance > 0) {
                require(availableBalance == amount, "availableBalance is not dust");
                for (uint256 i = 0; i + 1 < path.length; i += 1) {
                    Mooniswap _mooniswap = mooniswapFactory.pools(path[i], path[i+1]);
                    require(_validateSpread(_mooniswap), "Spread is too high");
                }
                if (path[0].isETH()) {
                    tx.origin.transfer(availableBalance);  // solhint-disable-line avoid-tx-origin
                } else {
                    path[0].safeTransfer(address(mooniswap), availableBalance);
                }
            }
        } else {
            uint256 receivedAmount = _swap(path, amount, payable(address(this)));
            epochBalance.inchBalance = epochBalance.inchBalance.add(receivedAmount);
        }

        if (path[0] == tokens[0]) {
            epochBalance.token0Balance = epochBalance.token0Balance.sub(amount);
        } else {
            epochBalance.token1Balance = epochBalance.token1Balance.sub(amount);
        }

        if (epochBalance.token0Balance == 0 && epochBalance.token1Balance == 0) {
            token.firstUnprocessedEpoch = firstUnprocessedEpoch.add(1);
        }
    }

    /// @notice Collects `msg.sender`'s tokens from pools and transfers them to him
    function claim(Mooniswap[] memory pools) external {
        UserInfo storage user = userInfo[msg.sender];
        for (uint256 i = 0; i < pools.length; ++i) {
            Mooniswap mooniswap = pools[i];
            TokenInfo storage token = tokenInfo[mooniswap];
            _collectProcessedEpochs(user, token, mooniswap, token.currentEpoch);
        }

        uint256 balance = user.balance;
        if (balance > 1) {
            // Avoid erasing storage to decrease gas footprint for referral payments
            user.balance = 1;
            inchToken.transfer(msg.sender, balance - 1);
        }
    }

    /// @notice Collects current epoch `msg.sender`'s tokens from pool and transfers them to him
    function claimCurrentEpoch(Mooniswap mooniswap) external nonReentrant validPool(mooniswap) {
        TokenInfo storage token = tokenInfo[mooniswap];
        UserInfo storage user = userInfo[msg.sender];
        uint256 currentEpoch = token.currentEpoch;
        uint256 balance = user.share[mooniswap][currentEpoch];
        if (balance > 0) {
            user.share[mooniswap][currentEpoch] = 0;
            token.epochBalance[currentEpoch].totalSupply = token.epochBalance[currentEpoch].totalSupply.sub(balance);
            mooniswap.transfer(msg.sender, balance);
        }
    }

    /// @notice Collects frozen epoch `msg.sender`'s tokens from pool and transfers them to him
    function claimFrozenEpoch(Mooniswap mooniswap) external nonReentrant validPool(mooniswap) {
        TokenInfo storage token = tokenInfo[mooniswap];
        UserInfo storage user = userInfo[msg.sender];
        uint256 firstUnprocessedEpoch = token.firstUnprocessedEpoch;
        uint256 currentEpoch = token.currentEpoch;

        require(firstUnprocessedEpoch.add(1) == currentEpoch, "Epoch already finalized");
        require(user.firstUnprocessedEpoch[mooniswap] == firstUnprocessedEpoch, "Epoch funds already claimed");

        user.firstUnprocessedEpoch[mooniswap] = currentEpoch;
        uint256 share = user.share[mooniswap][firstUnprocessedEpoch];

        if (share > 0) {
            EpochBalance storage epochBalance = token.epochBalance[firstUnprocessedEpoch];
            uint256 totalSupply = epochBalance.totalSupply;
            user.share[mooniswap][firstUnprocessedEpoch] = 0;
            epochBalance.totalSupply = totalSupply.sub(share);

            IERC20[] memory tokens = mooniswap.getTokens();
            epochBalance.token0Balance = _transferTokenShare(tokens[0], epochBalance.token0Balance, share, totalSupply);
            epochBalance.token1Balance = _transferTokenShare(tokens[1], epochBalance.token1Balance, share, totalSupply);
            epochBalance.inchBalance = _transferTokenShare(inchToken, epochBalance.inchBalance, share, totalSupply);
        }
    }

    function _transferTokenShare(IERC20 token, uint256 balance, uint256 share, uint256 totalSupply) private returns(uint256 newBalance) {
        uint256 amount = balance.mul(share).div(totalSupply);
        if (amount > 0) {
            token.uniTransfer(msg.sender, amount);
        }
        return balance.sub(amount);
    }

    function _collectProcessedEpochs(UserInfo storage user, TokenInfo storage token, Mooniswap mooniswap, uint256 currentEpoch) private {
        uint256 userEpoch = user.firstUnprocessedEpoch[mooniswap];

        // Early return for the new users
        if (user.share[mooniswap][userEpoch] == 0) {
            user.firstUnprocessedEpoch[mooniswap] = currentEpoch;
            return;
        }

        uint256 tokenEpoch = token.firstUnprocessedEpoch;
        if (tokenEpoch <= userEpoch) {
            return;
        }
        uint256 epochCount = Math.min(2, tokenEpoch - userEpoch); // 0, 1 or 2 epochs

        // Claim 1 or 2 processed epochs for the user
        uint256 collected = _collectEpoch(user, token, mooniswap, userEpoch);
        if (epochCount > 1) {
            collected = collected.add(_collectEpoch(user, token, mooniswap, userEpoch + 1));
        }
        user.balance = user.balance.add(collected);

        // Update user token epoch counter
        bool emptySecondEpoch = user.share[mooniswap][userEpoch + 1] == 0;
        user.firstUnprocessedEpoch[mooniswap] = (epochCount == 2 || emptySecondEpoch) ? currentEpoch : userEpoch + 1;
    }

    function _collectEpoch(UserInfo storage user, TokenInfo storage token, Mooniswap mooniswap, uint256 epoch) private returns(uint256 collected) {
        uint256 share = user.share[mooniswap][epoch];
        if (share > 0) {
            uint256 inchBalance = token.epochBalance[epoch].inchBalance;
            uint256 totalSupply = token.epochBalance[epoch].totalSupply;

            collected = inchBalance.mul(share).div(totalSupply);

            user.share[mooniswap][epoch] = 0;
            token.epochBalance[epoch].totalSupply = totalSupply.sub(share);
            token.epochBalance[epoch].inchBalance = inchBalance.sub(collected);
        }
    }
}
