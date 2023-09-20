// SPDX-License-Identifier: MIT
pragma solidity ^0.6.6;

import "https://github.com/Woonkly/OpenZeppelinBaseContracts/contracts/math/SafeMath.sol";
import "https://github.com/Woonkly/OpenZeppelinBaseContracts/contracts/token/ERC20/ERC20.sol";
import "https://github.com/Woonkly/OpenZeppelinBaseContracts/contracts/utils/ReentrancyGuard.sol";
import "https://github.com/Woonkly/MartinHSolUtils/Utils.sol";
import "https://github.com/Woonkly/STAKESmartContractPreRelease/Pausabled.sol";
import "https://github.com/Woonkly/STAKESmartContractPreRelease/Erc20Manager.sol";
import "https://github.com/Woonkly/STAKESmartContractPreRelease/StakeManager.sol";
import "https://github.com/Woonkly/STAKESmartContractPreRelease/IWStaked.sol";
import "https://github.com/Woonkly/STAKESmartContractPreRelease/IInvestiable.sol";

/**
MIT License

Copyright (c) 2021 Woonkly OU

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED BY WOONKLY OU "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

contract WOOPStake is Owners, Pausabled, Erc20Manager, ReentrancyGuard {
    using SafeMath for uint256;

    //Section Type declarations
    struct Stake {
        address account;
        uint256 bal;
        bool autoCompound;
        uint8 flag; //0 no exist  1 exist 2 deleted
    }

    struct processRewardInfo {
        uint256 remainder;
        uint256 woopsRewards;
        uint256 dealed;
        address me;
        bool resp;
    }

    struct Stadistic {
        uint256 ind;
        uint256 funds;
        uint256 rews;
        uint256 rewsCOIN;
        uint256 autocs;
    }

    //Section State variables

    address internal _remainder;
    address internal _woopERC20;
    uint256 internal _distributedCOIN;
    IInvestable internal _inv;
    IWStaked internal _stakes;
    address internal _investable;
    address internal _stakeable;
    uint256 _factor;
    mapping(address => mapping(address => uint256)) private _rewards;
    mapping(address => uint256) private _rewardsCOIN;
    mapping(address => uint256) private _distributeds;

    //Section Modifier

    modifier IhaveEnoughTokens(address sc, uint256 token_amount) {
        uint256 amount = getMyTokensBalance(sc);
        require(token_amount <= amount, "-tk");
        _;
    }

    modifier IhaveEnoughCoins(uint256 coins) {
        uint256 amount = getMyCoinBalance();
        require(coins <= amount, "-coin");
        _;
    }

    modifier hasApprovedTokens(
        address sc,
        address sender,
        uint256 token_amount
    ) {
        IERC20 _token = IERC20(sc);
        require(
            _token.allowance(sender, address(this)) >= token_amount,
            "!aptk"
        ); //sender != address(0) &&
        _;
    }

    modifier ProviderHasToken(address sc, uint256 amount) {
        uint256 total = calcTotalRewards(amount);
        require(total <= getTokensBalanceOf(sc, _msgSender()), "WOO:tk-");
        _;
    }

    modifier IhaveAprovedRewardTokens(address sc, uint256 amount) {
        uint256 total = calcTotalRewards(amount);
        IERC20 _token = IERC20(sc);
        require(
            _token.allowance(_msgSender(), address(this)) >= total,
            "WOO:-apt"
        );

        _;
    }

    modifier Solvency(address sc) {
        bool isSolvency;
        uint256 solvent;

        (isSolvency, solvent) = getSolvency(sc);

        require(isSolvency, "WO:sol!");
        _;
    }

    modifier SolvencyCOIN() {
        bool isSolvency;
        uint256 solvent;

        (isSolvency, solvent) = getSolvencyCOIN();

        require(isSolvency, "WO:sol!");
        _;
    }

    //Section Events

    event RewardedCOIN(address account, uint256 reward);
    event Rewarded(address sc, address account, uint256 reward);
    event CoinReceived(uint256 coins);
    event FactorChanged(uint256 oldf, uint256 newf);
    event DistributedReseted(address sc, uint256 old);
    event DistributedCOINReseted(uint256 old);
    event RemaninderAccChanged(address old, address newr);
    event ERC20WOOPChanged(address old, address newr);
    event VestingChanged(address old, address newi);
    event StakeAddrChanged(address old, address news);
    event WithdrawFunds(address account, uint256 amount, uint256 remainder);
    event RewardWithdrawed(
        address sc,
        address account,
        uint256 amount,
        uint256 remainder
    );
    event RewardToCompound(address account, uint256 amount);

    event RewardCOINWithdrawed(
        address account,
        uint256 amount,
        uint256 remainder
    );

    event InsuficientRewardFund(address sc, address account);
    event NewLeftover(address sc, address account, uint256 leftover);
    event InsuficientRewardFundCOIN(address account);
    event NewLeftoverCOIN(address account, uint256 leftover);

    event StakeClosed(
        uint256 csc,
        uint256 stakes,
        uint256 totFunds,
        uint256 totRew
    );

    //Section functions

    constructor(
        address remAcc,
        address woopERC20,
        address inv,
        address stake
    ) public {
        _paused = false;
        _remainder = remAcc;
        //_factor=10**8;
        //factor = 1000000000000000000;

        _factor = 100000000;
        _distributedCOIN = 0;
        _woopERC20 = woopERC20;
        _investable = inv;
        _inv = IInvestable(inv);
        _stakeable = stake;
        _stakes = IWStaked(stake);
    }

    function _dorewardCOIN(address account, uint256 reward) internal {
        require(account != address(0), "WO:0addr");

        _rewardsCOIN[account] = reward;
        emit RewardedCOIN(account, reward);
    }

    function rewardedCOIN(address account) public view returns (uint256) {
        return _rewardsCOIN[account];
    }

    function _rewardCOIN(address account, uint256 amount)
        internal
        returns (bool)
    {
        _dorewardCOIN(account, amount);
        return true;
    }

    function _increaseRewardsCOIN(address account, uint256 addedValue)
        internal
        returns (bool)
    {
        _dorewardCOIN(account, _rewardsCOIN[account].add(addedValue));
        return true;
    }

    function _decreaseRewardsCOIN(address account, uint256 subtractedValue)
        internal
        returns (bool)
    {
        _dorewardCOIN(
            account,
            _rewardsCOIN[account].sub(subtractedValue, "WO:-0")
        );
        return true;
    }

    function _doreward(
        address sc,
        address account,
        uint256 reward
    ) internal {
        require(sc != address(0), "WO:0addr");
        require(account != address(0), "WO:0addr");

        _rewards[sc][account] = reward;
        emit Rewarded(sc, account, reward);
    }

    function rewarded(address sc, address account)
        public
        view
        returns (uint256)
    {
        return _rewards[sc][account];
    }

    function _reward(
        address sc,
        address account,
        uint256 amount
    ) internal returns (bool) {
        _doreward(sc, account, amount);
        return true;
    }

    function _increaseRewards(
        address sc,
        address account,
        uint256 addedValue
    ) internal returns (bool) {
        _doreward(sc, account, _rewards[sc][account].add(addedValue));
        return true;
    }

    function _decreaseRewards(
        address sc,
        address account,
        uint256 subtractedValue
    ) internal returns (bool) {
        _doreward(
            sc,
            account,
            _rewards[sc][account].sub(subtractedValue, "WO:-0")
        );
        return true;
    }

    receive() external payable {
        // React to receiving ether
        _processRewardCOIN(msg.value);

        emit CoinReceived(msg.value);
    }

    fallback() external payable {
        //emit CoinReceived(msg.value);
    }

    function getMyCoinBalance() public view returns (uint256) {
        address payable self = address(this);
        uint256 bal = self.balance;
        return bal;
    }

    function getMyTokensBalance(address sc) public view returns (uint256) {
        IERC20 _token = IERC20(sc);
        return _token.balanceOf(address(this));
    }

    function getTokensBalanceOf(address sc, address account)
        public
        view
        returns (uint256)
    {
        IERC20 _token = IERC20(sc);
        return _token.balanceOf(account);
    }

    function addErc20STK(address sc) public onlyIsInOwners returns (bool) {
        newERC20(sc);
        return true;
    }

    function removeErc20STK(address sc) public onlyIsInOwners returns (bool) {
        removeERC20(sc);
        return true;
    }

    function setFactor(uint256 newf) public onlyIsInOwners {
        require(newf <= 1000000000, ">lim");
        emit FactorChanged(_factor, newf);
        _factor = newf;
    }

    function getFactor() public view returns (uint256) {
        return _factor;
    }

    function getfractionUnit() public view returns (uint256) {
        return uint256(1000000000000000000000000000).div(_factor);
    }

    function getDistributed(address sc) public view returns (uint256) {
        return _distributeds[sc];
    }

    function resetDistributed(address sc) public onlyIsInOwners returns (bool) {
        uint256 old = _distributeds[sc];
        _distributeds[sc] = 0;
        emit DistributedReseted(sc, old);
        return true;
    }

    function getDistributedCOIN() public view returns (uint256) {
        return _distributedCOIN;
    }

    function resetDistributedCOIN() public onlyIsInOwners returns (bool) {
        uint256 old = _distributedCOIN;
        _distributedCOIN = 0;
        emit DistributedCOINReseted(old);
        return true;
    }

    function getRemaninderAcc() public view returns (address) {
        return _remainder;
    }

    function setRemaniderAcc(address newr)
        public
        onlyIsInOwners
        returns (bool)
    {
        require(newr != address(0), "!0ad");
        address old = _remainder;
        _remainder = newr;
        emit RemaninderAccChanged(old, newr);
        return true;
    }

    function getERC20WOOP() public view returns (address) {
        return _woopERC20;
    }

    function setERC20WOOP(address newr) public onlyIsInOwners returns (bool) {
        require(newr != address(0), "!0ad");
        address old = _woopERC20;
        _woopERC20 = newr;
        emit ERC20WOOPChanged(old, newr);
        return true;
    }

    function getVesting() public view returns (address) {
        return _investable;
    }

    function setVesting(address newi) public onlyIsInOwners returns (bool) {
        require(newi != address(0), "!0ad");
        address old = _investable;
        _investable = newi;
        _inv = IInvestable(newi);
        emit VestingChanged(old, newi);
        return true;
    }

    function getStakeAddr() public view returns (address) {
        return _stakeable;
    }

    function setStakeAddr(address news) public onlyIsInOwners returns (bool) {
        require(news != address(0), "!0ad");
        address old = _stakeable;
        _stakeable = news;
        _stakes = IWStaked(news);
        emit StakeAddrChanged(old, news);
        return true;
    }

    function setMyCompoundStatus(bool status)
        public
        nonReentrant
        returns (bool)
    {
        require(_stakes.StakeExist(_msgSender()), "WO:!");
        _stakes.setAutoCompound(_msgSender(), status);
        if (status == true)
            _compoundReward(_msgSender(), rewarded(_woopERC20, _msgSender()));
        return true;
    }

    function addStake(uint256 amount)
        public
        Active
        hasApprovedTokens(_woopERC20, _msgSender(), amount)
        returns (bool)
    {
        require(amount >= getfractionUnit(), "WO:-am");

        IERC20 _token = IERC20(_woopERC20);

        require(
            _token.transferFrom(_msgSender(), address(this), amount),
            "WO:-etf"
        );

        require(_addStake(_msgSender(), amount), "WO:eas");

        return true;
    }

    function _addStake(address account, uint256 amount)
        internal
        Active
        returns (bool)
    {
        if (!_stakes.StakeExist(account)) {
            _stakes.newStake(account, amount);
        } else {
            _stakes.addToStake(account, amount);
        }

        return true;
    }

    function _withdrawFunds(address account, uint256 amount)
        internal
        Active
        returns (uint256)
    {
        require(_stakes.StakeExist(account), "WO:!");
        uint256 fund;
        bool autoC;

        (fund, autoC) = _stakes.getStake(account);

        require(amount <= fund, "WO:eef");

        uint256 remainder = fund.sub(amount);

        if (remainder == 0) {
            _stakes.removeStake(account);
        } else {
            _stakes.renewStake(account, remainder);
        }

        emit WithdrawFunds(account, amount, remainder);

        return amount;
    }

    function withdrawFunds(uint256 amount)
        public
        Active
        nonReentrant
        returns (bool)
    {
        require(_stakes.StakeExist(_msgSender()), "WO:!");
        require(
            _inv.canWithdrawFunds(
                _msgSender(),
                amount,
                _stakes.balanceOf(_msgSender())
            ),
            "WO:!i"
        );

        IERC20 _token = IERC20(_woopERC20);

        require(_token.transfer(_msgSender(), amount), "WO:ewf");
        _withdrawFunds(_msgSender(), amount);

        _inv.updateFund(_msgSender(), amount);
        return true;
    }

    function _withdrawReward(
        address sc,
        address account,
        uint256 amount
    ) internal Active nonReentrant returns (uint256) {
        IERC20 _token = IERC20(sc);

        uint256 rew = rewarded(sc, account);

        require(amount <= rew, "WO:amew");

        require(amount <= getMyTokensBalance(sc), "WO:-tk");

        require(_token.transfer(account, amount));

        uint256 remainder = rew.sub(amount);


        //fix critical issue by coin Fabrik
        _doreward(sc, account, remainder);


       emit RewardWithdrawed(sc, account, amount, remainder);

        return amount;
    }

    function _compoundReward(address account, uint256 amount)
        internal
        Active
        returns (uint256)
    {
        uint256 rew = rewarded(_woopERC20, account);

        require(amount <= rew, "WO: am>w");

        require(amount <= getMyTokensBalance(_woopERC20), "WO:-tk");

        uint256 remainder = rew.sub(amount);


        //fix critical issue by coin Fabrik
        _doreward(_woopERC20, account, remainder);


        _stakes.addToStake(account, amount);

        emit RewardToCompound(account, amount);

        return amount;
    }

    function WithdrawReward(address sc, uint256 amount)
        public
        Active
        returns (bool)
    {
        _withdrawReward(sc, _msgSender(), amount);

        return true;
    }

    function CompoundReward(uint256 amount)
        public
        Active
        nonReentrant
        returns (bool)
    {
        _compoundReward(_msgSender(), amount);

        return true;
    }

    function _withdrawRewardCOIN(address account, uint256 amount)
        internal
        Active
        nonReentrant
        returns (uint256)
    {
        uint256 rew = rewardedCOIN(account);

        require(amount <= rew, "WO:am++");

        require(amount <= getMyCoinBalance(), "WO:tk-");

        address payable acc = address(uint160(address(account)));

        acc.transfer(amount);

        uint256 remainder = rew.sub(amount);


        //fix critical issue by coin Fabrik
        _dorewardCOIN(account,remainder);

        emit RewardCOINWithdrawed(account, amount, remainder);

        return amount;
    }

    function WithdrawRewardCOIN(uint256 amount) public Active returns (bool) {
        _withdrawRewardCOIN(_msgSender(), amount);

        return true;
    }

    function getCalcRewardAmount(address account, uint256 amount)
        public
        view
        returns (uint256, uint256)
    {
        if (!_stakes.StakeExist(account)) return (0, 0);

        uint256 fund = 0;
        bool autoC;

        (fund, autoC) = _stakes.getStake(account);

        if (fund < getfractionUnit()) return (0, 0);

        uint256 factor = fund.div(getfractionUnit());

        if (factor < 1) return (0, 0);

        uint256 remainder = fund.sub(factor.mul(getfractionUnit()));

        uint256 woopsRewards = calcReward(amount, factor);

        if (woopsRewards < 1) return (0, 0);

        return (woopsRewards, remainder);
    }

    function calcReward(uint256 amount, uint256 factor)
        public
        view
        returns (uint256)
    {
        return amount.mul(factor).div(_factor);
    }

    function calcTotalRewards(uint256 amount) public view returns (uint256) {
        uint256 remainder;
        uint256 woopsRewards;
        uint256 ind = 0;
        uint256 total = 0;

        Stake memory p;

        uint256 last = _stakes.getLastIndexStakes();

        for (uint256 i = 0; i < (last + 1); i++) {
            (p.account, p.bal, p.autoCompound, p.flag) = _stakes
                .getStakeByIndex(i);

            if (p.flag == 1) {
                (woopsRewards, remainder) = getCalcRewardAmount(
                    p.account,
                    amount
                );
                if (woopsRewards > 0) {
                    total = total.add(woopsRewards);
                }
                ind++;
            }
        }

        return total;
    }

    function _processReward_1(
        IERC20 _token,
        address account,
        uint256 amount
    ) internal returns (bool) {
        require(_token.transferFrom(account, address(this), amount), "WO:etr");
        return true;
    }

    function _processReward_2(address sc, uint256 amount)
        internal
        returns (uint256)
    {
        processRewardInfo memory slot;

        Stake memory p;

        uint256 last = _stakes.getLastIndexStakes();

        for (uint256 i = 0; i < (last + 1); i++) {
            (p.account, p.bal, p.autoCompound, p.flag) = _stakes
                .getStakeByIndex(i);

            if (p.flag == 1) {
                (slot.woopsRewards, slot.remainder) = getCalcRewardAmount(
                    p.account,
                    amount
                );
                if (slot.woopsRewards > 0) {
                    if (
                        _stakes.getAutoCompoundStatus(p.account) &&
                        sc == _woopERC20
                    ) {
                        _stakes.addToStake(p.account, slot.woopsRewards);
                    } else {
                        _increaseRewards(sc, p.account, slot.woopsRewards);
                    }

                    slot.dealed = slot.dealed.add(slot.woopsRewards);
                } else {
                    emit InsuficientRewardFund(sc, p.account);
                }
            }
        } //for

        _distributeds[sc] = _distributeds[sc].add(slot.dealed);

        return slot.dealed;
    }

// SWC-107-Reentrancy: L743 - L769
    function processReward(address sc, uint256 amount)
        public
        nonReentrant
        Active
        hasApprovedTokens(sc, _msgSender(), amount)
        ProviderHasToken(sc, amount)
        returns (bool)
    {
        if (!ERC20Exist(sc)) {
            newERC20(sc);
        }

        processRewardInfo memory slot;

        IERC20 _token = IERC20(sc);
        _processReward_1(_token, _msgSender(), amount);

        slot.dealed = _processReward_2(sc, amount);

        uint256 leftover = amount.sub(slot.dealed);
        if (leftover > 0) {
            require(_token.transfer(_remainder, leftover), "WO:trf");
            emit NewLeftover(sc, _remainder, leftover);
        }

        return true;
    }

    function _processReward_2COIN(uint256 amount) internal returns (uint256) {
        processRewardInfo memory slot;
        Stake memory p;

        uint256 last = _stakes.getLastIndexStakes();

        for (uint256 i = 0; i < (last + 1); i++) {
            (p.account, p.bal, p.autoCompound, p.flag) = _stakes
                .getStakeByIndex(i);

            if (p.flag == 1) {
                (slot.woopsRewards, slot.remainder) = getCalcRewardAmount(
                    p.account,
                    amount
                );

                if (slot.woopsRewards > 0) {
                    _increaseRewardsCOIN(p.account, slot.woopsRewards);

                    slot.dealed = slot.dealed.add(slot.woopsRewards);
                } else {
                    emit InsuficientRewardFundCOIN(p.account);
                }
            }
        } //for

        return slot.dealed;
    }

    function _processRewardCOIN(uint256 amount)
        internal
        nonReentrant
        Active
        returns (bool)
    {
        processRewardInfo memory slot;

        address payable nrem = address(uint160(_remainder));

        slot.dealed = _processReward_2COIN(amount);

        _distributedCOIN = _distributedCOIN.add(slot.dealed);

        uint256 leftover = amount.sub(slot.dealed);
        if (leftover > 0) {
            nrem.transfer(leftover);
            emit NewLeftoverCOIN(_remainder, leftover);
        }

        return true;
    }

    function closeStakes() public onlyIsInOwners nonReentrant returns (bool) {
        uint256 totRew = 0;

        uint256 toSC = _lastIndexE20s + 1;

        for (uint32 i = 0; i < (_lastIndexE20s + 1); i++) {
            E20 memory p = _E20s[i];
            if (p.flag == 1) {
                totRew = totRew.add(_withdrawAllrewards(p.sc));
            }
        }

        totRew = totRew.add(_withdrawAllrewardsCOIN());

        uint256 fund;
        bool autoC;
        uint256 funds = 0;

        Stake memory p;

        uint256 last = _stakes.getLastIndexStakes();

        for (uint256 i = 0; i < (last + 1); i++) {
            (p.account, p.bal, p.autoCompound, p.flag) = _stakes
                .getStakeByIndex(i);
            if (p.flag == 1) {
                (fund, autoC) = _stakes.getStake(p.account);
                _withdrawFunds(p.account, fund);
                funds = funds.add(fund);
            }
        }

        setPause(true);
        _stakes.removeAllStake();

        emit StakeClosed(toSC, (last + 1), funds, totRew);
        return true;
    }

    function _withdrawAllrewardsCOIN()
        internal
        SolvencyCOIN()
        nonReentrant
        returns (uint256)
    {
        uint256 total = 0;
        uint256 rew = 0;
        Stake memory p;

        uint256 last = _stakes.getLastIndexStakes();
        // SWC-113-DoS with Failed Call: L874 - L886
        for (uint256 i = 0; i < (last + 1); i++) {
            (p.account, p.bal, p.autoCompound, p.flag) = _stakes
                .getStakeByIndex(i);

            if (p.flag == 1) {
                rew = rewardedCOIN(p.account);

                if (rew > 0) {
                    _withdrawRewardCOIN(p.account, rew);
                    total = total.add(rew);
                }
            }
        }

        uint256 eth_reserve = address(this).balance;

        if (eth_reserve > 0) {
            address payable ow = address(uint160(_remainder));
            ow.transfer(eth_reserve);
        }

        return total;
    }

    function _withdrawAllrewards(address sc)
        internal
        Solvency(sc)
        returns (uint256)
    {
        uint256 total = 0;
        uint256 rew = 0;

        Stake memory p;

        uint256 last = _stakes.getLastIndexStakes();

        for (uint256 i = 0; i < (last + 1); i++) {
            (p.account, p.bal, p.autoCompound, p.flag) = _stakes
                .getStakeByIndex(i);

            if (p.flag == 1) {
                rew = rewarded(sc, p.account);

                if (rew > 0) {
                    _withdrawReward(sc, p.account, rew);
                    total = total.add(rew);
                }
            }
        }

        IERC20 _token = IERC20(sc);

        uint256 token_reserve = _token.balanceOf(address(this));

        if (token_reserve > 0) {
            require(_token.transfer(_remainder, token_reserve), "WO:trf");
        }

        return total;
    }

    function getSolvencyCOIN() public view returns (bool, uint256) {
        uint256 ind = 0;
        uint256 funds = 0;
        uint256 rews = 0;
        uint256 rewsc = 0;
        uint256 autos = 0;

        (ind, funds, rews, rewsc, autos) = getStatistics(_woopERC20);

        uint256 coins = getMyCoinBalance();

        if (coins < rewsc) {
            return (false, rewsc - coins);
        } else {
            return (true, coins - rewsc);
        }
    }

    function getSolvency(address sc) public view returns (bool, uint256) {
        Stadistic memory s;

        (s.ind, s.funds, s.rews, , ) = getStatistics(sc);

        uint256 tokens = getMyTokensBalance(sc);

        uint256 tot = s.funds + s.rews;

        if (tokens < tot) {
            return (false, tot - tokens);
        } else {
            return (true, tokens - tot);
        }
    }

    function getStatistics(address sc)
        public
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        uint256 fund;
        bool autoC;

        Stadistic memory s;

        Stake memory p;

        uint256 last = _stakes.getLastIndexStakes();

        for (uint256 i = 0; i < (last + 1); i++) {
            (p.account, p.bal, p.autoCompound, p.flag) = _stakes
                .getStakeByIndex(i);

            if (p.flag == 1) {
                (fund, autoC) = _stakes.getStake(p.account);

                if (sc == _woopERC20) {
                    s.funds = s.funds.add(fund);
                }

                fund = rewarded(sc, p.account);

                s.rews = s.rews.add(fund);

                fund = rewardedCOIN(p.account);

                s.rewsCOIN = s.rewsCOIN.add(fund);

                if (autoC) {
                    s.autocs++;
                }
                s.ind++;
            }
        }

        return (s.ind, s.funds, s.rews, s.rewsCOIN, s.autocs);
    }
}
