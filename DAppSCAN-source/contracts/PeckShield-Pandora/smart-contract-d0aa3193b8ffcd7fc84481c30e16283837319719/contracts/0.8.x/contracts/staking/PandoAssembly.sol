//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../interfaces/IDroidBot.sol";
import "../libraries/NFTLib.sol";

contract PandoAssembly is Ownable, IERC721Receiver {
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 power;
        int256 rewardDebt;
        EnumerableSet.UintSet nftIds;
    }

    IERC20 public busd;
    IDroidBot public droidBot;

    // governance
    uint256 private constant ACC_REWARD_PRECISION = 1e12;
    uint256 private constant SLOT_PRICE_PRECISION = 100;
    address public reserveFund;
    address public paymentToken;
    address public receivingFund;

    uint256 public accRewardPerShare;
    uint256 public lastRewardTime;
    uint256 public endRewardTime;
    uint256 public startRewardTime;

    uint256 public rewardPerSecond;
    uint256 public totalPower;
    uint256 public slotBasePrice;
    uint256 public slotCoefficient;

    mapping (address => UserInfo) private userInfo;
    mapping (address => uint256) public slotPurchased;

    /* ========== Modifiers =============== */

    modifier onlyReserveFund() {
        require(reserveFund == msg.sender || owner() == msg.sender, "NFTStakingPool: caller is not the reserveFund");
        _;
    }

    constructor(address _busd, address _droidBot, address _paymentToken) {
        busd = IERC20(_busd);
        droidBot = IDroidBot(_droidBot);
        lastRewardTime = block.timestamp;
        startRewardTime = block.timestamp;
        paymentToken = _paymentToken;
        slotBasePrice = 100 * 1e18;
        slotCoefficient = 120;
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    function info(address _user) external view returns(uint256[] memory _nftIds){
        UserInfo storage user = userInfo[_user];
        _nftIds = EnumerableSet.values(user.nftIds);
    }

    function originalPower(address _user) public view returns (uint256 res) {
        UserInfo storage user = userInfo[_user];
        uint256[] memory tokenIds = EnumerableSet.values(user.nftIds);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            res += droidBot.info(tokenIds[i]).power;
        }
    }

    function currentPower(address _user) public view returns(uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 power = NFTLib.getPower(EnumerableSet.values(user.nftIds), droidBot);
        return power;
    }

    function getRewardForDuration(uint256 _from, uint256 _to) public view returns (uint256) {
        uint256 _rewardPerSecond = rewardPerSecond;
        if (_from >= _to || _from >= endRewardTime) return 0;
        if (_to <= startRewardTime) return 0;
        if (_from <= startRewardTime) {
            if (_to <= endRewardTime) return (_to - startRewardTime) * _rewardPerSecond;
            else return (endRewardTime - startRewardTime) * _rewardPerSecond;
        }
        if (_to <= endRewardTime) return (_to - _from) * _rewardPerSecond;
        else return (endRewardTime - _from) * _rewardPerSecond;
    }

    function getRewardPerSecond() public view returns (uint256) {
        return getRewardForDuration(block.timestamp, block.timestamp + 1);
    }

    function pendingReward(address _user) external view returns (uint256 pending) {
        UserInfo storage user = userInfo[_user];
        uint256 _accRewardPerShare = accRewardPerShare;
        if (block.timestamp > lastRewardTime && totalPower != 0) {
            uint256 rewardAmount = getRewardForDuration(lastRewardTime, block.timestamp);
            _accRewardPerShare += (rewardAmount * ACC_REWARD_PRECISION) / totalPower;
        }
        pending = uint256(int256(user.power * _accRewardPerShare / ACC_REWARD_PRECISION) - user.rewardDebt);
    }

    /// @notice Update reward variables of the given pool.
    function updatePool() public {
        if (block.timestamp > lastRewardTime) {
            if (totalPower > 0) {
                uint256 rewardAmount = getRewardForDuration(lastRewardTime, block.timestamp);
                accRewardPerShare += rewardAmount * ACC_REWARD_PRECISION / totalPower;
            }
            lastRewardTime = block.timestamp;
            emit LogUpdatePool(lastRewardTime, totalPower, accRewardPerShare);
        }
    }

    function buySlot(address to) public {
        uint256 n = slotPurchased[to];
        uint256 p = slotBasePrice * (slotCoefficient**n) / (SLOT_PRICE_PRECISION**n);
        slotPurchased[to]++;
        if (receivingFund == address (0)) {
            ERC20Burnable(paymentToken).burnFrom(msg.sender, p);
        } else {
            IERC20(paymentToken).safeTransferFrom(msg.sender, receivingFund, p);
        }
    }

    function deposit(uint256[] memory tokenIds, address to) public {
        updatePool();
        UserInfo storage user = userInfo[to];
        require(EnumerableSet.length(user.nftIds) + tokenIds.length <= 4 + slotPurchased[to], 'Staking : stake more than slot purchased');

        // Effects]
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            EnumerableSet.add(user.nftIds, tokenId);
            droidBot.safeTransferFrom(msg.sender, address(this), tokenIds[i]);
        }

        uint256 power = NFTLib.getPower(EnumerableSet.values(user.nftIds), droidBot);
        uint256 incPower = power - user.power;
        user.power = power;
        totalPower += incPower;
        user.rewardDebt += int256(incPower * accRewardPerShare / ACC_REWARD_PRECISION);
        emit Deposit(msg.sender, tokenIds, incPower, to);
    }


    function withdraw(uint256[] memory tokenIds, address to) public {
        updatePool();
        UserInfo storage user = userInfo[msg.sender];

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            if (EnumerableSet.contains(user.nftIds, tokenId)) {
                EnumerableSet.remove(user.nftIds, tokenId);
                droidBot.transferFrom(address(this), to, tokenId);
            }
        }
        uint256 power = NFTLib.getPower(EnumerableSet.values(user.nftIds), droidBot);
        uint256 withdrawPower = user.power - power;
        user.rewardDebt -= int256(withdrawPower * accRewardPerShare / ACC_REWARD_PRECISION);
        user.power -= withdrawPower;
        totalPower -= withdrawPower;
        // Effects
        emit Withdraw(msg.sender, tokenIds, withdrawPower, to);
    }

    /// @notice Harvest proceeds for transaction sender to `to`.
    /// @param to Receiver of rewards.
    function harvest(address to) public {
        updatePool();
        UserInfo storage user = userInfo[msg.sender];
        int256 accumulatedReward = int256(user.power * accRewardPerShare / ACC_REWARD_PRECISION);
        uint256 _pendingReward = uint256(accumulatedReward - user.rewardDebt);

        // Effects
        user.rewardDebt = accumulatedReward;

        // Interactions
        if (_pendingReward > 0) {
            busd.safeTransfer(to, _pendingReward);
        }
        emit Harvest(msg.sender, _pendingReward);
    }


    function withdrawAndHarvest(uint256[] memory tokenIds, address to) public {
        updatePool();
        UserInfo storage user = userInfo[msg.sender];

        int256 accumulatedReward = int256(user.power * accRewardPerShare / ACC_REWARD_PRECISION);
        uint256 _pendingReward = uint256(accumulatedReward - user.rewardDebt);

        // Effects
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            if (EnumerableSet.contains(user.nftIds, tokenId)) {
                EnumerableSet.remove(user.nftIds, tokenId);
                droidBot.transferFrom(address(this), to, tokenId);
            }
        }
        uint256 power = NFTLib.getPower(EnumerableSet.values(user.nftIds), droidBot);
        uint256 withdrawPower = user.power - power;

        user.rewardDebt = accumulatedReward - int256(withdrawPower * accRewardPerShare / ACC_REWARD_PRECISION);
        user.power -= withdrawPower;
        totalPower -= withdrawPower;

        // Interactions
        if (_pendingReward > 0) {
            busd.safeTransfer(to, _pendingReward);
        }

        emit Withdraw(msg.sender, tokenIds, withdrawPower, to);
        emit Harvest(msg.sender, _pendingReward);
    }

    function withdrawAll(address to) public {
        UserInfo storage user = userInfo[msg.sender];

        uint256[] memory tokenIds = EnumerableSet.values(user.nftIds);
        withdraw(tokenIds, to);
    }

    function withdrawAndHarvestAll(address to) public {
        UserInfo storage user = userInfo[msg.sender];

        uint256[] memory tokenIds = EnumerableSet.values(user.nftIds);
        withdrawAndHarvest(tokenIds, to);
    }

    /// @notice Withdraw without caring about rewards. EMERGENCY ONLY.
    /// @param to Receiver of the LP tokens.
    function emergencyWithdraw(address to) public {
        UserInfo storage user = userInfo[msg.sender];
        uint256 power = user.power;
        user.power = 0;
        user.rewardDebt = 0;
        totalPower -= power;

        // Note: transfer can fail or succeed if `amount` is zero.
        uint256[] memory tokenIds = EnumerableSet.values(user.nftIds);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            if (EnumerableSet.contains(user.nftIds, tokenId)) {
                EnumerableSet.remove(user.nftIds, tokenId);
                droidBot.transferFrom(address(this), to, tokenId);
            }
        }

        emit EmergencyWithdraw(msg.sender, tokenIds, power, to);
    }

    function onERC721Received(
        address operator,
        address, //from
        uint256, //tokenId
        bytes calldata //data
    ) public view override returns (bytes4) {
        require(
            operator == address(this),
            "received Nft from unauthenticated contract"
        );

        return
        bytes4(
            keccak256("onERC721Received(address,address,uint256,bytes)")
        );
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /// @notice Sets the reward per second to be distributed. Can only be called by the owner.
    /// @param _rewardPerSecond The amount of reward to be distributed per second.
    function setRewardPerSecond(uint256 _rewardPerSecond) internal {
        rewardPerSecond = _rewardPerSecond;
        emit LogRewardPerSecond(_rewardPerSecond);
    }

    function allocateMoreRewards(uint256 _addedReward, uint256 _days) external onlyReserveFund {
        updatePool();
        uint256 _pendingSeconds = (endRewardTime >  block.timestamp) ? (endRewardTime - block.timestamp) : 0;
        uint256 _newPendingReward = (rewardPerSecond * _pendingSeconds) + _addedReward;
        uint256 _newPendingSeconds = _pendingSeconds + (_days * (1 days));
        uint256 _newRewardPerSecond = _newPendingReward / _newPendingSeconds;
        setRewardPerSecond(_newRewardPerSecond);
        if (_days > 0) {
            if (endRewardTime <  block.timestamp) {
                endRewardTime =  block.timestamp + (_days * (1 days));
            } else {
                endRewardTime = endRewardTime +  (_days * (1 days));
            }
        }
        busd.safeTransferFrom(msg.sender, address(this), _addedReward);
    }

    function setReserveFund(address _reserveFund) external onlyOwner {
        reserveFund = _reserveFund;
    }

    function rescueFund(uint256 _amount) external onlyOwner {
        require(_amount > 0 && _amount <= busd.balanceOf(address(this)), "invalid amount");
        busd.safeTransfer(owner(), _amount);
        emit FundRescued(owner(), _amount);
    }

    function setPayment(address _paymentToken, uint256 _price, uint256 _coef) external onlyOwner {
        paymentToken = _paymentToken;
        slotBasePrice = _price;
        slotCoefficient = _coef;
        emit PaymentChanged(_paymentToken, _price, _coef);
    }

    function changeDroidBotAddress(address _newAddr) external onlyOwner {
        droidBot = IDroidBot(_newAddr);
        emit DroidBotAddressChanged(_newAddr);
    }

    function setReceivingFund(address _addr) external onlyOwner {
        receivingFund = _addr;
        emit ReceivingFundChanged(_addr);
    }
    /* =============== EVENTS ==================== */

    event Deposit(address indexed user, uint256[] nftId, uint256 amount, address indexed to);
    event Withdraw(address indexed user, uint256[] nftId, uint256 amount, address indexed to);
    event EmergencyWithdraw(address indexed user,  uint256[] nftId, uint256 amount, address indexed to);
    event Harvest(address indexed user, uint256 amount);
    event LogUpdatePool(uint256 lastRewardTime, uint256 lpSupply, uint256 accRewardPerShare);
    event LogRewardPerSecond(uint256 rewardPerSecond);
    event FundRescued(address indexed receiver, uint256 amount);
    event DroidBotAddressChanged(address droiBotAddress);
    event PaymentChanged(address token, uint256 price, uint256 coef);
    event ReceivingFundChanged(address receivingFund);
}