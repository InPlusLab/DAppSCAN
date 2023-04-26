// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";

import "../governance/InitializableOwner.sol";
import "../interfaces/IvDsgToken.sol";
import "../interfaces/IBurnableERC20.sol";
import "../pools/MutiRewardPool.sol";
import "../base/BasicMetaTransaction.sol";


contract TimeShop is InitializableOwner, ReentrancyGuard, BasicMetaTransaction {
    using SafeMath for uint256;
    using SafeERC20 for IBurnableERC20;
    using SafeERC20 for IERC20;

    event BuyTimeToken(
        address indexed sender,
        uint256 indexed dsg_amount,
        uint256 timestamp
    );
    event Withdraw(address indexed sender, uint256 indexed tm_amount);

    IBurnableERC20 public m_dsg_token;
    IvDsgToken public m_vdsg_token;
    IERC20 public m_time_token;
    MutiRewardPool public m_time_pool;

    uint256 public total;
    uint256 public total_supply;

    /*
        Used to redeem Time DSG.
        50% burns immediately.
        15% dividend vDSG.
        15% is immediately released to the Time pledger.
        20% will be linearly released to Time pledgers within 6 months.
    */
    uint256 constant m_base_rate = 100;
    uint256 constant m_100_percent = 10000;
    uint256 constant m_burn_rate = 50 * m_base_rate;
    uint256 constant m_vdsg_rate = 15 * m_base_rate;
    uint256 constant m_pool_now_rate = 15 * m_base_rate;
    uint256 constant m_pool_slow_rate = 20 * m_base_rate;
    uint256 constant m_max_round = 10;

    //@param max_time_token;         max timeToken.
    //@param max_dsg_token;          max cost dsg.
    //@param long_time;              how long get all timeToken.
    //@param right_now_release;      right now get timeToken.
    //@param total_dsg;              right get dsg;
    struct DsgTimeTokenRate {
        uint256 max_time_token;
        uint256 max_dsg_token;
        uint256 long_time;
        uint256 right_now_release;
        uint256 total_dsg;
    }

    uint256 now_round;
    DsgTimeTokenRate[m_max_round] public m_dsg_time_rate;

    struct DebtRecord {
        uint256 round;
        uint256 endTime;
        uint256 latestTime;
        // this timeToken amount.
        uint256 totalAmount;
        uint256 debtAmount;
    }

    using EnumerableSet for EnumerableSet.UintSet;

    struct UserRecord {
        // value is startTime . if complete, remove it.
        EnumerableSet.UintSet buys;
        // startTime => reward timetoken record.
        mapping(uint256 => DebtRecord) records;
    }

    mapping(address => UserRecord) users;

    constructor() public {}

    function initialize(
        address _dsg_token,
        address _vdsg_token,
        address _time_token,
        address time_pool
    ) public {
        super._initialize();

        m_dsg_token = IBurnableERC20(_dsg_token);
        m_vdsg_token = IvDsgToken(_vdsg_token);
        m_time_token = IERC20(_time_token);
        m_time_pool = MutiRewardPool(time_pool);

        total = 7_000_000_000_000_000 * (10**18);
        init_rate();
        m_time_token.safeTransferFrom(msgSender(), address(this), total);
    }

    function init_rate() internal {
        require(m_dsg_time_rate[0].max_dsg_token == 0, "error.");

        //total 160,000,000
        m_dsg_time_rate[0].max_dsg_token = 500_000 * (10**18);
        m_dsg_time_rate[1].max_dsg_token = 2_000_000 * (10**18);
        m_dsg_time_rate[2].max_dsg_token = 7_500_000 * (10**18);
        m_dsg_time_rate[3].max_dsg_token = 15_000_000 * (10**18);
        m_dsg_time_rate[4].max_dsg_token = 27_000_000 * (10**18);
        m_dsg_time_rate[5].max_dsg_token = 33_000_000 * (10**18);
        m_dsg_time_rate[6].max_dsg_token = 26_000_000 * (10**18);
        m_dsg_time_rate[7].max_dsg_token = 21_000_000 * (10**18);
        m_dsg_time_rate[8].max_dsg_token = 18_000_000 * (10**18);
        m_dsg_time_rate[9].max_dsg_token = 10_000_000 * (10**18);

        //total 7,000,000,000,000,000
        m_dsg_time_rate[0].max_time_token = 100_000_000_000_000 * (10**18);
        m_dsg_time_rate[1].max_time_token = 300_000_000_000_000 * (10**18);
        m_dsg_time_rate[2].max_time_token = 600_000_000_000_000 * (10**18);
        m_dsg_time_rate[3].max_time_token = 1_000_000_000_000_000 * (10**18);
        m_dsg_time_rate[4].max_time_token = 1_500_000_000_000_000 * (10**18);
        m_dsg_time_rate[5].max_time_token = 1_500_000_000_000_000 * (10**18);
        m_dsg_time_rate[6].max_time_token = 1_000_000_000_000_000 * (10**18);
        m_dsg_time_rate[7].max_time_token = 600_000_000_000_000 * (10**18);
        m_dsg_time_rate[8].max_time_token = 300_000_000_000_000 * (10**18);
        m_dsg_time_rate[9].max_time_token = 100_000_000_000_000 * (10**18);

        m_dsg_time_rate[0].right_now_release = 5 * m_base_rate;
        m_dsg_time_rate[1].right_now_release = 8 * m_base_rate;
        m_dsg_time_rate[2].right_now_release = 15 * m_base_rate;
        m_dsg_time_rate[3].right_now_release = 20 * m_base_rate;
        m_dsg_time_rate[4].right_now_release = 25 * m_base_rate;
        m_dsg_time_rate[5].right_now_release = 33 * m_base_rate;
        m_dsg_time_rate[6].right_now_release = 40 * m_base_rate;
        m_dsg_time_rate[7].right_now_release = 50 * m_base_rate;
        m_dsg_time_rate[8].right_now_release = 60 * m_base_rate;
        m_dsg_time_rate[9].right_now_release = 90 * m_base_rate;

        m_dsg_time_rate[0].long_time = 48 * 30 days;
        m_dsg_time_rate[1].long_time = 36 * 30 days;
        m_dsg_time_rate[2].long_time = 24 * 30 days;
        m_dsg_time_rate[3].long_time = 18 * 30 days;
        m_dsg_time_rate[4].long_time = 12 * 30 days;
        m_dsg_time_rate[5].long_time = 9 * 30 days;
        m_dsg_time_rate[6].long_time = 6 * 30 days;
        m_dsg_time_rate[7].long_time = 3 * 30 days;
        m_dsg_time_rate[8].long_time = 2 * 30 days;
        m_dsg_time_rate[9].long_time = 1 * 30 days;
    }

    function withdrawAll() public {
        // storage .
        UserRecord storage ur = users[msgSender()];

        uint256 totalReceive = 0;
        uint256 length = ur.buys.length();

        for (uint256 i = 0; i < length;) {
            uint256 get_key = ur.buys.at(i);
            DebtRecord storage dr = ur.records[get_key];

            if (dr.debtAmount == dr.totalAmount) {
                continue;
            }

            uint256 re = establishTimeTokenRound(msgSender(), get_key);

            dr.latestTime = block.timestamp;
            dr.debtAmount = dr.debtAmount.add(re);

            if (dr.debtAmount == dr.totalAmount) {
                ur.buys.remove(get_key);
                length--;
            } else {
                i++;
            }

            totalReceive = totalReceive.add(re);
        }

        total_supply = total_supply.add(totalReceive);

        m_time_token.safeTransfer(msgSender(), totalReceive);
        
        emit Withdraw(msgSender(), totalReceive);
    }

    function withdraw(uint256 idx) public {
        UserRecord storage ur = users[msgSender()];
        require(idx < ur.buys.length(), "bad idx");

        uint256 get_key = ur.buys.at(idx);
        DebtRecord storage dr = ur.records[get_key];

        if (dr.debtAmount == dr.totalAmount) {
            return;
        }

        uint256 re = establishTimeTokenRound(msgSender(), get_key);

        dr.latestTime = block.timestamp;
        dr.debtAmount = dr.debtAmount.add(re);

        if (dr.debtAmount == dr.totalAmount) {
            ur.buys.remove(get_key);
        }

        total_supply = total_supply.add(re);

        m_time_token.safeTransfer(msgSender(), re);

        emit Withdraw(msgSender(), re);
    }

    function getReward(address sender) public view returns (uint256) {
        // storage .
        UserRecord storage ur = users[sender];

        uint256 totalReceive = 0;
        for (uint256 i = 0; i < ur.buys.length(); ++i) {
            uint256 re = establishTimeTokenRound(sender, ur.buys.at(i));

            totalReceive = totalReceive.add(re);
        }

        return totalReceive;
    }

    function establishTimeTokenRound(address sender, uint256 key)
        public
        view
        returns (uint256)
    {
        UserRecord storage ur = users[sender];

        DebtRecord memory dr = ur.records[key];

        // cant find record.
        if (dr.endTime == 0) {
            return 0;
        }
        
        if (dr.endTime <= dr.latestTime) {
            return 0;
        }

        return
            getReleaseAmount(
                dr.latestTime,
                dr.endTime,
                dr.totalAmount,
                dr.debtAmount
            );
    }

    function buyTimeToken(uint256 dsg_amount) public {
        require(dsg_amount > 0, "bad amount");

        DsgTimeTokenRate storage dttr = m_dsg_time_rate[now_round];

        uint256 remainingAmount = dttr.max_dsg_token.sub(dttr.total_dsg);

        //  now round enough.
        if (remainingAmount >= dsg_amount) {
            _buyTimeTokenByRound(dsg_amount, now_round);

            if (remainingAmount == dsg_amount && now_round < m_max_round - 1) {
                now_round++;
            }
        } else {
            if (remainingAmount > 0) {
                _buyTimeTokenByRound(remainingAmount, now_round);
            }
            
            if (now_round < m_max_round - 1) {
                now_round++;
            }
        }
    }

    function _buyTimeTokenByRound(uint256 dsg_amount, uint256 round) nonReentrant
        internal
        returns (bool)
    {
        DsgTimeTokenRate storage dttr = m_dsg_time_rate[round];
        require(
            dttr.total_dsg.add(dsg_amount) <= dttr.max_dsg_token,
            "not enough timeToken."
        );

        dttr.total_dsg = dttr.total_dsg.add(dsg_amount);

        // create DebtRecord.
        DebtRecord memory dr;
        dr.round = round;
        dr.endTime = block.timestamp + dttr.long_time;
        dr.latestTime = block.timestamp;

        /// caculate
        dr.totalAmount = dttr.max_time_token.mul(dsg_amount).div(dttr.max_dsg_token);

        // storage .
        UserRecord storage ur = users[msgSender()];

        // dont allow buy timeToken in same time.
        require(!ur.buys.contains(block.timestamp), "please try later.");
        ur.buys.add(block.timestamp);

        /// transfer from dsg.
        m_dsg_token.safeTransferFrom(msgSender(), address(this), dsg_amount);

        // burn, donate, pool
        dispatchDSGToken(dsg_amount);

        uint256 to_value = dr.totalAmount.mul(dttr.right_now_release).div(m_100_percent);

        dr.debtAmount = to_value;
        ur.records[block.timestamp] = dr;

        total_supply = total_supply.add(to_value);

        m_time_token.safeTransfer(msgSender(), to_value);
        emit BuyTimeToken(msgSender(), dsg_amount, block.timestamp);

        return true;
    }

    // dispath dsg token.
    function dispatchDSGToken(uint256 dsg_amount) internal returns (bool) {

        // burn
        uint256 burn_amount = dsg_amount.mul(m_burn_rate).div(m_100_percent);
        m_dsg_token.burn(burn_amount);

        // donate to vdsg.
        uint256 donate_amount = dsg_amount.mul(m_vdsg_rate).div(m_100_percent);
        m_dsg_token.approve(address(m_vdsg_token), donate_amount);
        m_vdsg_token.donate(donate_amount);

        // donate time pool
        uint256 pool_donate_amount = dsg_amount.mul(m_pool_now_rate).div(m_100_percent);
        uint256 pool_slow_amount = dsg_amount.mul(m_pool_slow_rate).div(m_100_percent);

        // only approve once for  donate, addAdditionalRewards
        m_dsg_token.approve(address(m_time_pool), pool_slow_amount + pool_donate_amount);
        m_time_pool.donate(m_dsg_token, pool_donate_amount);

        // addAdditionalRewards time pool.  6 months , butTimeTokenabount blocks: (1 * 60 * 60 * 24 * 30 * 6) / 3 = 5184000
        
        // consider token0 == dsg.
        uint256 t0areb = 0;
        if (m_dsg_token == m_time_pool.rewardToken0()) {
            t0areb = m_time_pool.token0AdditionalRewardEndBlock();
        }else if (m_dsg_token == m_time_pool.rewardToken1()) {
            t0areb = m_time_pool.token1AdditionalRewardEndBlock();
        }else{
            require(false, "cant find dsg token.");
        }

        uint256 remainingBlocks = t0areb > block.number ? t0areb.sub(block.number) : 0;
        remainingBlocks = 5184000 > remainingBlocks ? 5184000 - remainingBlocks : 5184000;
      
        m_time_pool.addAdditionalRewards(m_dsg_token, pool_slow_amount, remainingBlocks);

        return true;
    }

    function getReleaseAmount(
        uint256 latestTime,
        uint256 endTime,
        uint256 totalAmount,
        uint256 debtAmount
    ) public view returns (uint256) {
        if (endTime <= latestTime) {
            return 0;
        }

        uint256 _receive_time = 0;
        if (block.timestamp >= endTime) {
            _receive_time = endTime;
        } else {
            _receive_time = block.timestamp;
        }

        // require(_endTime > latestTime, "error time.");
        if (_receive_time <= latestTime) {
            return 0;
        }

        uint256 amount = totalAmount.sub(debtAmount).mul(_receive_time.sub(latestTime)).div(endTime.sub(latestTime));

        return amount;
    }

    function getViews() public view returns (DsgTimeTokenRate[] memory vv) {
        vv = new DsgTimeTokenRate[](10);

        for (uint256 i = 0; i < 10; i++) {
            vv[i] = m_dsg_time_rate[i];
        }

        return vv;
    }

    function getUsersRecordLength(address sender)
        public
        view
        returns (uint256)
    {
        return users[sender].buys.length();
    }

    function getUserRecordKey(address sender, uint256 index)
        public
        view
        returns (DebtRecord memory)
    {
        uint256 key = users[sender].buys.at(index);
        return users[sender].records[key];
    }

    function getUserBuyRecords(address sender) public view returns(DebtRecord[] memory records) {
        UserRecord storage user = users[sender];
        uint256 len = user.buys.length();

        if (len == 0) {
            return records;
        }

        records = new DebtRecord[](len);
        
        for (uint256 i = 0; i < len; ++i) {
            records[i] = user.records[user.buys.at(i)];
        }

    }
}
