//SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.4;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";


import "../libraries/Random.sol";

contract PandoPot is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    enum REWARD_STATUS {AVAILABLE, CLAIMED, EXPIRED}
    // 0 : mega, 1 : minor, 2 : leaderboard
    struct Reward {
        address owner;
        uint256[3] usdt;
        uint256[3] psr;
        uint256 expire;
        REWARD_STATUS status;
    }

    address public USDT;
    address public PSR;

    uint256 public constant PRECISION = 10000000000;
    uint256 public constant unlockPeriod = 2 * 365 * 1 days;
    uint256 public timeBomb = 2 * 30 * 1 days;
    uint256 public rewardExpireTime = 14 * 1 days;
    uint256 public megaPrizePercentage = 25;
    uint256 public minorPrizePercentage = 1;
    uint256 public lastDistribute;
    uint256 public usdtForCurrentPot;
    uint256 public PSRForCurrentPot;
    uint256 public totalPSRAllocated;
    uint256 public lastUpdatePot;

    uint256 public usdtForPreviousPot;
    uint256 public PSRForPreviousPot;

    uint256 public nTickets;
    uint256 public pendingUSDT;
    mapping (address => bool) public whitelist;
    mapping (uint256 => Reward) private rewards;

    /*----------------------------CONSTRUCTOR----------------------------*/
    constructor (address _USDT, address _PSR) {
        USDT = _USDT;
        PSR = _PSR;
        lastDistribute = block.timestamp;
        lastUpdatePot = block.timestamp;
    }

    /*----------------------------INTERNAL FUNCTIONS----------------------------*/

    function transferToken(address _token, address _receiver, uint256 _amount) internal {
        if (_amount > 0) {
            IERC20(_token).safeTransfer(_receiver, _amount);
        }
    }

    /*----------------------------EXTERNAL FUNCTIONS----------------------------*/

    function reward(uint256 _ticketNumber) external view returns(Reward memory) {
        return rewards[_ticketNumber];
    }

    function enter(address _receiver, uint256 _mega, uint256 _minor, uint256 _salt) external whenNotPaused nonReentrant  onlyWhitelist() {
        updateJackpot();
        uint256 _seed = Random.computerSeed(0) % PRECISION + 1;
        Reward memory _reward = Reward({
            owner: _receiver,
            usdt: [uint256(0), uint256(0), uint256(0)],
            psr: [uint256(0), uint256(0), uint256(0)],
            expire: block.timestamp + rewardExpireTime,
            status: REWARD_STATUS.AVAILABLE
        });
        //mega
        if (_seed <= _mega) {
            lastDistribute = block.timestamp;
            _reward.usdt[0] = usdtForCurrentPot * megaPrizePercentage / 100;
            _reward.psr[0] = PSRForCurrentPot * megaPrizePercentage / 100;
        }
        updateJackpot();

        //minor
        _seed = Random.computerSeed(_salt) % PRECISION + 1;
        if (_seed <= _minor) {
            _reward.usdt[1] = usdtForCurrentPot * minorPrizePercentage / 100;
            _reward.psr[1] = PSRForCurrentPot * minorPrizePercentage / 100;
        }
        pendingUSDT += _reward.usdt[0] + _reward.usdt[1];
        PSRForCurrentPot -= _reward.psr[0] + _reward.psr[1];

        emit NewTicket(nTickets, _reward.owner, _reward.usdt, _reward.psr, _reward.expire);
        rewards[nTickets++] = _reward;
    }


    function claim(uint256 _ticketId) external whenNotPaused nonReentrant {
        Reward storage _reward = rewards[_ticketId];
        require(_reward.status == REWARD_STATUS.AVAILABLE && _reward.expire >= block.timestamp, 'Jackpot: reward unavailable');
        _reward.status = REWARD_STATUS.CLAIMED;
        for (uint8 i = 0; i < 3; i++) {
            transferToken(USDT, _reward.owner, _reward.usdt[i]);
            transferToken(PSR, _reward.owner, _reward.psr[i]);
            pendingUSDT -= _reward.usdt[i];
        }
        emit Claimed(_ticketId, _reward.owner, _reward.usdt, _reward.psr);
    
    }

    function distribute(address[] memory _leaderboards, uint256[] memory ratios) external onlyWhitelist whenNotPaused {
        require(_leaderboards.length == ratios.length, 'Jackpot: leaderboards != ratios');
        uint256 _cur = 0;
        for (uint256 i = 0; i < ratios.length; i++) {
            _cur += ratios[i];
        }
        require(_cur == PRECISION, 'Jackpot: ratios incorrect');
        updateJackpot();
        for (uint256 i = 0; i < _leaderboards.length; i++) {
            uint256 ticketId = nTickets;
            rewards[ticketId].usdt[2] = usdtForPreviousPot * ratios[i] / PRECISION;
            rewards[ticketId].psr[2] = PSRForPreviousPot * ratios[i] / PRECISION;
            rewards[ticketId].expire = block.timestamp + rewardExpireTime;
            rewards[ticketId].status = REWARD_STATUS.AVAILABLE;
            rewards[ticketId].owner = _leaderboards[i];
            nTickets++;
            emit NewTicket(ticketId, _leaderboards[i], rewards[ticketId].usdt, rewards[ticketId].psr, rewards[ticketId].expire);
        }
        pendingUSDT += usdtForPreviousPot;
        usdtForPreviousPot = 0;
        PSRForPreviousPot = 0;
        lastDistribute = block.timestamp;
    }

    function updateJackpot() public {
        usdtForCurrentPot = IERC20(USDT).balanceOf(address(this)) - usdtForPreviousPot - pendingUSDT;
        PSRForCurrentPot += totalPSRAllocated * (block.timestamp - lastUpdatePot) / unlockPeriod;

        if (block.timestamp - lastDistribute >= timeBomb) {
            if (PSRForPreviousPot == 0 && usdtForPreviousPot == 0) {
                usdtForPreviousPot = usdtForCurrentPot * megaPrizePercentage / 100;
                PSRForPreviousPot = PSRForCurrentPot * megaPrizePercentage / 100;
                PSRForCurrentPot -= PSRForPreviousPot;
            }
        }
        lastUpdatePot = block.timestamp;
    }

    function liquidation(uint256 _ticketId) external whenNotPaused {
        Reward storage _reward = rewards[_ticketId];
        require(_reward.status == REWARD_STATUS.AVAILABLE, 'Jackpot: reward unavailable');
        if (_reward.expire < block.timestamp) {
            _reward.status = REWARD_STATUS.EXPIRED;
            for (uint8 i = 0; i < 3; i++) {
                if (_reward.psr[i] > 0 || _reward.usdt[i] > 0) {
                    pendingUSDT -= _reward.usdt[i];
                    PSRForCurrentPot += _reward.psr[i];
                }
            }
        }
    }

    function currentPot() external view returns(uint256, uint256) {
        uint256 _usdt = IERC20(USDT).balanceOf(address(this)) - usdtForPreviousPot - pendingUSDT;
        uint256 _psr = totalPSRAllocated * (block.timestamp - lastUpdatePot) / unlockPeriod + PSRForCurrentPot;
        return (_usdt, _psr);
    }

    /*----------------------------RESTRICTED FUNCTIONS----------------------------*/

    modifier onlyWhitelist() {
        require(whitelist[msg.sender] == true, 'Jackpot: caller is not in the whitelist');
        _;
    }

    function toggleWhitelist(address _addr) external onlyOwner {
        whitelist[_addr] = !whitelist[_addr];
    }

    function allocatePSR(uint256 _amount) external onlyOwner {
        totalPSRAllocated += _amount;
        IERC20(PSR).safeTransferFrom(msg.sender, address(this), _amount);
    }

    function changeTimeBomb(uint256 _second) external onlyOwner{
        timeBomb = _second;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function emergencyWithdraw() external onlyOwner whenPaused {
        IERC20 _usdt = IERC20(USDT);
        IERC20 _psr = IERC20(PSR);
        uint256 _usdtAmount = _usdt.balanceOf(address(this));
        uint256 _psrAmount = _psr.balanceOf(address(this));
        _usdt.safeTransfer(owner(), _usdtAmount);
        _psr.safeTransfer(owner(), _psrAmount);
    }
    /*----------------------------EVENTS----------------------------*/

    event NewTicket(uint256 ticketId, address user, uint256[3] usdt, uint256[3] PSR, uint256 expire);
    event Claimed(uint256 ticketId, address user, uint256[3] usdt, uint256[3] PSR);
}