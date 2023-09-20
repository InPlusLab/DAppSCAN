//SPDX License Identifier: MIT

pragma solidity 0.8.0;

// We dont use Reentrancy Guard here because we only call the stakeToken contract which is assumed to be non-malicious
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract LockedStakingRewards is Ownable {
    IERC20 public constant stakeToken = IERC20(0x8765b1A0eb57ca49bE7EACD35b24A574D0203656);

    uint256 public constant depositDuration = 7 days;
    uint256 private constant basisPoints = 1e4;
    
    struct Pool {
        uint256 tokenPerShareMultiplier;
        bool isTerminated;
        uint256 cycleDuration;
        uint256 startOfDeposit;
        uint256 tokenPerShare;
    }

    mapping(uint256 => Pool) public pool;

    mapping(address => mapping(uint256 => uint256)) private _shares;

    // SWC-128-DoS With Block Gas Limit: L30 - L32
    constructor(Pool[] memory _initialPools) {
        for (uint256 i = 0; i < _initialPools.length; i++) {
            createPool(i, _initialPools[i]);
        }
        transferOwnership(0x2a9Da28bCbF97A8C008Fd211f5127b860613922D);
    }

        ///////// Transformative functions ///////////
    function receiveApproval
    (
        address _sender,
        uint256 _amount,
        address _stakeToken,
        bytes memory data
    )
        external
    {
        uint256 _pool;
        assembly {
            _pool := mload(add(data, 0x20))
        }
        require(isTransferPhase(_pool), "pool is locked currently");

        require(stakeToken.transferFrom(_sender, address(this), _amount));
        _shares[_sender][_pool] += _amount * basisPoints / pool[_pool].tokenPerShare;
        emit Staked(_sender, _pool, _amount);
    }

    function withdraw(uint256 _sharesAmount, uint256 _pool) external {
        require(isTransferPhase(_pool), "pool is locked currently");
        require(_sharesAmount <= _shares[msg.sender][_pool], "cannot withdraw more than balance");

        uint256 _tokenAmount = sharesToToken(_sharesAmount, _pool);
        _shares[msg.sender][_pool] -= _sharesAmount;
        require(stakeToken.transfer(msg.sender, _tokenAmount));
        emit Unstaked(msg.sender, _pool, _tokenAmount);
    }

    function updatePool(uint256 _pool) external {
        require(block.timestamp > pool[_pool].startOfDeposit + depositDuration, "can only update after depositDuration");
        require(!pool[_pool].isTerminated, "can not terminated pools");

        pool[_pool].startOfDeposit += pool[_pool].cycleDuration;
        pool[_pool].tokenPerShare = pool[_pool].tokenPerShare * pool[_pool].tokenPerShareMultiplier / basisPoints;
        emit PoolUpdated(_pool, pool[_pool].startOfDeposit, pool[_pool].tokenPerShare);
    }

        ///////////// Restricted Access Functions /////////////

    function updateTokenPerShareMultiplier(uint256 _pool, uint256 newTokenPerShareMultiplier) external onlyOwner {
        require(isTransferPhase(_pool), "pool only updateable during transfer phase");
        pool[_pool].tokenPerShareMultiplier = newTokenPerShareMultiplier;
    }

    function terminatePool(uint256 _pool) public onlyOwner {
        pool[_pool].isTerminated = true;
        emit PoolKilled(_pool);
    }

    function createPool(uint256 _pool, Pool memory pool_) public onlyOwner {
        require(pool[_pool].cycleDuration == 0, "cannot override an existing pool");
        pool[_pool] = pool_;
        emit PoolUpdated(_pool, pool[_pool].startOfDeposit, pool[_pool].tokenPerShare);
    }

        ///////////// View Functions /////////////

    function isTransferPhase(uint256 _pool) public view returns(bool) {
        return(
            (block.timestamp > pool[_pool].startOfDeposit &&
            block.timestamp < pool[_pool].startOfDeposit + depositDuration) ||
            pool[_pool].isTerminated
        );
    }

    function getPoolInfo(uint256 _pool) public view returns(bool, uint256) {
        return (isTransferPhase(_pool), pool[_pool].startOfDeposit);
    }

    function viewUserShares(address _user, uint256 _pool) public view returns(uint256) {
        return _shares[_user][_pool];
    }

    function viewUserTokenAmount(address _user, uint256 _pool) public view returns(uint256) {
        return viewUserShares(_user, _pool) * pool[_pool].tokenPerShare / basisPoints;
    }

    function sharesToToken(uint256 _sharesAmount, uint256 _pool) public view returns(uint256) {
        return _sharesAmount * pool[_pool].tokenPerShare / basisPoints;
    }

    function tokenToShares(uint256 _tokenAmount, uint256 _pool) public view returns(uint256) {
        return _tokenAmount * basisPoints / pool[_pool].tokenPerShare;
    }

    function getUserTokenAmountAfter(address _user, uint256 _pool) public view returns(uint256) {
        if(block.timestamp > pool[_pool].startOfDeposit) {
            return sharesToToken(_shares[_user][_pool], _pool) * pool[_pool].tokenPerShareMultiplier / basisPoints;
        }
        return sharesToToken(_shares[_user][_pool], _pool);
    }


        ///////////// Events /////////////
    
    event Staked(address indexed staker, uint256 indexed pool, uint256 amount);
    event Unstaked(address indexed staker, uint256 indexed pool, uint256 amount);
    event PoolUpdated(uint256 indexed pool, uint256 newDepositStart, uint256 newTokenPerShare);
    event PoolKilled(uint256 indexed pool);

        ///////////// SnapshotHelper /////////////
    IERC20 constant private vest = IERC20(0x29Fb510fFC4dB425d6E2D22331aAb3F31C1F1771);

    function balanceOf(address _user) external view returns(uint256) {
        uint256 sum = vest.balanceOf(_user);
        for(uint i = 0; i < 5; i++) {
            sum += viewUserTokenAmount(_user, i);
        }
        return sum;
    }
}