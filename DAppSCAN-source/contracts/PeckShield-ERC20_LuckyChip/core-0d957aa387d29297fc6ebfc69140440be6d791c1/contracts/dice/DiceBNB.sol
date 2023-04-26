// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IBEP20.sol";
import "../interfaces/IWBNB.sol";
import "../interfaces/IDice.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/ILuckyChipRouter02.sol";
import "../interfaces/IBetMining.sol";
import "../interfaces/ILuckyPower.sol";
import "../libraries/SafeBEP20.sol";
import "../token/DiceToken.sol";
import "../token/LCToken.sol";

contract DiceBNB is IDice, Ownable, ReentrancyGuard, Pausable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    uint256 public prevBankerAmount;
    uint256 public bankerAmount;
    uint256 public netValue;
    uint256 public currentEpoch;
    uint256 public playerEndBlock;
    uint256 public bankerEndBlock;
    uint256 public totalDevAmount;
    uint256 public totalBurnAmount;
    uint256 public totalBonusAmount;
    uint256 public totalLotteryAmount;
    uint256 public intervalBlocks;
    uint256 public playerTimeBlocks;
    uint256 public bankerTimeBlocks;
    uint256 public constant TOTAL_RATE = 10000; // 100%
    uint256 public gapRate = 220; // 2.2%
    uint256 public devRate = 500; // 10% in gap
    uint256 public burnRate = 500; // 0.5% in gap
    uint256 public bonusRate = 2000; // 10% in gap
    uint256 public lotteryRate = 500; // 1% in gap
    uint256 public minBetAmount;
    uint256 public maxBetRatio = 5;
    uint256 public maxLostRatio = 300;
    uint256 public withdrawFeeRatio = 10; // 0.1% for withdrawFee
    uint256 public feeAmount;
    uint256 public maxBankerAmount;
    uint256 public freeAmountMultiplier = 1;

    address public adminAddr;
    address public devAddr;
    address public lotteryAddr;
    IOracle public oracle;
    ILuckyPower public luckyPower;
    address public immutable WBNB;
    LCToken public lcToken;
    DiceToken public diceToken;    
    ILuckyChipRouter02 public swapRouter;
    IBetMining public betMining;

    enum Status {
        Pending,
        Open,
        Locked,
        Claimable,
        Expired
    }

    struct Round {
        uint256 startBlock;
        uint256 lockBlock;
        uint256 secretSentBlock;
        bytes32 bankHash;
        uint256 bankSecret;
        uint256 totalAmount;
        uint256 maxBetAmount;
        uint256[6] betAmounts;
        uint256 burnAmount;
        uint256 bonusAmount;
        uint256 lotteryAmount;
        uint256 betUsers;
        uint32 finalNumber;
        Status status;
    }

    struct BetInfo {
        uint256 amount;
        uint16 numberCount;    
        bool[6] numbers;
        bool claimed; // default false
    }

    struct BankerInfo {
        uint256 diceTokenAmount;
        uint256 avgBuyValue;
    }

    mapping(uint256 => Round) public rounds;
    mapping(uint256 => mapping(address => BetInfo)) public ledger;
    mapping(address => uint256[]) public userRounds;
    mapping(address => BankerInfo) public bankerInfo;

    event SetAdmin(uint256 indexed block, address adminAddr, address devAddr, address lotteryAddr);
    event SetBlocks(uint256 indexed block, uint256 playerTimeBlocks, uint256 bankerTimeBlocks);
    event SetRates(uint256 indexed block, uint256 gapRate, uint256 devRate, uint256 burnRate, uint256 bonusRate, uint256 lotteryRate);
    event SetAmounts(uint256 indexed block, uint256 minBetAmount, uint256 feeAmount, uint256 maxBankerAmount);
    event SetRatios(uint256 indexed block, uint256 maxBetRatio, uint256 maxLostRatio, uint256 withdrawFeeRatio);
    event SetMultiplier(uint256 indexed block, uint256 multiplier);
    event SetSwapRouter(uint256 indexed block, address swapRouterAddr);
    event SetOracle(uint256 indexed block, address oracleAddr);
    event SetLuckyPower(uint256 indexed block, address luckyPowerAddr);
    event SetBetMining(uint256 indexed block, address betMiningAddr);
    event StartRound(uint256 indexed epoch, uint256 blockNumber, bytes32 bankHash);
    event SendSecretRound(uint256 indexed epoch, uint256 blockNumber, uint256 bankSecret, uint32 finalNumber);
    event BetNumber(address indexed sender, uint256 indexed currentEpoch, bool[6] numbers, uint256 amount);
    event ClaimReward(address indexed sender, uint256 blockNumber, uint256 amount);
    event RewardsCalculated(uint256 indexed epoch, uint256 burnAmount, uint256 bonusAmount,uint256 lotteryAmount);
    event EndPlayerTime(uint256 epoch, uint256 blockNumber);
    event EndBankerTime(uint256 epoch, uint256 blockNumber);
    event UpdateNetValue(uint256 epoch, uint256 blockNumber, uint256 netValue);
    event Deposit(address indexed user, uint256 tokenAmount);
    event Withdraw(address indexed user, uint256 diceTokenAmount);

    constructor(
        address _WBNBAddr,
        address _lcTokenAddr,
        address _diceTokenAddr,
        address _luckyPowerAddr,
        address _devAddr,
        address _lotteryAddr,
        uint256 _intervalBlocks,
        uint256 _playerTimeBlocks,
        uint256 _bankerTimeBlocks,
        uint256 _minBetAmount,
        uint256 _feeAmount,
        uint256 _maxBankerAmount
    ) public {
        WBNB = _WBNBAddr;
        lcToken = LCToken(_lcTokenAddr);
        diceToken = DiceToken(_diceTokenAddr);
        luckyPower = ILuckyPower(_luckyPowerAddr);
        devAddr = _devAddr;
        lotteryAddr = _lotteryAddr;
        intervalBlocks = _intervalBlocks;
        playerTimeBlocks = _playerTimeBlocks;
        bankerTimeBlocks = _bankerTimeBlocks;
        minBetAmount = _minBetAmount;
        feeAmount = _feeAmount;
        maxBankerAmount = _maxBankerAmount;
        netValue = uint256(1e12);
        _pause();
    }

    modifier notContract() {
        require((!_isContract(msg.sender)) && (msg.sender == tx.origin), "no contract");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == adminAddr, "not admin");
        _;
    }

    // set blocks
    function setBlocks(uint256 _intervalBlocks, uint256 _playerTimeBlocks, uint256 _bankerTimeBlocks) external onlyAdmin {
        intervalBlocks = _intervalBlocks;
        playerTimeBlocks = _playerTimeBlocks;
        bankerTimeBlocks = _bankerTimeBlocks;
        emit SetBlocks(block.number, playerTimeBlocks, bankerTimeBlocks);
    }

    // set rates
    function setRates(uint256 _gapRate, uint256 _devRate, uint256 _burnRate, uint256 _bonusRate, uint256 _lotteryRate) external onlyAdmin {
        require(_gapRate <= 1000 && _devRate.add(_burnRate).add(_bonusRate).add(_lotteryRate) <= TOTAL_RATE, "rate limit");
        gapRate = _gapRate;
        devRate = _devRate;
        burnRate = _burnRate;
        bonusRate = _bonusRate;
        lotteryRate = _lotteryRate;
        emit SetRates(block.number, gapRate, devRate, burnRate, bonusRate, lotteryRate);
    }

    // set amounts
    function setAmounts(uint256 _minBetAmount, uint256 _feeAmount, uint256 _maxBankerAmount) external onlyAdmin {
        minBetAmount = _minBetAmount;
        feeAmount = _feeAmount;
        maxBankerAmount = _maxBankerAmount;
        emit SetAmounts(block.number, minBetAmount, feeAmount, maxBankerAmount);
    }

    // set ratios
    function setRatios(uint256 _maxBetRatio, uint256 _maxLostRatio, uint256 _withdrawFeeRatio) external onlyAdmin {
        require(_maxBetRatio <= 50 && _maxLostRatio <= 500 && _withdrawFeeRatio <= 50, "ratio limit");
        maxBetRatio = _maxBetRatio;
        maxLostRatio = _maxLostRatio;
        withdrawFeeRatio = _withdrawFeeRatio;
        emit SetRatios(block.number, maxBetRatio, maxLostRatio, withdrawFeeRatio);
    }

    // set admin address
    function setAdmin(address _adminAddr, address _devAddr, address _lotteryAddr) external onlyOwner {
        require(_adminAddr != address(0) && _devAddr != address(0) && _lotteryAddr != address(0), "Zero");
        adminAddr = _adminAddr;
        devAddr = _devAddr;
        lotteryAddr = _lotteryAddr;
        emit SetAdmin(block.number, adminAddr, devAddr, lotteryAddr);
    }

    function setFreeAmountMultiplier(uint256 _multiplier) external onlyOwner{
        require(_multiplier >= 1 && _multiplier <= 100, "multiplier range");
        freeAmountMultiplier = _multiplier;
        emit SetMultiplier(block.number, _multiplier);
    }

    // End banker time
    function endBankerTime(uint256 epoch, bytes32 bankHash) external onlyAdmin whenPaused {
        require(epoch == currentEpoch + 1, "Epoch");
        require(bankerAmount > 0, "bankerAmount gt 0");
        prevBankerAmount = bankerAmount;
        _unpause();
        emit EndBankerTime(currentEpoch, block.number);
        
        currentEpoch = currentEpoch + 1;
        _startRound(currentEpoch, bankHash);
        playerEndBlock = rounds[currentEpoch].startBlock.add(playerTimeBlocks);
        bankerEndBlock = rounds[currentEpoch].startBlock.add(bankerTimeBlocks);
    }

    // Start the next round n, lock for round n-1
    function executeRound(uint256 epoch, bytes32 bankHash) external onlyAdmin whenNotPaused{
        // CurrentEpoch refers to previous round (n-1)
        require(epoch == currentEpoch, "Epoch");
        require(block.number >= rounds[currentEpoch].lockBlock && block.number <= rounds[currentEpoch].lockBlock.add(intervalBlocks), "Within interval");
        rounds[currentEpoch].status = Status.Locked;

        // Increment currentEpoch to current round (n)
        currentEpoch = currentEpoch + 1;
        _startRound(currentEpoch, bankHash);
        require(rounds[currentEpoch].startBlock < playerEndBlock && rounds[currentEpoch].lockBlock <= playerEndBlock, "playerTime");
    }

    // end player time, triggers banker time
    function endPlayerTime(uint256 epoch, uint256 bankSecret) external onlyAdmin whenNotPaused{
        require(epoch == currentEpoch, "epoch");
        rounds[currentEpoch].status = Status.Locked; 
        sendSecret(epoch, bankSecret);
        _pause();
        _updateNetValue(epoch);
        _claimBonusAndLottery();
        emit EndPlayerTime(currentEpoch, block.number);
    }

    // end player time without caring last round
    function endPlayerTimeImmediately(uint256 epoch) external onlyAdmin whenNotPaused{
        require(epoch == currentEpoch, "epoch");
        _pause();
        _updateNetValue(epoch);
        _claimBonusAndLottery();
        emit EndPlayerTime(currentEpoch, block.number);
    }

    // update net value
    function _updateNetValue(uint256 epoch) internal whenPaused{    
        netValue = netValue.mul(bankerAmount).div(prevBankerAmount);
        emit UpdateNetValue(epoch, block.number, netValue);
    }

    // send bankSecret
    function sendSecret(uint256 epoch, uint256 bankSecret) public onlyAdmin whenNotPaused{
        Round storage round = rounds[epoch];
        require(round.status == Status.Locked, "Has locked");
        require(block.number >= round.lockBlock && block.number <= round.lockBlock.add(intervalBlocks), "Within interval");
        require(round.bankSecret == 0, "Revealed");
        require(keccak256(abi.encodePacked(bankSecret)) == round.bankHash, "Not matching");

        _safeSendSecret(epoch, bankSecret);
        _calculateRewards(epoch);
    }

    function _safeSendSecret(uint256 epoch, uint256 bankSecret) internal whenNotPaused {
        Round storage round = rounds[epoch];
        round.secretSentBlock = block.number;
        round.bankSecret = bankSecret;
        uint256 random = round.bankSecret ^ round.betUsers ^ block.timestamp ^ block.difficulty;
        round.finalNumber = uint32(random % 6);
        round.status = Status.Claimable;

        emit SendSecretRound(epoch, block.number, bankSecret, round.finalNumber);
    }

    // bet number
    function betNumber(bool[6] calldata numbers, address referrer) external payable whenNotPaused notContract nonReentrant {
        Round storage round = rounds[currentEpoch];
        require(msg.value >= feeAmount, "FeeAmount");
        require(round.status == Status.Open, "Not Open");
        require(block.number > round.startBlock && block.number < round.lockBlock, "Not bettable");
        require(ledger[currentEpoch][msg.sender].amount == 0, "Bet once");
        uint16 numberCount = 0;
        for (uint32 i = 0; i < 6; i ++) {
            if (numbers[i]) {
                numberCount = numberCount + 1;    
            }
        }
        require(numberCount > 0, "numberCount > 0");
        uint256 amount = msg.value.sub(feeAmount);
        require(amount >= minBetAmount.mul(uint256(numberCount)) && amount <= round.maxBetAmount.mul(uint256(numberCount)), "range limit");
        uint256 maxBetAmount = 0;
        uint256 betAmount = amount.div(uint256(numberCount));
        for (uint32 i = 0; i < 6; i ++) {
            if (numbers[i]) {
                if(round.betAmounts[i].add(betAmount) > maxBetAmount){
                    maxBetAmount = round.betAmounts[i].add(betAmount);
                }
            }else{
                if(round.betAmounts[i] > maxBetAmount){
                    maxBetAmount = round.betAmounts[i];
                }
            }
        }

        if(maxBetAmount.mul(5) > round.totalAmount.add(amount).sub(maxBetAmount)){
            require(maxBetAmount.mul(5).sub(round.totalAmount.add(amount).sub(maxBetAmount)) < bankerAmount.mul(maxLostRatio).div(TOTAL_RATE), 'MaxLost Limit');
        }
        
        if (feeAmount > 0){
            _safeTransferBNB(adminAddr, feeAmount);
        }

        // Update round data
        round.totalAmount = round.totalAmount.add(amount);
        round.betUsers = round.betUsers.add(1);
        for (uint32 i = 0; i < 6; i ++) {
            if (numbers[i]) {
                round.betAmounts[i] = round.betAmounts[i].add(betAmount);
            }
        }

        // Update user data
        BetInfo storage betInfo = ledger[currentEpoch][msg.sender];
        betInfo.numbers = numbers;
        betInfo.amount = amount;
        betInfo.numberCount = numberCount;
        userRounds[msg.sender].push(currentEpoch);

        if(address(betMining) != address(0)){
            betMining.bet(msg.sender, referrer, WBNB, amount);
        }

        if(address(luckyPower) != address(0)){
            luckyPower.updatePower(msg.sender);
        }

        emit BetNumber(msg.sender, currentEpoch, numbers, amount);
    }

    // Claim reward
    function claimReward() external notContract nonReentrant {
        address user = address(msg.sender);
        (uint256 rewardAmount, uint256 startIndex, uint256 endIndex) = pendingReward(user);

        if (rewardAmount > 0){
            uint256 epoch;
            for(uint256 i = startIndex; i < endIndex; i ++){
                epoch = userRounds[user][i];
                ledger[epoch][user].claimed = true;
            }

            IWBNB(WBNB).withdraw(rewardAmount);
            _safeTransferBNB(user, rewardAmount);
            emit ClaimReward(user, block.number, rewardAmount);
        }
    }

    // View pending reward
    function pendingReward(address user) public view returns (uint256 rewardAmount, uint256 startIndex, uint256 endIndex) {
        uint256 epoch;
        uint256 roundRewardAmount = 0;
        rewardAmount = 0;
        startIndex = 0;
        endIndex = 0;
        if(userRounds[user].length > 0){
            uint256 i = userRounds[user].length.sub(1);
            while(i >= 0){
                epoch = userRounds[user][i];
                if (ledger[epoch][user].claimed){
                    startIndex = i.add(1);
                    break;
                }
                if(i == 0){
                    break;
                }
                i = i.sub(1);
            }

            endIndex = startIndex;
            for (i = startIndex; i < userRounds[user].length; i ++){
                epoch = userRounds[user][i];
                BetInfo storage betInfo = ledger[epoch][user];
                Round storage round = rounds[epoch];
                if (round.status == Status.Claimable){
                    if(betInfo.numbers[round.finalNumber]){
                        uint256 singleAmount = betInfo.amount.div(uint256(betInfo.numberCount));
                        roundRewardAmount = singleAmount.mul(6).mul(TOTAL_RATE.sub(gapRate)).div(TOTAL_RATE);
                        rewardAmount = rewardAmount.add(roundRewardAmount);
                    }
                    endIndex = endIndex.add(1);
                }else{
                    if(block.number > round.lockBlock.add(intervalBlocks)){
                        rewardAmount = rewardAmount.add(betInfo.amount);
                        endIndex = endIndex.add(1);
                    }else{
                        break;
                    }
                }
            }
        }
    }

    // Claim all bonus to LuckyPower
    function _claimBonusAndLottery() internal {
        uint256 tmpAmount = 0;
        uint256 withdrawAmount = totalDevAmount.add(totalBonusAmount).add(totalLotteryAmount);
        IWBNB(WBNB).withdraw(withdrawAmount);
        if(totalDevAmount > 0){
            tmpAmount = totalDevAmount;
            totalDevAmount = 0;
            _safeTransferBNB(devAddr, tmpAmount);
        }
        if(totalBurnAmount > 0){
            tmpAmount = totalBurnAmount;
            totalBurnAmount = 0;
            lcToken.burn(address(this), tmpAmount);
        }
        if(totalBonusAmount > 0){
            tmpAmount = totalBonusAmount;
            totalBonusAmount = 0;
            _safeTransferBNB(address(luckyPower), tmpAmount);
            if(address(luckyPower) != address(0)){
                luckyPower.updateBonus(WBNB, tmpAmount);
            }
        } 
        if(totalLotteryAmount > 0){
            tmpAmount = totalLotteryAmount;
            totalLotteryAmount = 0;
            _safeTransferBNB(lotteryAddr, tmpAmount);
        }
    }

    // Return round epochs that a user has participated
    function getUserRounds(
        address user,
        uint256 cursor,
        uint256 size
    ) external view returns (uint256[] memory, uint256) {
        uint256 length = size;
        if (length > userRounds[user].length - cursor) {
            length = userRounds[user].length - cursor;
        }

        uint256[] memory values = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            values[i] = userRounds[user][cursor.add(i)];
        }

        return (values, cursor.add(length));
    }

    // Return user bet info
    function getUserBetInfo(uint256 epoch, address user) external view returns (uint256, uint16, bool[6] memory, bool){
        BetInfo storage betInfo = ledger[epoch][user];
        return (betInfo.amount, betInfo.numberCount, betInfo.numbers, betInfo.claimed);
    }

    // Return betAmounts of a round
    function getRoundBetAmounts(uint256 epoch) external view returns (uint256[6] memory){
        return rounds[epoch].betAmounts;
    }

    // Manual Start round. Previous round n-1 must lock
    function manualStartRound(bytes32 bankHash) external onlyAdmin whenNotPaused {
        require(block.number >= rounds[currentEpoch].lockBlock, "Manual start");
        currentEpoch = currentEpoch + 1;
        _startRound(currentEpoch, bankHash);
        require(rounds[currentEpoch].startBlock < playerEndBlock && rounds[currentEpoch].lockBlock <= playerEndBlock, "playerTime");
    }

    function _startRound(uint256 epoch, bytes32 bankHash) internal {
        Round storage round = rounds[epoch];
        round.startBlock = block.number;
        round.lockBlock = block.number.add(intervalBlocks);
        round.bankHash = bankHash;
        round.totalAmount = 0;
        round.maxBetAmount = bankerAmount.mul(maxBetRatio).div(TOTAL_RATE);
        round.status = Status.Open;

        emit StartRound(epoch, block.number, bankHash);
    }

    // Calculate rewards for round
    function _calculateRewards(uint256 epoch) internal {
        require(rounds[epoch].bonusAmount == 0, "Rewards calculated");
        Round storage round = rounds[epoch];

        { // avoid stack too deep
            uint256 devAmount = 0;
            uint256 burnAmount = 0;
            
            uint256 tmpAmount = 0;
            uint256 gapAmount = 0;
            uint256 tmpBankerAmount = bankerAmount;
            for (uint32 i = 0; i < 6; i ++){
                if (i == round.finalNumber){
                    tmpBankerAmount = tmpBankerAmount.sub(round.betAmounts[i].mul(6).mul(TOTAL_RATE.sub(gapRate)).div(TOTAL_RATE));
                    gapAmount = round.betAmounts[i].mul(6).mul(gapRate).div(TOTAL_RATE);
                }else{
                    tmpBankerAmount = tmpBankerAmount.add(round.betAmounts[i]);
                    gapAmount = round.betAmounts[i].mul(gapRate).div(TOTAL_RATE);
                }
                tmpAmount = gapAmount.mul(devRate).div(TOTAL_RATE);
                devAmount = devAmount.add(tmpAmount);
                tmpBankerAmount = tmpBankerAmount.sub(tmpAmount);

                tmpAmount = gapAmount.mul(burnRate).div(TOTAL_RATE);
                burnAmount = burnAmount.add(tmpAmount);
                tmpBankerAmount = tmpBankerAmount.sub(tmpAmount);
            }
            
            round.burnAmount = burnAmount;
            bankerAmount = tmpBankerAmount;
    
            totalDevAmount = totalDevAmount.add(devAmount);
            if(address(swapRouter) != address(0)){
                address[] memory path = new address[](2);
                path[0] = WBNB;
                path[1] = address(lcToken);
                uint256 amountOut = swapRouter.getAmountsOut(round.burnAmount, path)[1];
                uint256 lcAmount = swapRouter.swapExactTokensForTokens(round.burnAmount, amountOut.mul(5).div(10), path, address(this), block.timestamp + (5 minutes))[1];
                totalBurnAmount = totalBurnAmount.add(lcAmount);
            }
        }

        { // avoid stack too deep
            uint256 bonusAmount = 0;
            uint256 lotteryAmount = 0;
            
            uint256 tmpAmount = 0;
            uint256 gapAmount = 0;
            uint256 tmpBankerAmount = bankerAmount;
            for (uint32 i = 0; i < 6; i ++){
                if (i == round.finalNumber){
                    gapAmount = round.betAmounts[i].mul(6).mul(gapRate).div(TOTAL_RATE);
                }else{
                    gapAmount = round.betAmounts[i].mul(gapRate).div(TOTAL_RATE);
                }
                tmpAmount = gapAmount.mul(bonusRate).div(TOTAL_RATE);
                bonusAmount = bonusAmount.add(tmpAmount);
                tmpBankerAmount = tmpBankerAmount.sub(tmpAmount);

                tmpAmount = gapAmount.mul(lotteryRate).div(TOTAL_RATE);
                lotteryAmount = lotteryAmount.add(tmpAmount);
                tmpBankerAmount = tmpBankerAmount.sub(tmpAmount);
            }
            bankerAmount = tmpBankerAmount;
            round.bonusAmount = bonusAmount;
            round.lotteryAmount = lotteryAmount;

            totalBonusAmount = totalBonusAmount.add(bonusAmount);
            totalLotteryAmount = totalLotteryAmount.add(lotteryAmount);
        }

        emit RewardsCalculated(epoch, round.burnAmount, round.bonusAmount, round.lotteryAmount);
    }

    // Deposit token to Dice as a banker, get Syrup back.
    function deposit() public payable whenPaused nonReentrant notContract {
        uint256 _tokenAmount = msg.value;
        require(_tokenAmount > 0, "Amount > 0");
        require(bankerAmount.add(_tokenAmount) < maxBankerAmount, 'maxBankerAmount Limit');
        BankerInfo storage banker = bankerInfo[msg.sender];
        IWBNB(WBNB).deposit{value: _tokenAmount}();
        assert(IWBNB(WBNB).transfer(address(this), _tokenAmount));
        uint256 diceTokenAmount = _tokenAmount.mul(1e12).div(netValue);
        diceToken.mint(address(msg.sender), diceTokenAmount);
        uint256 totalDiceTokenAmount = banker.diceTokenAmount.add(diceTokenAmount);
        banker.avgBuyValue = banker.avgBuyValue.mul(banker.diceTokenAmount).div(1e12).add(_tokenAmount).mul(1e12).div(totalDiceTokenAmount);
        banker.diceTokenAmount = totalDiceTokenAmount;
        bankerAmount = bankerAmount.add(_tokenAmount);
        emit Deposit(msg.sender, _tokenAmount);    
    }

    // Withdraw syrup from dice to get token back
    function withdraw(uint256 _diceTokenAmount) public whenPaused nonReentrant notContract {
        require(_diceTokenAmount > 0, "diceTokenAmount > 0");
        BankerInfo storage banker = bankerInfo[msg.sender];
        banker.diceTokenAmount = banker.diceTokenAmount.sub(_diceTokenAmount); 
        SafeBEP20.safeTransferFrom(diceToken, msg.sender, address(diceToken), _diceTokenAmount);
        diceToken.burn(address(diceToken), _diceTokenAmount);
        uint256 tokenAmount = _diceTokenAmount.mul(netValue).div(1e12);
        bankerAmount = bankerAmount.sub(tokenAmount);
        IWBNB(WBNB).withdraw(tokenAmount);
        if (withdrawFeeRatio > 0 && address(luckyPower) != address(0) && address(oracle) != address(0)){
            uint256 freeAmount = luckyPower.getPower(msg.sender).mul(freeAmountMultiplier);
            uint256 transLcAmount = oracle.getQuantity(WBNB, tokenAmount);
            if(transLcAmount > freeAmount){
                uint256 withdrawFee = transLcAmount.sub(freeAmount).mul(tokenAmount).div(transLcAmount).mul(withdrawFeeRatio).div(TOTAL_RATE);
                tokenAmount = tokenAmount.sub(withdrawFee);
                _safeTransferBNB(devAddr, withdrawFee);
            }
        }
        
        _safeTransferBNB(address(msg.sender), tokenAmount);

        emit Withdraw(msg.sender, _diceTokenAmount);
    }

    // Judge address is contract or not
    function _isContract(address addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }

    // View function to see banker diceToken Value on frontend.
    function canWithdrawToken(address bankerAddr) external view returns (uint256){
        return bankerInfo[bankerAddr].diceTokenAmount.mul(netValue).div(1e12);    
    }

    // View function to see banker diceToken Value on frontend.
    function canWithdrawAmount(uint256 _amount) external override view returns (uint256){
        return _amount.mul(netValue).div(1e12);    
    }

    // View function to see banker diceToken Value on frontend.
    function calProfitRate(address bankerAddr) external view returns (uint256){
        return netValue.mul(100).div(bankerInfo[bankerAddr].avgBuyValue);    
    }

    // Update the swap router.
    function setSwapRouter(address _router) external onlyAdmin {
        require(_router != address(0), "Zero");
        swapRouter = ILuckyChipRouter02(_router);
        emit SetSwapRouter(block.number, _router);
    }

    // Update the oracle.
    function setOracle(address _oracleAddr) external onlyAdmin {
        require(_oracleAddr != address(0), "Zero");
        oracle = IOracle(_oracleAddr);
        emit SetOracle(block.number, _oracleAddr);
    }

    // Update the lucky power.
    function setLuckyPower(address _luckyPowerAddr) external onlyAdmin {
        require(_luckyPowerAddr != address(0), "Zero");
        luckyPower = ILuckyPower(_luckyPowerAddr);
        emit SetLuckyPower(block.number, _luckyPowerAddr);
    }

    // Update the bet mining.
    function setBetMining(address _betMiningAddr) external onlyAdmin {
        require(_betMiningAddr != address(0), "Zero");
        betMining = IBetMining(_betMiningAddr);
        emit SetBetMining(block.number, _betMiningAddr);
    }

    function _safeTransferBNB(address to, uint256 value) internal {
        (bool success, ) = to.call{gas: 23000, value: value}("");
        require(success, 'BNB_TRANSFER_FAILED');
    }

    function tokenAddr() public override view returns (address){
        return WBNB;
    }
}

