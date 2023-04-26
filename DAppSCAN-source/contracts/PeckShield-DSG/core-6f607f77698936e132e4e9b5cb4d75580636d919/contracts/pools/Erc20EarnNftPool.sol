// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/ISwapPair.sol";



contract Erc20EarnNftPool is Ownable, IERC721Receiver {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    struct Pool {
        address tokenAddress;
        bool isLpToken;
        uint256 stakeAmount;
        uint256 stakeTime;
        address nftAddress;
        uint256[] nftTokenIds;
        uint256 nftLeft;
    }
    Pool[] public pool;

    // pool id => user address => stake info list (start staking time)
    mapping (uint256 => mapping (address => uint256[])) public user;

    mapping (address => mapping (uint256 => bool)) public nftInContract;

    struct StakeView {
        uint pid;
        uint256 amount;
        uint256 beginTime;
        uint256 endTime;
        bool isCompleted;
    }

    struct PoolView {
        address tokenAddress;
        bool isLpToken;
        uint256 stakeAmount;
        uint256 stakeTime;
        address nftAddress;
        uint256[] nftTokenIds;
        uint256 nftLeft;
        address token0;
        string symbol0;
        string name0;
        uint8 decimals0;
        address token1;
        string symbol1;
        string name1;
        uint8 decimals1;
    }

    event AddPoolEvent(address indexed tokenAddress, uint256 indexed stakeAmount, uint256 stakeTime, address indexed nftAddress);
    event AddNftToPoolEvent(uint256 indexed pid, uint256[] tokenIds);
    event StakeEvent(uint256 indexed pid, address indexed user, uint256 beginTime);
    event ForceWithdrawEvent(uint256 indexed pid, address indexed user, uint256 indexed beginTime);
    event HarvestEvent(uint256 indexed pid, address indexed user, uint256 indexed tokenId);

    modifier validatePoolByPid(uint256 _pid) {
        require(_pid < pool.length, "pool does not exist");
        _;
    }

    constructor() public {

    }

    /**
     * @dev See {IERC721Receiver-onERC721Received}.
     *
     * Always returns `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function addPool(address _tokenAddress, uint256 _stakeAmount, uint256 _stakeTime, address _nftAddress, bool isLp) external onlyOwner {
        require(_tokenAddress.isContract(), "stake token address should be smart contract address");
        require(_nftAddress.isContract(), "NFT address should be smart contract address");

        uint256[] memory tokenIds;

        if(isLp) {
            require(ISwapPair(_tokenAddress).token0() != address(0), "not lp");
        }

        pool.push(Pool({
            tokenAddress: _tokenAddress,
            isLpToken: isLp,
            stakeAmount: _stakeAmount,
            stakeTime: _stakeTime,
            nftAddress: _nftAddress,
            nftTokenIds: tokenIds,
            nftLeft: 0
        }));

        emit AddPoolEvent(_tokenAddress, _stakeAmount, _stakeTime, _nftAddress);
    }

    function addNftToPool(uint256 _pid, uint256[] memory _tokenIds) external onlyOwner validatePoolByPid(_pid) {
        IERC721 nft = IERC721(pool[_pid].nftAddress);
        for (uint i = 0; i < _tokenIds.length; i++) {
            uint256 tokenId = _tokenIds[i];
            require(nft.ownerOf(tokenId) == address(this), "NFT is not owned by Stake contract");
            require(!nftInContract[pool[_pid].nftAddress][tokenId], "NFT already in Stake contract list");
            pool[_pid].nftTokenIds.push(tokenId);
            pool[_pid].nftLeft++;
            nftInContract[pool[_pid].nftAddress][tokenId] = true;
        }

        emit AddNftToPoolEvent(_pid, _tokenIds);
    }

    function getPool(uint256 _pid) external view validatePoolByPid(_pid) returns(Pool memory) {
        return pool[_pid];
    }

    function getAllPools() external view  returns(Pool[] memory) {
        return pool;
    }

    function getPoolView(uint256 _pid) public view validatePoolByPid(_pid) returns(PoolView memory poolView) {
        Pool memory p = pool[_pid];

        poolView = PoolView({
            tokenAddress: p.tokenAddress,
            isLpToken: p.isLpToken,
            stakeAmount: p.stakeAmount,
            stakeTime: p.stakeTime,
            nftAddress: p.nftAddress,
            nftTokenIds: p.nftTokenIds,
            nftLeft: p.nftLeft,
            token0: address(0),
            symbol0: "",
            name0: "",
            decimals0: 0,
            token1: address(0),
            symbol1: "",
            name1: "",
            decimals1: 0
        });

        if(p.isLpToken) {
            address lpToken = p.tokenAddress;
            ERC20 token0 = ERC20(ISwapPair(lpToken).token0());
            ERC20 token1 = ERC20(ISwapPair(lpToken).token1());
            poolView.token0 = address(token0);
            poolView.symbol0 = token0.symbol();
            poolView.name0 = token0.name();
            poolView.decimals0 = token0.decimals();
            poolView.token1 = address(token1);
            poolView.symbol1 = token1.symbol();
            poolView.name1 = token1.name();
            poolView.decimals1 = token1.decimals();
        } else {
            ERC20 token = ERC20(p.tokenAddress);
            poolView.token0 = p.tokenAddress;
            poolView.symbol0 = token.symbol();
            poolView.name0 = token.name();
            poolView.decimals0 = token.decimals();
        }
    }

    function getAllPoolViews() external view  returns(PoolView[] memory) {
        PoolView[] memory views = new PoolView[](pool.length);
        for (uint256 i = 0; i < pool.length; i++) {
            views[i] = getPoolView(i);
        }
        return views;
    }

    function stake(uint256 _pid) external validatePoolByPid(_pid) {
        require(pool[_pid].nftLeft > 0, "no NFT to earn");

        IERC20 token = IERC20(pool[_pid].tokenAddress);
        require(token.balanceOf(msg.sender) >= pool[_pid].stakeAmount, "out of balance");
        require(token.allowance(msg.sender, address(this)) >= pool[_pid].stakeAmount, "not enough permission to stake token");

        pool[_pid].nftLeft--;
        user[_pid][msg.sender].push(block.timestamp);

        uint256 oldBal = token.balanceOf(address(this));
        require(token.transferFrom(msg.sender, address(this), pool[_pid].stakeAmount), "transfer from staking token's owner error");
        uint256 realAmount = token.balanceOf(address(this)).sub(oldBal);
        require(realAmount >= pool[_pid].stakeAmount, "transfer amount not match");

        emit StakeEvent(_pid, msg.sender, block.timestamp);
    }

    function forceWithdraw(uint256 _pid, uint256 _sid) external validatePoolByPid(_pid) {
        require(_sid < user[_pid][msg.sender].length, "staking is not existed");
        uint256 beginTime = user[_pid][msg.sender][_sid];
        require(block.timestamp < beginTime + pool[_pid].stakeTime, "staking is ended");

        IERC20 token = IERC20(pool[_pid].tokenAddress);
        require(token.balanceOf(address(this)) >= pool[_pid].stakeAmount, "out of contract balance");
        removeFromUserList(_pid, _sid);
        pool[_pid].nftLeft++;

        token.safeTransfer(msg.sender, pool[_pid].stakeAmount);

        emit ForceWithdrawEvent(_pid, msg.sender, beginTime);
    }

    function harvest(uint256 _pid, uint256 _sid) external validatePoolByPid(_pid) {
        require(_sid < user[_pid][msg.sender].length, "staking is not existed");
        require(block.timestamp >= user[_pid][msg.sender][_sid] + pool[_pid].stakeTime, "staking is not due");
        require(pool[_pid].nftTokenIds.length > 0, "no nft left");

        IERC721 nft = IERC721(pool[_pid].nftAddress);
        uint256 tokenIdIdx = genRandomTokenId(_pid);
        uint256 tokenId = pool[_pid].nftTokenIds[tokenIdIdx];
        require(nft.ownerOf(tokenId) == address(this), "stake contract not own NFT");
        removeFromTokenIdList(_pid, tokenIdIdx);

        IERC20 token = IERC20(pool[_pid].tokenAddress);
        require(token.balanceOf(address(this)) >= pool[_pid].stakeAmount, "out of contract balance");
        removeFromUserList(_pid, _sid);

        nft.safeTransferFrom(address(this), msg.sender, tokenId);
        token.safeTransfer(msg.sender, pool[_pid].stakeAmount);

        emit HarvestEvent(_pid, msg.sender, tokenId);
    }

    /*
    function withdrawTokenByOwner(uint256 _pid, uint256 _sid, address _to) external onlyOwner validatePoolByPid(_pid) {
        require(_sid < user[_pid][_to].length, "staking is not existed");

        IERC20 token = IERC20(pool[_pid].tokenAddress);
        uint256 amount = pool[_pid].stakeAmount <= token.balanceOf(address(this)) ? pool[_pid].stakeAmount : token.balanceOf(address(this));
        removeFromUserList(_pid, _sid);
        pool[_pid].nftLeft++;

        token.safeTransfer(_to, amount);
    }

    
    function withdrawNftByOwner(uint256 _pid, uint256 _tokenId, address _to) external onlyOwner validatePoolByPid(_pid) {
        require(pool[_pid].nftLeft > 0, "no available NFT to withdraw");
        uint idx = 0;
        bool found = false;
        IERC721 nft = IERC721(pool[_pid].nftAddress);
        while (idx < pool[_pid].nftTokenIds.length) {
            if (pool[_pid].nftTokenIds[idx] == _tokenId) {
                removeFromTokenIdList(_pid, idx);
                pool[_pid].nftLeft--;
                require(nft.ownerOf(_tokenId) == address(this), "NFT is not owned by contract");
                nft.safeTransferFrom(address(this), _to, _tokenId);
                found = true;
                break;
            }
            idx++;
        }
        require(found, "NFT is not existed in pool");
    }
    */

    function getUserStakeCnt(uint256 _pid, address _userAddr) public view validatePoolByPid(_pid) returns(uint) {
        return user[_pid][_userAddr].length;
    }

    function getUserStake(uint256 _pid, address _userAddr, uint256 _index) public view validatePoolByPid(_pid)
    returns(uint256 stakeAmount, uint256 stakeTime, uint256 endTime, bool isCompleted) {
        require(_index < user[_pid][_userAddr].length, "staking is not existed");
        endTime = user[_pid][_userAddr][_index] + pool[_pid].stakeTime;
        if (block.timestamp >= endTime) {
            isCompleted = true;
        }
        return (pool[_pid].stakeAmount, user[_pid][_userAddr][_index], endTime, isCompleted);
    }

    function getUserStakes(uint256 _pid, address _userAddr) public view validatePoolByPid(_pid)
    returns(StakeView[] memory stakes){
        uint cnt = getUserStakeCnt(_pid, _userAddr);
        if(cnt == 0) {
            return stakes;
        }

        stakes = new StakeView[](cnt);
        for(uint i = 0; i < cnt; i++) {
            (uint256 stakeAmount,
            uint256 stakeTime,
            uint256 endTime,
            bool isCompleted) = getUserStake(_pid, _userAddr, i);

            stakes[i] = StakeView({
                pid: _pid,
                amount: stakeAmount,
                beginTime: stakeTime,
                endTime: endTime,
                isCompleted: isCompleted
            });
        }
    }

    function getPoolAmount(uint256 _pid) public view validatePoolByPid(_pid) returns(uint256) {
        return pool[_pid].stakeAmount;
    }

    function getPoolNftLeft(uint256 _pid) public view validatePoolByPid(_pid) returns(uint256) {
        return pool[_pid].nftLeft;
    }

    function getNftListLength(uint256 _pid) public view validatePoolByPid(_pid) returns(uint256) {
        return pool[_pid].nftTokenIds.length;
    }

    function getNftList(uint256 _pid) public view validatePoolByPid(_pid) returns(uint256[] memory) {
        return pool[_pid].nftTokenIds;
    }

    function genRandomTokenId(uint256 _pid) private view returns(uint256) {
        return uint256(keccak256(abi.encodePacked(block.timestamp))) % pool[_pid].nftTokenIds.length;
    }

    function removeFromUserList(uint256 _pid, uint _sid) private {
        user[_pid][msg.sender][_sid] = user[_pid][msg.sender][user[_pid][msg.sender].length - 1];
        user[_pid][msg.sender].pop();
    }

    function removeFromTokenIdList(uint256 _pid, uint256 _index) private {
        nftInContract[pool[_pid].nftAddress][pool[_pid].nftTokenIds[_index]] = false;
        pool[_pid].nftTokenIds[_index] = pool[_pid].nftTokenIds[pool[_pid].nftTokenIds.length - 1];
        pool[_pid].nftTokenIds.pop();
    }
}


