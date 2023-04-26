// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./utils/ContractGuard.sol";
import "./interfaces/IBasisAsset.sol";
import "./interfaces/ITreasury.sol";

contract Boardroom is ContractGuard {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /* ========== DATA STRUCTURES ========== */

    struct Boardseat {
        uint256 lastSnapshotIndex;
        uint256 rewardEarned;
        uint256 epochTimerStart;
    }

    struct BoardroomSnapshot {
        uint256 time;
        uint256 rewardReceived;
        uint256 rewardPerShare;
    }

    /* ========== STATE VARIABLES ========== */

    IERC20 public sky;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    // governance
    address public operator;

    // flags
    bool public initialized = false;

    IERC20 public dark;
    ITreasury public treasury;

    mapping(address => Boardseat) public directors;
    BoardroomSnapshot[] public boardHistory;

    uint256 public withdrawLockupEpochs;
    uint256 public rewardLockupEpochs;

    address public reserveFund;
    uint256 public withdrawFee;
    uint256 public stakeFee;

    /* ========== EVENTS ========== */

    event Initialized(address indexed executor, uint256 at);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardAdded(address indexed user, uint256 reward);

    /* ========== Modifiers =============== */

    modifier onlyOperator() {
        require(operator == msg.sender, "Boardroom: caller is not the operator");
        _;
    }

    modifier directorExists {
        require(balanceOf(msg.sender) > 0, "Boardroom: The director does not exist");
        _;
    }

    modifier updateReward(address director) {
        if (director != address(0)) {
            Boardseat memory seat = directors[director];
            seat.rewardEarned = earned(director);
            seat.lastSnapshotIndex = latestSnapshotIndex();
            directors[director] = seat;
        }
        _;
    }

    modifier notInitialized {
        require(!initialized, "Boardroom: already initialized");
        _;
    }

    /* ========== GOVERNANCE ========== */

    function initialize(
        IERC20 _dark,
        IERC20 _sky,
        ITreasury _treasury
    ) public notInitialized {
        dark = _dark;
        sky = _sky;
        treasury = _treasury;

        stakeFee = 2;
        withdrawFee = 0;

        BoardroomSnapshot memory genesisSnapshot = BoardroomSnapshot({time : block.number, rewardReceived : 0, rewardPerShare : 0});
        boardHistory.push(genesisSnapshot);

        withdrawLockupEpochs = 6; // Lock for 6 epochs (48h) before release withdraw
        rewardLockupEpochs = 3; // Lock for 3 epochs (24h) before release claimReward

        initialized = true;
        operator = msg.sender;
        emit Initialized(msg.sender, block.number);
    }

    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
    }

    function setLockUp(uint256 _withdrawLockupEpochs, uint256 _rewardLockupEpochs) external onlyOperator {
        require(_withdrawLockupEpochs >= _rewardLockupEpochs && _withdrawLockupEpochs <= 42, "_withdrawLockupEpochs: out of range"); // <= 2 week
        withdrawLockupEpochs = _withdrawLockupEpochs;
        rewardLockupEpochs = _rewardLockupEpochs;
    }

    function setReserveFund(address _reserveFund) external onlyOperator {
        require(_reserveFund != address(0), "reserveFund address cannot be 0 address");
        reserveFund = _reserveFund;
    }

    function setStakeFee(uint256 _stakeFee) external onlyOperator {
        require(_stakeFee <= 5, "Max stake fee is 5%");
        stakeFee = _stakeFee;
    }

    function setWithdrawFee(uint256 _withdrawFee) external onlyOperator {
        require(_withdrawFee <= 20, "Max withdraw fee is 20%");
        withdrawFee = _withdrawFee;
    }

    /* ========== VIEW FUNCTIONS ========== */

    // =========== Snapshot getters

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function latestSnapshotIndex() public view returns (uint256) {
        return boardHistory.length.sub(1);
    }

    function getLatestSnapshot() internal view returns (BoardroomSnapshot memory) {
        return boardHistory[latestSnapshotIndex()];
    }

    function getLastSnapshotIndexOf(address director) public view returns (uint256) {
        return directors[director].lastSnapshotIndex;
    }

    function getLastSnapshotOf(address director) internal view returns (BoardroomSnapshot memory) {
        return boardHistory[getLastSnapshotIndexOf(director)];
    }

    function canWithdraw(address director) external view returns (bool) {
        return directors[director].epochTimerStart.add(withdrawLockupEpochs) <= treasury.epoch();
    }

    function canClaimReward(address director) external view returns (bool) {
        return directors[director].epochTimerStart.add(rewardLockupEpochs) <= treasury.epoch();
    }

    function epoch() external view returns (uint256) {
        return treasury.epoch();
    }

    function nextEpochPoint() external view returns (uint256) {
        return treasury.nextEpochPoint();
    }

    function getDarkPrice() external view returns (uint256) {
        return treasury.getDarkPrice();
    }

    // =========== Director getters

    function rewardPerShare() public view returns (uint256) {
        return getLatestSnapshot().rewardPerShare;
    }

    function earned(address director) public view returns (uint256) {
        uint256 latestRPS = getLatestSnapshot().rewardPerShare;
        uint256 storedRPS = getLastSnapshotOf(director).rewardPerShare;

        return balanceOf(director).mul(latestRPS.sub(storedRPS)).div(1e18).add(directors[director].rewardEarned);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stake(uint256 amount) public onlyOneBlock updateReward(msg.sender) {
        require(amount > 0, "Boardroom: Cannot stake 0");
        sky.safeTransferFrom(msg.sender, address(this), amount);
        if (stakeFee > 0) {
            uint256 feeAmount = amount.mul(stakeFee).div(100);
            sky.safeTransfer(reserveFund, feeAmount);
            amount = amount.sub(feeAmount);
        }
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        directors[msg.sender].epochTimerStart = treasury.epoch(); // reset timer
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public onlyOneBlock directorExists updateReward(msg.sender) {
        require(amount > 0, "Boardroom: Cannot withdraw 0");
        require(directors[msg.sender].epochTimerStart.add(withdrawLockupEpochs) <= treasury.epoch(), "Boardroom: still in withdraw lockup");
        claimReward();
        uint256 directorShare = _balances[msg.sender];
        require(directorShare >= amount, "Boardroom: withdraw request greater than staked amount");
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = directorShare.sub(amount);
        if (withdrawFee > 0) {
            uint256 feeAmount = amount.mul(withdrawFee).div(100);
            sky.safeTransfer(reserveFund, feeAmount);
            amount = amount.sub(feeAmount);
        }
        sky.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        withdraw(balanceOf(msg.sender));
    }

    function claimReward() public updateReward(msg.sender) {
        uint256 reward = directors[msg.sender].rewardEarned;
        if (reward > 0) {
            require(directors[msg.sender].epochTimerStart.add(rewardLockupEpochs) <= treasury.epoch(), "Boardroom: still in reward lockup");
            directors[msg.sender].epochTimerStart = treasury.epoch(); // reset timer
            directors[msg.sender].rewardEarned = 0;
            dark.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function allocateSeigniorage(uint256 amount) external onlyOneBlock onlyOperator {
        require(amount > 0, "Boardroom: Cannot allocate 0");
        require(totalSupply() > 0, "Boardroom: Cannot allocate when totalSupply is 0");

        // Create & add new snapshot
        uint256 prevRPS = getLatestSnapshot().rewardPerShare;
        uint256 nextRPS = prevRPS.add(amount.mul(1e18).div(totalSupply()));

        BoardroomSnapshot memory newSnapshot = BoardroomSnapshot({
            time: block.number,
            rewardReceived: amount,
            rewardPerShare: nextRPS
        });
        boardHistory.push(newSnapshot);

        dark.safeTransferFrom(msg.sender, address(this), amount);
        emit RewardAdded(msg.sender, amount);
    }

    function governanceRecoverUnsupported(IERC20 _token, uint256 _amount, address _to) external onlyOperator {
        // do not allow to drain core tokens
        require(address(_token) != address(dark), "dark");
        require(address(_token) != address(sky), "sky");
        _token.safeTransfer(_to, _amount);
    }
}
