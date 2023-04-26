// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IBEP20.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/ILuckyPower.sol";
import "../interfaces/IMasterChef.sol";
import "../interfaces/IBetMining.sol";
import "../interfaces/IReferral.sol";
import "../interfaces/ILottery.sol";
import "../libraries/SafeBEP20.sol";

contract LuckyPower is ILuckyPower, Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _tokens;
    EnumerableSet.AddressSet private _updaters;
    EnumerableSet.AddressSet private _lpTokens;
    EnumerableSet.AddressSet private _diceTokens;
    EnumerableSet.AddressSet private _teamAddrs;

    // Power quantity info of each user.
    struct UserInfo {
        uint256 quantity;
        uint256 lpQuantity;
        uint256 bankerQuantity;
        uint256 playerQuantity;
        uint256 referrerQuantity;
        uint256 lotteryQuantity;
    }

    // Reward info of each user for each bonus
    struct UserRewardInfo {
        uint256 pendingReward;
        uint256 rewardDebt;
        uint256 accRewardAmount;
    }

    // Info of each pool.
    struct BonusInfo {
        address token; // Address of bonus token contract.
        uint256 lastRewardBlock; // Last block number that reward tokens distribution occurs.
        uint256 accRewardPerShare; // Accumulated reward tokens per share, times 1e12.
        uint256 allocRewardAmount;
        uint256 accRewardAmount;
    }

    uint256 public quantity;
    uint256 public constant PERCENT_DEC = 10000;
    uint256 public lpPercent = 5000;

    // Lc token
    IBEP20 public lcToken;
    // Info of each bonus.
    BonusInfo[] public bonusInfo;
    // token address to its corresponding id
    mapping(address => uint256) public tokenIdMap;
    // Info of each user that stakes LP tokens.
    mapping(address => UserInfo) public userInfo;
    // user pending bonus 
    mapping(uint256 => mapping(address => UserRewardInfo)) public userRewardInfo;

    IOracle public oracle;
    IMasterChef public masterChef;
    IBetMining public betMining;
    IReferral public referral;
    ILottery public lottery;

    function isUpdater(address account) public view returns (bool) {
        return EnumerableSet.contains(_updaters, account);
    }

    // modifier for mint function
    modifier onlyUpdater() {
        require(isUpdater(msg.sender), "caller is not a updater");
        _;
    }

    function addUpdater(address _addUpdater) public onlyOwner returns (bool) {
        require(_addUpdater != address(0), "Token: _addUpdater is the zero address");
        return EnumerableSet.add(_updaters, _addUpdater);
    }

    function delUpdater(address _delUpdater) public onlyOwner returns (bool) {
        require(_delUpdater != address(0), "Token: _delUpdater is the zero address");
        return EnumerableSet.remove(_updaters, _delUpdater);
    } 

    event UpdatePower(address indexed user, uint256 quantity);
    event Withdraw(address indexed user);
    event EmergencyWithdraw(address indexed user);
    event SetMasterChef(address indexed _masterChefAddr);
    event SetBetMining(address indexed _betMiningAddr);
    event SetReferral(address indexed _referralAddr);
    event SetLottery(address indexed _lotteryAddr);

    constructor(
        address _lcTokenAddr,
        address _oracleAddr,
        address _masterChefAddr,
        address _betMiningAddr,
        address _referralAddr,
        address _lotteryAddr
    ) public {
        lcToken = IBEP20(_lcTokenAddr);
        oracle = IOracle(_oracleAddr);
        masterChef = IMasterChef(_masterChefAddr);
        betMining = IBetMining(_betMiningAddr);
        referral = IReferral(_referralAddr);
        lottery = ILottery(_lotteryAddr);
    }

    // Add a new token to the pool. Can only be called by the owner.
    function addBonus(address _token) public onlyOwner {
        require(_token != address(0), "BetMining: _token is the zero address");

        require(!EnumerableSet.contains(_tokens, _token), "BetMining: _token is already added to the pool");
        // return EnumerableSet.add(_tokens, _token);
        EnumerableSet.add(_tokens, _token);

        bonusInfo.push(
            BonusInfo({
                token: _token,
                lastRewardBlock: block.number,
                accRewardPerShare: 0,
                allocRewardAmount: 0,
                accRewardAmount: 0
            })
        );
        tokenIdMap[_token] = getBonusLength() - 1;
    }

    // Update reward variables of the given pool to be up-to-date.
    function updateBonus(address bonusToken, uint256 amount) public override onlyUpdater {
        uint256 bonusId = tokenIdMap[bonusToken];
        require(bonusId < bonusInfo.length, "BonusId must be less than bonusInfo length");

        BonusInfo storage bonus = bonusInfo[bonusId];
        if(bonus.token != bonusToken || quantity <= 0){
            return;
        }

        uint256 length = EnumerableSet.length(_teamAddrs);
        for(uint256 i = 0; i < length; i ++){
            address teamAddr = EnumerableSet.at(_teamAddrs, i);
            updatePower(teamAddr);
        }

        bonus.accRewardPerShare = bonus.accRewardPerShare.add(amount.mul(1e12).div(quantity));
        bonus.allocRewardAmount = bonus.allocRewardAmount.add(amount);
        bonus.accRewardAmount = bonus.accRewardAmount.add(amount);
        bonus.lastRewardBlock = block.number;
    }

    function getPower(address account) public override view returns (uint256) {
        return userInfo[account].quantity;
    }

        // add pending rewardss.
    function addPendingRewards(address account) internal{
        UserInfo storage user = userInfo[account];
        if (user.quantity > 0) {
            for(uint256 i = 0; i < bonusInfo.length; i ++){
                BonusInfo storage bonus = bonusInfo[i];
                UserRewardInfo storage userReward = userRewardInfo[i][account];
                uint256 pendingReward = user.quantity.mul(bonus.accRewardPerShare).div(1e12).sub(userReward.rewardDebt);
                if (pendingReward > 0) {
                    userReward.pendingReward = userReward.pendingReward.add(pendingReward);
                    userReward.accRewardAmount = userReward.accRewardAmount.add(pendingReward);
                }
            }
        }
    }

    function updatePower(address account) public override{
        require(account != address(0), "BetMining: bet account is zero address");

        for(uint256 i = 0; i < bonusInfo.length; i ++){
            BonusInfo storage bonus = bonusInfo[i];
            if(bonus.token != address(lcToken)){
                oracle.update(bonus.token, address(lcToken));
                oracle.updateBlockInfo();
            }
        }

        UserInfo storage user = userInfo[account];
        addPendingRewards(account);

        uint256 tmpQuantity = user.quantity;
        uint256 newQuantity = 0;
        if(address(masterChef) != address(0) && address(oracle) != address(0)){
            (address[] memory tokens, uint256[] memory amounts, uint256[] memory pendingLcAmounts, uint256 devPending, uint256 poolLength) = masterChef.getLuckyPower(account);
            uint256 tmpLpQuantity = 0;
            uint256 tmpBankerQuantity = 0;
            uint256 tmpValue = 0;
            for(uint256 i = 0; i < poolLength; i ++){
                if(EnumerableSet.contains(_lpTokens, tokens[i])){
                    tmpValue = oracle.getLpTokenValue(tokens[i], amounts[i]);
                    tmpLpQuantity = tmpLpQuantity.add(tmpValue.mul(lpPercent).div(PERCENT_DEC)).add(pendingLcAmounts[i]);
                    newQuantity = newQuantity.add(tmpValue.mul(lpPercent).div(PERCENT_DEC)).add(pendingLcAmounts[i]);
                }else if(EnumerableSet.contains(_diceTokens, tokens[i])){
                    tmpValue = oracle.getDiceTokenValue(tokens[i], amounts[i]);
                    tmpBankerQuantity = tmpLpQuantity.add(tmpValue).add(pendingLcAmounts[i]);
                    newQuantity = newQuantity.add(tmpValue).add(pendingLcAmounts[i]);
                }
            }
            user.lpQuantity = tmpLpQuantity;
            user.bankerQuantity = tmpBankerQuantity;
            if(devPending > 0){
                newQuantity = newQuantity.add(devPending);
            }
        }else{
            user.bankerQuantity = 0;
            user.lpQuantity = 0;
        }

        if(address(betMining) != address(0)){
            user.playerQuantity = betMining.getLuckyPower(account);
            newQuantity = newQuantity.add(user.playerQuantity);
        }else{
            user.playerQuantity = 0;
        }
        
        if(address(referral) != address(0)){
            user.referrerQuantity = referral.getLuckyPower(account);
            newQuantity = newQuantity.add(user.referrerQuantity);
        }else{
            user.referrerQuantity = 0;
        }

        if(address(lottery) != address(0)){
            user.lotteryQuantity = lottery.getLuckyPower(account);
            newQuantity = newQuantity.add(user.lotteryQuantity);
        }else{
            user.lotteryQuantity = 0;
        }
        user.quantity = newQuantity;

        quantity = quantity.sub(tmpQuantity).add(user.quantity);
        for(uint256 i = 0; i < bonusInfo.length; i ++){
            BonusInfo storage bonus = bonusInfo[i];
            UserRewardInfo storage userReward = userRewardInfo[i][account];
            userReward.rewardDebt = user.quantity.mul(bonus.accRewardPerShare).div(1e12);
        }

        emit UpdatePower(account, user.quantity);
    }

    function pendingRewards(address account) public view returns (address[] memory, uint256[] memory) {
        uint256 length = bonusInfo.length;
        address[] memory tokens = new address[](length);
        uint256[] memory amounts = new uint256[](length);
        UserInfo storage user = userInfo[account];
        if (user.quantity > 0) {
            for(uint256 i = 0; i < length; i ++){
                BonusInfo storage bonus = bonusInfo[i];
                UserRewardInfo storage userReward = userRewardInfo[i][account];
                uint256 pendingReward = user.quantity.mul(bonus.accRewardPerShare).div(1e12).sub(userReward.rewardDebt);
                tokens[i] = bonus.token;
                amounts[i] = userReward.pendingReward.add(pendingReward);
            }
        }
        return (tokens, amounts);
    }

    function withdraw() public nonReentrant {
        address account = msg.sender;
        addPendingRewards(account);

        uint256 tmpReward = 0;
        for(uint256 i = 0; i < bonusInfo.length; i ++){
            BonusInfo storage bonus = bonusInfo[i];
            UserRewardInfo storage userReward = userRewardInfo[i][account];
            tmpReward = userReward.pendingReward;
            userReward.pendingReward = 0;
            IBEP20(bonus.token).safeTransfer(account, tmpReward);
        }

        updatePower(account);
        emit Withdraw(msg.sender);
    }

    
    function emergencyWithdraw() public nonReentrant {
        address account = msg.sender;

        uint256 tmpReward = 0;
        for(uint256 i = 0; i < bonusInfo.length; i ++){
            BonusInfo storage bonus = bonusInfo[i];
            UserRewardInfo storage userReward = userRewardInfo[i][account];
            tmpReward = userReward.pendingReward;
            userReward.pendingReward = 0;
            IBEP20(bonus.token).safeTransfer(account, tmpReward);
        }

        updatePower(account);
        emit EmergencyWithdraw(msg.sender);
    }

    function setOracle(address _oracleAddr) public onlyOwner {
        require(_oracleAddr != address(0), "BetMining: new oracle is the zero address");
        oracle = IOracle(_oracleAddr);
    }

    function setMasterChef(address _masterChefAddr) public onlyOwner {
        require(_masterChefAddr != address(0), "Zero");
        masterChef = IMasterChef(_masterChefAddr);
        emit SetMasterChef(_masterChefAddr);
    }

    function setBetMining(address _betMiningAddr) public onlyOwner {
        require(_betMiningAddr != address(0), "Zero");
        betMining = IBetMining(_betMiningAddr);
        emit SetBetMining(_betMiningAddr);
    }

    function setReferral(address _referralAddr) public onlyOwner {
        require(_referralAddr != address(0), "Zero");
        referral = IReferral(_referralAddr);
        emit SetReferral(_referralAddr);
    }

    function setLottery(address _lotteryAddr) public onlyOwner {
        require(_lotteryAddr != address(0), "Zero");
        lottery = ILottery(_lotteryAddr);
        emit SetLottery(_lotteryAddr);
    }

    function setLpPercent(uint256 _percent) public onlyOwner {
        require(_percent <= PERCENT_DEC, "range");
        lpPercent = _percent;
    }

    function getLpTokensLength() public view returns (uint256) {
        return EnumerableSet.length(_tokens);
    }

    function getLpToken(uint256 _index) public view returns (address) {
        return EnumerableSet.at(_tokens, _index);
    }

    function addLpToken(address _addLpToken) public onlyOwner returns (bool) {
        require(_addLpToken != address(0), "Token: _addLpToken is the zero address");
        return EnumerableSet.add(_lpTokens, _addLpToken);
    }

    function delLpToken(address _delLpToken) public onlyOwner returns (bool) {
        require(_delLpToken != address(0), "Token: _delLpToken is the zero address");
        return EnumerableSet.remove(_lpTokens, _delLpToken);
    } 

    function addDiceToken(address _addDiceToken) public onlyOwner returns (bool) {
        require(_addDiceToken != address(0), "Token: _addDiceToken is the zero address");
        return EnumerableSet.add(_diceTokens, _addDiceToken);
    }

    function delDiceToken(address _delDiceToken) public onlyOwner returns (bool) {
        require(_delDiceToken != address(0), "Token: _delDiceToken is the zero address");
        return EnumerableSet.remove(_diceTokens, _delDiceToken);
    }

    function addTeamAddr(address _teamAddr) public onlyOwner returns (bool) {
        require(_teamAddr != address(0), "Addr: _teamAddr is the zero address");
        return EnumerableSet.add(_teamAddrs, _teamAddr);
    }

    function delTeamAddr(address _teamAddr) public onlyOwner returns (bool) {
        require(_teamAddr != address(0), "Addr: _teamAddr is the zero address");
        return EnumerableSet.remove(_teamAddrs, _teamAddr);
    } 

    function getUpdaterLength() public view returns (uint256) {
        return EnumerableSet.length(_updaters);
    }

    function getUpdater(uint256 _index) public view returns (address) {
        return EnumerableSet.at(_updaters, _index);
    }

    function getBonusLength() public view returns (uint256) {
        return bonusInfo.length;
    }

}
