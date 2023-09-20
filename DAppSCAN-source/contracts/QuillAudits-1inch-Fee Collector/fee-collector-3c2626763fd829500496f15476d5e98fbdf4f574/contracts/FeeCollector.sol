// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./utils/BalanceAccounting.sol";


contract FeeCollector is Ownable, BalanceAccounting {
    using SafeERC20 for IERC20;

    struct EpochBalance {
        mapping(address => uint256) balances;
        uint256 totalSupply;
        uint256 tokenSpent;
        uint256 inchBalance;
    }

    struct TokenInfo {
        uint40 lastTime;
        uint216 lastValue;
        mapping(uint256 => EpochBalance) epochBalance;
        uint256 firstUnprocessedEpoch;
        uint256 currentEpoch;
        mapping(address => uint256) firstUserUnprocessedEpoch;
    }

    uint256 private immutable _k00;
    uint256 private immutable _k01;
    uint256 private immutable _k02;
    uint256 private immutable _k03;
    uint256 private immutable _k04;
    uint256 private immutable _k05;
    uint256 private immutable _k06;
    uint256 private immutable _k07;
    uint256 private immutable _k08;
    uint256 private immutable _k09;
    uint256 private immutable _k10;
    uint256 private immutable _k11;
    uint256 private immutable _k12;
    uint256 private immutable _k13;
    uint256 private immutable _k14;
    uint256 private immutable _k15;
    uint256 private immutable _k16;
    uint256 private immutable _k17;
    uint256 private immutable _k18;
    uint256 private immutable _k19;

    uint256 private constant _MAX_TIME = 0xfffff;

    mapping(IERC20 => TokenInfo) public tokenInfo;
    IERC20 public immutable token;
    uint256 public immutable minValue;
    uint8 public immutable decimals;

    constructor(
        IERC20 _token,
        uint256 _minValue,
        uint256 _deceleration
    ) {
        require(_deceleration > 0 && _deceleration < 1e36, "Invalid deceleration");

        token = _token;
        minValue = _minValue;
        decimals = IERC20Metadata(address(_token)).decimals();

        uint256 z;
        _k00 = z = _deceleration;
        _k01 = z = z * z / 1e36;
        _k02 = z = z * z / 1e36;
        _k03 = z = z * z / 1e36;
        _k04 = z = z * z / 1e36;
        _k05 = z = z * z / 1e36;
        _k06 = z = z * z / 1e36;
        _k07 = z = z * z / 1e36;
        _k08 = z = z * z / 1e36;
        _k09 = z = z * z / 1e36;
        _k10 = z = z * z / 1e36;
        _k11 = z = z * z / 1e36;
        _k12 = z = z * z / 1e36;
        _k13 = z = z * z / 1e36;
        _k14 = z = z * z / 1e36;
        _k15 = z = z * z / 1e36;
        _k16 = z = z * z / 1e36;
        _k17 = z = z * z / 1e36;
        _k18 = z = z * z / 1e36;
        _k19 = z = z * z / 1e36;
        require(z * z < 1e36, "Deceleration is too slow");
    }

    function name() external view returns(string memory) {
        return string(abi.encodePacked("FeeCollector: ", IERC20Metadata(address(token)).name()));
    }

    function symbol() external view returns(string memory) {
        return string(abi.encodePacked("fee-", IERC20Metadata(address(token)).symbol()));
    }

    function getEpochBalance(IERC20 _token, uint256 epoch) external view returns(uint256 totalSupply, uint256 tokenSpent, uint256 inchBalance) {
        EpochBalance storage epochBalance = tokenInfo[_token].epochBalance[epoch];
        (totalSupply, tokenSpent, inchBalance) = (epochBalance.totalSupply, epochBalance.tokenSpent, epochBalance.inchBalance);
    }

    function getUserEpochBalance(IERC20 _token, uint256 epoch, address user) external view returns(uint256 balance) {
        balance = tokenInfo[_token].epochBalance[epoch].balances[user];
    }

    function getFirstUserUnprocessedEpoch(IERC20 _token, address user) external view returns(uint256 firstUserUnprocessedEpoch) {
        firstUserUnprocessedEpoch = tokenInfo[_token].firstUserUnprocessedEpoch[user];
    }

    function decelerationTable() public view returns(uint256[20] memory) {
        return [
            _k00, _k01, _k02, _k03, _k04,
            _k05, _k06, _k07, _k08, _k09,
            _k10, _k11, _k12, _k13, _k14,
            _k15, _k16, _k17, _k18, _k19
        ];
    }

    function value(IERC20 _token) public view returns(uint256 result) {
        return valueForTime(block.timestamp, _token);
    }

    function valueForTimeSimple(uint256 time, IERC20 _token) public view returns(uint256 result) {
        uint256[20] memory table = decelerationTable();
        uint256 lastTime = tokenInfo[_token].lastTime;
        uint256 lastValue = tokenInfo[_token].lastValue;
        uint256 secs = Math.min(time - lastTime, _MAX_TIME);
        result = Math.max(lastValue, minValue);
        for (uint i = 0; secs > 0 && i < table.length; i++) {
            if (secs & 1 != 0) {
                result = result * table[i] / 1e36;
            }
            if (result < minValue) return minValue;
            secs >>= 1;
        }
    }

    function valueForTime(uint256 time, IERC20 _token) public view returns(uint256 result) {
        uint256 secs = tokenInfo[_token].lastTime;
        result = tokenInfo[_token].lastValue;

        secs = time - secs;
        if (secs > _MAX_TIME) {
            secs = _MAX_TIME;
        }
        if (result < minValue) {
            result = minValue;
        }

        uint256 minValue_ = minValue;
        assembly { // solhint-disable-line no-inline-assembly
            if and(secs, 0x00000F) {
                if and(secs, 0x000001) {
                    result := div(mul(result, 999900000000000000000000000000000000), 1000000000000000000000000000000000000)
                    if lt(result, minValue_) {
                        result := minValue_
                        secs := 0
                    }
                }

                if and(secs, 0x000002) {
                    result := div(mul(result, 999800010000000000000000000000000000), 1000000000000000000000000000000000000)
                    if lt(result, minValue_) {
                        result := minValue_
                        secs := 0
                    }
                }

                if and(secs, 0x000004) {
                    result := div(mul(result, 999600059996000100000000000000000000), 1000000000000000000000000000000000000)
                    if lt(result, minValue_) {
                        result := minValue_
                        secs := 0
                    }
                }

                if and(secs, 0x000008) {
                    result := div(mul(result, 999200279944006999440027999200010000), 1000000000000000000000000000000000000)
                    if lt(result, minValue_) {
                        result := minValue_
                        secs := 0
                    }
                }
            }

            if and(secs, 0x0000F0) {
                if and(secs, 0x000010) {
                    result := div(mul(result, 998401199440181956328006856128688560), 1000000000000000000000000000000000000)
                    if lt(result, minValue_) {
                        result := minValue_
                        secs := 0
                    }
                }

                if and(secs, 0x000020) {
                    result := div(mul(result, 996804955043593987145855519554957648), 1000000000000000000000000000000000000)
                    if lt(result, minValue_) {
                        result := minValue_
                        secs := 0
                    }
                }

                if and(secs, 0x000040) {
                    result := div(mul(result, 993620118399461429792290614928235372), 1000000000000000000000000000000000000)
                    if lt(result, minValue_) {
                        result := minValue_
                        secs := 0
                    }
                }

                if and(secs, 0x000080) {
                    result := div(mul(result, 987280939688159750172898466482272707), 1000000000000000000000000000000000000)
                    if lt(result, minValue_) {
                        result := minValue_
                        secs := 0
                    }
                }
            }

            if and(secs, 0x000F00) {
                if and(secs, 0x000100) {
                    result := div(mul(result, 974723653871535730138973062438582481), 1000000000000000000000000000000000000)
                    if lt(result, minValue_) {
                        result := minValue_
                        secs := 0
                    }
                }

                if and(secs, 0x000200) {
                    result := div(mul(result, 950086201416677390961738571086337286), 1000000000000000000000000000000000000)
                    if lt(result, minValue_) {
                        result := minValue_
                        secs := 0
                    }
                }

                if and(secs, 0x000400) {
                    result := div(mul(result, 902663790122371280016479918855854806), 1000000000000000000000000000000000000)
                    if lt(result, minValue_) {
                        result := minValue_
                        secs := 0
                    }
                }

                if and(secs, 0x000800) {
                    result := div(mul(result, 814801917998084346828628782199508463), 1000000000000000000000000000000000000)
                    if lt(result, minValue_) {
                        result := minValue_
                        secs := 0
                    }
                }
            }

            if and(secs, 0x00F000) {
                if and(secs, 0x001000) {
                    result := div(mul(result, 663902165573356968243491567819400493), 1000000000000000000000000000000000000)
                    if lt(result, minValue_) {
                        result := minValue_
                        secs := 0
                    }
                }

                if and(secs, 0x002000) {
                    result := div(mul(result, 440766085452993090398118811102456830), 1000000000000000000000000000000000000)
                    if lt(result, minValue_) {
                        result := minValue_
                        secs := 0
                    }
                }

                if and(secs, 0x004000) {
                    result := div(mul(result, 194274742085555207178862579417407102), 1000000000000000000000000000000000000)
                    if lt(result, minValue_) {
                        result := minValue_
                        secs := 0
                    }
                }

                if and(secs, 0x008000) {
                    result := div(mul(result, 37742675412408995610179844414960649), 1000000000000000000000000000000000000)
                    if lt(result, minValue_) {
                        result := minValue_
                        secs := 0
                    }
                }
            }

            if and(secs, 0x0F0000) {
                if and(secs, 0x010000) {
                    result := div(mul(result, 1424509547286462546864068778806188), 1000000000000000000000000000000000000)
                    if lt(result, minValue_) {
                        result := minValue_
                        secs := 0
                    }
                }

                if and(secs, 0x020000) {
                    result := div(mul(result, 2029227450310282474813662564103), 1000000000000000000000000000000000000)
                    if lt(result, minValue_) {
                        result := minValue_
                        secs := 0
                    }
                }

                if and(secs, 0x040000) {
                    result := div(mul(result, 4117764045092769930387910), 1000000000000000000000000000000000000)
                    if lt(result, minValue_) {
                        result := minValue_
                        secs := 0
                    }
                }

                if and(secs, 0x080000) {
                    result := div(mul(result, 16955980731058), 1000000000000000000000000000000000000)
                    if lt(result, minValue_) {
                        result := minValue_
                        secs := 0
                    }
                }
            }
        }
    }

    function updateRewards(address[] calldata receivers, uint256[] calldata amounts) external {
        for (uint i = 0; i < receivers.length; i++) {
            _updateReward(IERC20(msg.sender), receivers[i], amounts[i]);
        }
    }

    function updateReward(address referral, uint256 amount) external {
        _updateReward(IERC20(msg.sender), referral, amount);
    }

    // SWC-107-Reentrancy: L340 - L343
    function updateRewardNonLP(IERC20 erc20, address referral, uint256 amount) external {
        erc20.safeTransferFrom(msg.sender, address(this), amount);
        _updateReward(erc20, referral, amount);
    }

    function trade(IERC20 erc20, uint256 amount) external {
        TokenInfo storage _token = tokenInfo[erc20];
        uint256 currentEpoch = _token.currentEpoch;
        uint256 firstUnprocessedEpoch = _token.firstUnprocessedEpoch;
        EpochBalance storage epochBalance = _token.epochBalance[firstUnprocessedEpoch];
        EpochBalance storage currentEpochBalance = _token.epochBalance[currentEpoch];

        uint256 currentEpochStored = currentEpoch;

        uint256 unprocessedTotalSupply = epochBalance.totalSupply;
        uint256 unprocessedTokenBalance = unprocessedTotalSupply - epochBalance.tokenSpent;
        uint256 tokenBalance = unprocessedTokenBalance;
        if (firstUnprocessedEpoch != currentEpoch) {
            tokenBalance += currentEpochBalance.totalSupply - currentEpochBalance.tokenSpent;
        }

        // SWC-114-Transaction Order Dependence: L361
        uint256 returnAmount = amount * tokenBalance / value(erc20);
        require(tokenBalance >= returnAmount, "not enough tokens");

        if (firstUnprocessedEpoch == currentEpoch) {
            currentEpoch += 1;
        }

        _updateTokenState(erc20, -int256(returnAmount), currentEpochStored, firstUnprocessedEpoch);

        if (returnAmount <= unprocessedTokenBalance) {
            if (returnAmount == unprocessedTokenBalance) {
                _token.firstUnprocessedEpoch += 1;
            }

            epochBalance.tokenSpent += returnAmount;
            epochBalance.inchBalance += amount;
        } else {
            uint256 amountPart = unprocessedTokenBalance * amount / returnAmount;

            epochBalance.tokenSpent = unprocessedTotalSupply;
            epochBalance.inchBalance += amountPart;

            currentEpochBalance.tokenSpent += returnAmount - unprocessedTokenBalance;
            currentEpochBalance.inchBalance += amount - amountPart;

            _token.firstUnprocessedEpoch += 1;
            currentEpoch += 1;
        }

        if (currentEpoch != currentEpochStored) {
            _token.currentEpoch = currentEpoch;
        }

        token.safeTransferFrom(msg.sender, address(this), amount);
        erc20.safeTransfer(msg.sender, returnAmount);
    }

    function claim(IERC20[] memory pools) external {
        for (uint256 i = 0; i < pools.length; ++i) {
            TokenInfo storage _token = tokenInfo[pools[i]];
            _collectProcessedEpochs(msg.sender, _token, _token.currentEpoch, _token.firstUnprocessedEpoch);
        }

        uint256 userBalance = balanceOf(msg.sender);
        if (userBalance > 1) {
            // Avoid erasing storage to decrease gas footprint for referral payments
            unchecked {
                uint256 withdrawn = userBalance - 1;
                _burn(msg.sender, withdrawn);
                token.safeTransfer(msg.sender, withdrawn);
            }
        }
    }

    function claimCurrentEpoch(IERC20 erc20) external {
        TokenInfo storage _token = tokenInfo[erc20];
        uint256 currentEpoch = _token.currentEpoch;
        uint256 userBalance = _token.epochBalance[currentEpoch].balances[msg.sender];
        if (userBalance > 0) {
            _token.epochBalance[currentEpoch].balances[msg.sender] = 0;
            _token.epochBalance[currentEpoch].totalSupply -= userBalance;
            erc20.safeTransfer(msg.sender, userBalance);
        }
    }

    function claimFrozenEpoch(IERC20 erc20) external {
        TokenInfo storage _token = tokenInfo[erc20];
        uint256 firstUnprocessedEpoch = _token.firstUnprocessedEpoch;
        uint256 currentEpoch = _token.currentEpoch;

        require(firstUnprocessedEpoch + 1 == currentEpoch, "Epoch already finalized");
        require(_token.firstUserUnprocessedEpoch[msg.sender] == firstUnprocessedEpoch, "Epoch funds already claimed");

        _token.firstUserUnprocessedEpoch[msg.sender] = currentEpoch;
        EpochBalance storage epochBalance = _token.epochBalance[firstUnprocessedEpoch];
        uint256 share = epochBalance.balances[msg.sender];

        if (share > 0) {
            uint256 totalSupply = epochBalance.totalSupply;
            epochBalance.balances[msg.sender] = 0;
            epochBalance.totalSupply = totalSupply - share;
            epochBalance.inchBalance -= _transferTokenShare(token, epochBalance.inchBalance, share, totalSupply);
            _transferTokenShare(erc20, epochBalance.tokenSpent, share, totalSupply);
        }
    }

    function _updateReward(IERC20 erc20, address referral, uint256 amount) private {
        TokenInfo storage _token = tokenInfo[erc20];
        uint256 currentEpoch = _token.currentEpoch;
        uint256 firstUnprocessedEpoch = _token.firstUnprocessedEpoch;

        _updateTokenState(erc20, int256(amount), currentEpoch, firstUnprocessedEpoch);

        // Add new reward to current epoch
        _token.epochBalance[currentEpoch].balances[referral] += amount;
        _token.epochBalance[currentEpoch].totalSupply += amount;

        // Collect all processed epochs and advance user token epoch
        _collectProcessedEpochs(referral, _token, currentEpoch, firstUnprocessedEpoch);
    }

    function _updateTokenState(IERC20 erc20, int256 amount, uint256 currentEpoch, uint256 firstUnprocessedEpoch) private {
        TokenInfo storage _token = tokenInfo[erc20];

        uint256 fee = _token.epochBalance[firstUnprocessedEpoch].totalSupply - _token.epochBalance[firstUnprocessedEpoch].tokenSpent;
        if (firstUnprocessedEpoch != currentEpoch) {
            fee += (_token.epochBalance[currentEpoch].totalSupply - _token.epochBalance[currentEpoch].tokenSpent);
        }

        uint256 feeWithAmount = (amount >= 0 ? fee + uint256(amount) : fee - uint256(-amount));
        (
            tokenInfo[erc20].lastTime,
            tokenInfo[erc20].lastValue
        ) = (
            uint40(block.timestamp),
            uint216(valueForTime(block.timestamp, erc20) * feeWithAmount / (fee == 0 ? 1 : fee))
        );
    }

    function _transferTokenShare(IERC20 _token, uint256 balance, uint256 share, uint256 totalSupply) private returns(uint256 amount) {
        amount = balance * share / totalSupply;
        if (amount > 0) {
            _token.safeTransfer(msg.sender, amount);
        }
    }

    function _collectProcessedEpochs(address user, TokenInfo storage _token, uint256 currentEpoch, uint256 tokenEpoch) private {
        uint256 userEpoch = _token.firstUserUnprocessedEpoch[user];

        if (tokenEpoch <= userEpoch) {
            return;
        }

        // Early return for the new users
        if (_token.epochBalance[userEpoch].balances[user] == 0) {
            _token.firstUserUnprocessedEpoch[user] = currentEpoch;
            return;
        }

        uint256 epochCount = Math.min(2, tokenEpoch - userEpoch); // 0, 1 or 2 epochs

        // Claim 1 or 2 processed epochs for the user
        uint256 collected = _collectEpoch(user, _token, userEpoch);
        if (epochCount > 1) {
            collected += _collectEpoch(user, _token, userEpoch + 1);
        }
        _mint(user, collected);

        // Update user token epoch counter
        bool emptySecondEpoch = _token.epochBalance[userEpoch + 1].balances[user] == 0;
        _token.firstUserUnprocessedEpoch[user] = (epochCount == 2 || emptySecondEpoch) ? currentEpoch : userEpoch + 1;
    }

    function _collectEpoch(address user, TokenInfo storage _token, uint256 epoch) private returns(uint256 collected) {
        uint256 share = _token.epochBalance[epoch].balances[user];
        if (share > 0) {
            uint256 inchBalance = _token.epochBalance[epoch].inchBalance;
            uint256 totalSupply = _token.epochBalance[epoch].totalSupply;

            collected = inchBalance * share / totalSupply;

            _token.epochBalance[epoch].balances[user] = 0;
            _token.epochBalance[epoch].totalSupply = totalSupply - share;
            _token.epochBalance[epoch].inchBalance = inchBalance - collected;
        }
    }
}
