// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./DiceToken.sol";
import "./libs/IBEP20.sol";
import "./libs/SafeBEP20.sol";
import "./libs/ILuckyChipRouter02.sol";
import "./libs/IMasterChef.sol";

contract Dice is Ownable, ReentrancyGuard, Pausable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    uint256 public prevBankerAmount;
    uint256 public bankerAmount;
    uint256 public netValue;
    uint256 public currentEpoch;
    uint256 public playerEndBlock;
    uint256 public bankerEndBlock;
    uint256 public totalBonusAmount;
    uint256 public totalLotteryAmount;
    uint256 public totalLcLotteryAmount;
    uint256 public masterChefBonusId;
    uint256 public intervalBlocks;
    uint256 public playerTimeBlocks;
    uint256 public bankerTimeBlocks;
    uint256 public constant TOTAL_RATE = 10000; // 100%
    uint256 public gapRate = 500;
    uint256 public lcBackRate = 1000; // 10% in gap
    uint256 public bonusRate = 1000; // 10% in gap
    uint256 public lotteryRate = 100; // 1% in gap
    uint256 public lcLotteryRate = 50; // 0.5% in gap
    uint256 public minBetAmount;
    uint256 public maxBetRatio = 5;
    uint256 public maxExposureRatio = 300;
    uint256 public feeAmount;
    uint256 public maxBankerAmount;

    address public adminAddress;
    address public lcAdminAddress;
    address public masterChefAddress;
    IBEP20 public token;
    IBEP20 public lcToken;
    DiceToken public diceToken;    
    ILuckyChipRouter02 public swapRouter;

    enum Status {
        Pending,
        Open,
        Lock,
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
        uint256 lcBackAmount;
        uint256 bonusAmount;
        uint256 swapLcAmount;
        uint256 betUsers;
        uint32 finalNumber;
        Status status;
    }

    struct BetInfo {
        uint256 amount;
        uint16 numberCount;    
        bool[6] numbers;
        bool claimed; // default false
        bool lcClaimed; // default false
    }

    struct BankerInfo {
        uint256 diceTokenAmount;
        uint256 avgBuyValue;
    }

    mapping(uint256 => Round) public rounds;
    mapping(uint256 => mapping(address => BetInfo)) public ledger;
    mapping(address => uint256[]) public userRounds;
    mapping(address => BankerInfo) public bankerInfo;

    event RatesUpdated(uint256 indexed block, uint256 gapRate, uint256 lcBackRate, uint256 bonusRate, uint256 lotteryRate, uint256 lcLotteryRate);
    event AmountsUpdated(uint256 indexed block, uint256 minBetAmount, uint256 feeAmount, uint256 maxBankerAmount);
    event RatiosUpdated(uint256 indexed block, uint256 maxBetRatio, uint256 maxExposureRatio);
    event StartRound(uint256 indexed epoch, uint256 blockNumber, bytes32 bankHash);
    event LockRound(uint256 indexed epoch, uint256 blockNumber);
    event SendSecretRound(uint256 indexed epoch, uint256 blockNumber, uint256 bankSecret, uint32 finalNumber);
    event BetNumber(address indexed sender, uint256 indexed currentEpoch, bool[6] numbers, uint256 amount);
    event Claim(address indexed sender, uint256 indexed currentEpoch, uint256 amount);
    event ClaimBonusLC(address indexed sender, uint256 amount);
    event ClaimBonus(uint256 amount);
    event RewardsCalculated(uint256 indexed epoch,uint256 lcbackamount,uint256 bonusamount,uint256 swaplcamount);
    event SwapRouterUpdated(address indexed router);
    event EndPlayerTime(uint256 epoch, uint256 blockNumber);
    event EndBankerTime(uint256 epoch, uint256 blockNumber);
    event UpdateNetValue(uint256 epoch, uint256 blockNumber, uint256 netValue);
    event Deposit(address indexed user, uint256 tokenAmount);    
    event Withdraw(address indexed user, uint256 diceTokenAmount);    

    constructor(
        address _tokenAddress,
        address _lcTokenAddress,
        address _diceTokenAddress,
        address _masterChefAddress,
        uint256 _masterChefBonusId,
        uint256 _intervalBlocks,
        uint256 _playerTimeBlocks,
        uint256 _bankerTimeBlocks,
        uint256 _minBetAmount,
        uint256 _feeAmount,
        uint256 _maxBankerAmount
    ) public {
        token = IBEP20(_tokenAddress);
        lcToken = IBEP20(_lcTokenAddress);
        diceToken = DiceToken(_diceTokenAddress);
        masterChefAddress = _masterChefAddress;
        masterChefBonusId = _masterChefBonusId;
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
        require(!_isContract(msg.sender), "contract not allowed");
        require(msg.sender == tx.origin, "proxy contract not allowed");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == adminAddress, "admin: wut?");
        _;
    }

    // set blocks
    function setBlocks(uint256 _intervalBlocks, uint256 _playerTimeBlocks, uint256 _bankerTimeBlocks) external onlyAdmin {
        intervalBlocks = _intervalBlocks;
        playerTimeBlocks = _playerTimeBlocks;
        bankerTimeBlocks = _bankerTimeBlocks;
    }

    // set rates
    function setRates(uint256 _gapRate, uint256 _lcBackRate, uint256 _bonusRate, uint256 _lotteryRate, uint256 _lcLotteryRate) external onlyAdmin {
        require(_gapRate <= 1000, "gapRate <= 10%");
        require(_lcBackRate.add(_bonusRate).add(_lotteryRate).add(_lcLotteryRate) <= TOTAL_RATE, "rateSum <= TOTAL_RATE");
        gapRate = _gapRate;
        lcBackRate = _lcBackRate;
        bonusRate = _bonusRate;
        lotteryRate = _lotteryRate;
        lcLotteryRate = _lcLotteryRate;
        emit RatesUpdated(block.number, gapRate, lcBackRate, bonusRate, lotteryRate, lcLotteryRate);
    }

    // set amounts
    function setAmounts(uint256 _minBetAmount, uint256 _feeAmount, uint256 _maxBankerAmount) external onlyAdmin {
        minBetAmount = _minBetAmount;
        feeAmount = _feeAmount;
        maxBankerAmount = _maxBankerAmount;
        emit AmountsUpdated(block.number, minBetAmount, feeAmount, maxBankerAmount);
    }

    // set ratios
    function setRatios(uint256 _maxBetRatio, uint256 _maxExposureRatio) external onlyAdmin {
        maxBetRatio = _maxBetRatio;
        maxExposureRatio = _maxExposureRatio;
        emit RatiosUpdated(block.number, maxBetRatio, maxExposureRatio);
    }

    // set admin address
    function setAdmin(address _adminAddress, address _lcAdminAddress) external onlyOwner {
        require(_adminAddress != address(0) && _lcAdminAddress != address(0), "Cannot be zero address");
        adminAddress = _adminAddress;
        lcAdminAddress = _lcAdminAddress;
    }

    // End banker time
    function endBankerTime(uint256 epoch, bytes32 bankHash) external onlyAdmin whenPaused {
        require(epoch == currentEpoch + 1, "epoch == currentEpoch + 1");
        require(bankerAmount > 0, "Round can start only when bankerAmount > 0");
        prevBankerAmount = bankerAmount;
        _unpause();
        emit EndBankerTime(currentEpoch, block.timestamp);
        
        currentEpoch = currentEpoch + 1;
        _startRound(currentEpoch, bankHash);
        playerEndBlock = rounds[currentEpoch].startBlock.add(playerTimeBlocks);
        bankerEndBlock = rounds[currentEpoch].startBlock.add(bankerTimeBlocks);
    }

    // Start the next round n, lock for round n-1
    function executeRound(uint256 epoch, bytes32 bankHash) external onlyAdmin whenNotPaused{
        require(epoch == currentEpoch, "epoch == currentEpoch");

        // CurrentEpoch refers to previous round (n-1)
        lockRound(currentEpoch);

        // Increment currentEpoch to current round (n)
        currentEpoch = currentEpoch + 1;
        _startRound(currentEpoch, bankHash);
        require(rounds[currentEpoch].startBlock < playerEndBlock, "startBlock < playerEndBlock");
        require(rounds[currentEpoch].lockBlock <= playerEndBlock, "lockBlock < playerEndBlock");
    }

    // end player time, triggers banker time
    function endPlayerTime(uint256 epoch, uint256 bankSecret) external onlyAdmin whenNotPaused{
        require(epoch == currentEpoch, "epoch == currentEpoch");
        sendSecret(epoch, bankSecret);
        _pause();
        _updateNetValue(epoch);
        _claimBonusAndLottery();
        emit EndPlayerTime(currentEpoch, block.timestamp);
    }

    // end player time without caring last round
    function endPlayerTimeImmediately(uint256 epoch) external onlyAdmin whenNotPaused{
        require(epoch == currentEpoch, "epoch == currentEpoch");
        _pause();
        _updateNetValue(epoch);
        _claimBonusAndLottery();
        emit EndPlayerTime(currentEpoch, block.timestamp);
    }

    // update net value
    function _updateNetValue(uint256 epoch) internal whenPaused{    
        netValue = netValue.mul(bankerAmount).div(prevBankerAmount);
        emit UpdateNetValue(epoch, block.timestamp, netValue);
    }

    // send bankSecret
    function sendSecret(uint256 epoch, uint256 bankSecret) public onlyAdmin whenNotPaused{
        Round storage round = rounds[epoch];
        require(round.lockBlock != 0, "End round after round has locked");
        require(round.status == Status.Lock, "End round after round has locked");
        require(block.number >= round.lockBlock, "Send secret after lockBlock");
        require(block.number <= round.lockBlock.add(intervalBlocks), "Send secret within intervalBlocks");
        require(round.bankSecret == 0, "Already revealed");
        require(keccak256(abi.encodePacked(bankSecret)) == round.bankHash, "Bank reveal not matching commitment");

        _safeSendSecret(epoch, bankSecret);
        _calculateRewards(epoch);
    }

    function _safeSendSecret(uint256 epoch, uint256 bankSecret) internal whenNotPaused {
        Round storage round = rounds[epoch];
        round.secretSentBlock = block.number;
        round.bankSecret = bankSecret;
        uint256 random = round.bankSecret ^ round.betUsers ^ block.difficulty;
        round.finalNumber = uint32(random % 6);
        round.status = Status.Claimable;

        emit SendSecretRound(epoch, block.number, bankSecret, round.finalNumber);
    }

    // bet number
    function betNumber(bool[6] calldata numbers, uint256 amount) external payable whenNotPaused notContract nonReentrant {
        Round storage round = rounds[currentEpoch];
        require(msg.value >= feeAmount, "msg.value > feeAmount");
        require(round.status == Status.Open, "Round not Open");
        require(block.number > round.startBlock && block.number < round.lockBlock, "Round not bettable");
        require(ledger[currentEpoch][msg.sender].amount == 0, "Bet once per round");
        uint16 numberCount = 0;
        uint256 maxSingleBetAmount = 0;
        for (uint32 i = 0; i < 6; i ++) {
            if (numbers[i]) {
                numberCount = numberCount + 1;    
                if(round.betAmounts[i] > maxSingleBetAmount){
                    maxSingleBetAmount = round.betAmounts[i];
                }
            }
        }
        require(numberCount > 0, "numberCount > 0");
        require(amount >= minBetAmount.mul(uint256(numberCount)), "BetAmount >= minBetAmount * numberCount");
        require(amount <= round.maxBetAmount.mul(uint256(numberCount)), "BetAmount <= round.maxBetAmount * numberCount");
        if(numberCount == 1){
            require(maxSingleBetAmount.add(amount).sub(round.totalAmount.sub(maxSingleBetAmount)) < bankerAmount.mul(maxExposureRatio).div(TOTAL_RATE), 'MaxExposure Limit');
        }
        
        if (feeAmount > 0){
            _safeTransferBNB(adminAddress, feeAmount);
        }

        token.safeTransferFrom(address(msg.sender), address(this), amount);

        // Update round data
        round.totalAmount = round.totalAmount.add(amount);
        round.betUsers = round.betUsers.add(1);
        uint256 betAmount = amount.div(uint256(numberCount));
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

        emit BetNumber(msg.sender, currentEpoch, numbers, amount);
    }


    // Claim reward
    function claim(uint256 epoch) external notContract nonReentrant {
        require(rounds[epoch].startBlock != 0, "Round has not started");
        require(block.number > rounds[epoch].lockBlock, "Round has not locked");
        require(!ledger[epoch][msg.sender].claimed, "Rewards claimed");

        uint256 reward;
        BetInfo storage betInfo = ledger[epoch][msg.sender];
        // Round valid, claim rewards
        if (rounds[epoch].status == Status.Claimable) {
            require(claimable(epoch, msg.sender), "Not eligible for claim");
            uint256 singleAmount = betInfo.amount.div(uint256(betInfo.numberCount));
            reward = singleAmount.mul(5).mul(TOTAL_RATE.sub(gapRate)).div(TOTAL_RATE);
            reward = reward.add(singleAmount);
        }
        // Round invalid, refund bet amount
        else {
            require(refundable(epoch, msg.sender), "Not eligible for refund");
            reward = ledger[epoch][msg.sender].amount;
        }

        betInfo.claimed = true;
        token.safeTransfer(msg.sender, reward);

        emit Claim(msg.sender, epoch, reward);
    }

    // Claim lc back
    function claimLcBack(address user) external notContract nonReentrant {
        (uint256 lcAmount, uint256 startIndex, uint256 endIndex) = pendingLcBack(user);

        if (lcAmount > 0){
            uint256 epoch;
            for(uint256 i = startIndex; i < endIndex; i ++){
                epoch = userRounds[user][i];
                ledger[epoch][user].lcClaimed = true;
            }

            lcToken.safeTransfer(user, lcAmount);
        }
        emit ClaimBonusLC(user, lcAmount);
    }

    // View pending lc back
    function pendingLcBack(address user) public view returns (uint256 lcAmount, uint256 startIndex, uint256 endIndex) {
        uint256 epoch;
        uint256 roundLcAmount = 0;
        lcAmount = 0;
        startIndex = 0;
        endIndex = userRounds[user].length;
        for (uint256 i = userRounds[user].length - 1; i >= 0; i --){
            epoch = userRounds[user][i];
            BetInfo storage betInfo = ledger[epoch][msg.sender];
            if (betInfo.lcClaimed){
                startIndex = i.add(1);
                break;
            }else{
                Round storage round = rounds[epoch];
                if (round.status == Status.Claimable){
                    if (betInfo.numbers[round.finalNumber]){
                        roundLcAmount = betInfo.amount.div(uint256(betInfo.numberCount)).mul(5).mul(gapRate).div(TOTAL_RATE).mul(lcBackRate).div(TOTAL_RATE);
                        if (betInfo.numberCount > 1){
                            roundLcAmount = roundLcAmount.add(betInfo.amount.div(uint256(betInfo.numberCount)).mul(uint256(betInfo.numberCount - 1)).mul(gapRate).div(TOTAL_RATE).mul(lcBackRate).div(TOTAL_RATE));
                        }
                    }else{
                        roundLcAmount = betInfo.amount.mul(gapRate).div(TOTAL_RATE).mul(lcBackRate).div(TOTAL_RATE);
                    }

                    roundLcAmount = roundLcAmount.mul(round.swapLcAmount).div(round.lcBackAmount);
                    lcAmount = lcAmount.add(roundLcAmount);
                }
            }
        }
    }

    // Claim all bonus to masterChef
    function _claimBonusAndLottery() internal {
        uint256 tmpAmount = 0;
        if(totalBonusAmount > 0){
            tmpAmount = totalBonusAmount;
            totalBonusAmount = 0;
            token.safeTransfer(masterChefAddress, tmpAmount);
            IMasterChef(masterChefAddress).updateBonus(masterChefBonusId);
            emit ClaimBonus(tmpAmount);
        } 
        if(totalLotteryAmount > 0){
            tmpAmount = totalLotteryAmount;
            totalLotteryAmount = 0;
            token.safeTransfer(adminAddress, tmpAmount);
        }
        if(totalLcLotteryAmount > 0){
            tmpAmount = totalLcLotteryAmount;
            totalLcLotteryAmount = 0;
            token.safeTransfer(lcAdminAddress, tmpAmount);
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

    // Get the claimable stats of specific epoch and user account
    function claimable(uint256 epoch, address user) public view returns (bool) {
        return (rounds[epoch].status == Status.Claimable) && (ledger[epoch][user].numbers[rounds[epoch].finalNumber]);
    }

    // Get the refundable stats of specific epoch and user account
    function refundable(uint256 epoch, address user) public view returns (bool) {
        return (rounds[epoch].status != Status.Claimable) && block.number > rounds[epoch].lockBlock.add(intervalBlocks) && ledger[epoch][user].amount != 0;
    }

    // Manual Start round. Previous round n-1 must lock
    function manualStartRound(bytes32 bankHash) external onlyAdmin whenNotPaused {
        require(block.number >= rounds[currentEpoch].lockBlock, "Manual start new round after current round lock");
        currentEpoch = currentEpoch + 1;
        _startRound(currentEpoch, bankHash);
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

    // Lock round
    function lockRound(uint256 epoch) public whenNotPaused {
        Round storage round = rounds[epoch];
        require(round.startBlock != 0, "Lock round after round has started");
        require(block.number >= round.lockBlock, "Lock round after lockBlock");
        require(block.number <= round.lockBlock.add(intervalBlocks), "Lock round within intervalBlocks");
        round.status = Status.Lock;
        emit LockRound(epoch, block.number);
    }

    // Calculate rewards for round
    function _calculateRewards(uint256 epoch) internal {
        require(lcBackRate.add(bonusRate) <= TOTAL_RATE, "lcBackRate + bonusRate <= TOTAL_RATE");
        require(rounds[epoch].bonusAmount == 0, "Rewards calculated");
        Round storage round = rounds[epoch];

        { // avoid stack too deep
            uint256 lcBackAmount = 0;
            uint256 bonusAmount = 0;
            uint256 tmpAmount = 0;
            uint256 gapAmount = 0;
            uint256 tmpBankerAmount = bankerAmount;
            for (uint32 i = 0; i < 6; i ++){
                if (i == round.finalNumber){
                    tmpBankerAmount = tmpBankerAmount.sub(round.betAmounts[i].mul(5).mul(TOTAL_RATE.sub(gapRate)).div(TOTAL_RATE));
                    gapAmount = gapAmount = round.betAmounts[i].mul(5).mul(gapRate).div(TOTAL_RATE);
                }else{
                    tmpBankerAmount = tmpBankerAmount.add(round.betAmounts[i]);
                    gapAmount = round.betAmounts[i].mul(gapRate).div(TOTAL_RATE);
                }
                tmpAmount = gapAmount.mul(lcBackRate).div(TOTAL_RATE);
                lcBackAmount = lcBackAmount.add(tmpAmount);
                tmpBankerAmount = tmpBankerAmount.sub(tmpAmount);

                tmpAmount = gapAmount.mul(bonusRate).div(TOTAL_RATE);
                bonusAmount = bonusAmount.add(tmpAmount);
                tmpBankerAmount = tmpBankerAmount.sub(tmpAmount); 
            }
            round.lcBackAmount = lcBackAmount;
            round.bonusAmount = bonusAmount;
            bankerAmount = tmpBankerAmount;
    
            if(address(token) == address(lcToken)){
                round.swapLcAmount = lcBackAmount;
            }else if(address(swapRouter) != address(0)){
                address[] memory path = new address[](2);
                path[0] = address(token);
                path[1] = address(lcToken);
                uint256 lcAmout = swapRouter.swapExactTokensForTokens(round.lcBackAmount, 0, path, address(this), block.timestamp + (5 minutes))[1];
                round.swapLcAmount = lcAmout;
            }
            totalBonusAmount = totalBonusAmount.add(bonusAmount);
        }

        { // avoid stack too deep
            uint256 lotteryAmount = 0;
            uint256 lcLotteryAmount = 0;
            uint256 tmpAmount = 0;
            uint256 gapAmount = 0;
            uint256 tmpBankerAmount = bankerAmount;
            for (uint32 i = 0; i < 6; i ++){
                if (i == round.finalNumber){
                    gapAmount = gapAmount = round.betAmounts[i].mul(5).mul(gapRate).div(TOTAL_RATE);
                }else{
                    gapAmount = round.betAmounts[i].mul(gapRate).div(TOTAL_RATE);
                }
                tmpAmount = gapAmount.mul(lotteryRate).div(TOTAL_RATE);
                lotteryAmount = lotteryAmount.add(tmpAmount);
                tmpBankerAmount = tmpBankerAmount.sub(tmpAmount);

                tmpAmount = gapAmount.mul(lcLotteryRate).div(TOTAL_RATE);
                lcLotteryAmount = lcLotteryAmount.add(tmpAmount);
                tmpBankerAmount = tmpBankerAmount.sub(tmpAmount); 
            }
            bankerAmount = tmpBankerAmount;
    
            totalLotteryAmount = totalLotteryAmount.add(lotteryAmount);
            totalLcLotteryAmount = totalLcLotteryAmount.add(lcLotteryAmount);
        }

        emit RewardsCalculated(epoch, round.lcBackAmount, round.bonusAmount, round.swapLcAmount);
    }


    // Deposit token to Dice as a banker, get Syrup back.
    function deposit(uint256 _tokenAmount) public whenPaused nonReentrant notContract {
        require(_tokenAmount > 0, "Deposit amount > 0");
        require(bankerAmount.add(_tokenAmount) < maxBankerAmount, 'maxBankerAmount Limit');
        BankerInfo storage banker = bankerInfo[msg.sender];
        token.safeTransferFrom(address(msg.sender), address(this), _tokenAmount);
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
        token.safeTransfer(address(msg.sender), tokenAmount);

        emit Withdraw(msg.sender, _diceTokenAmount);
    }

    // View function to see banker diceToken Value on frontend.
    function canWithdrawToken(address bankerAddress) external view returns (uint256){
        return bankerInfo[bankerAddress].diceTokenAmount.mul(netValue).div(1e12);    
    }

    // View function to see banker diceToken Value on frontend.
    function calProfitRate(address bankerAddress) external view returns (uint256){
        return netValue.mul(100).div(bankerInfo[bankerAddress].avgBuyValue);    
    }

    // Judge address is contract or not
    function _isContract(address addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }

    // Update the swap router.
    function updateSwapRouter(address _router) external onlyAdmin {
        require(_router != address(0), "DICE: Invalid router address.");
        swapRouter = ILuckyChipRouter02(_router);
        emit SwapRouterUpdated(address(swapRouter));
    }

    function _safeTransferBNB(address to, uint256 value) internal {
        (bool success, ) = to.call{gas: 23000, value: value}("");
        require(success, 'TransferHelper: BNB_TRANSFER_FAILED');
    }
}

