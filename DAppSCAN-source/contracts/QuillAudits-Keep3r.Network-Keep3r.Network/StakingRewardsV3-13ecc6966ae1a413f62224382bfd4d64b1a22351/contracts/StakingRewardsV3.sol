// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

library Math {
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

library PoolAddress {
    bytes32 internal constant POOL_INIT_CODE_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

    struct PoolKey {
        address token0;
        address token1;
        uint24 fee;
    }

    function computeAddress(address factory, PoolKey memory key) internal pure returns (address pool) {
        require(key.token0 < key.token1);
        pool = address(
            uint160(uint256(
                keccak256(
                    abi.encodePacked(
                        hex'ff',
                        factory,
                        keccak256(abi.encode(key.token0, key.token1, key.fee)),
                        POOL_INIT_CODE_HASH
                    )
                )
            )
        ));
    }
}

interface erc20 {
    function transfer(address recipient, uint amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint amount) external returns (bool);
    function balanceOf(address) external view returns (uint);
}

interface PositionManagerV3 {
    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );
    function safeTransferFrom(address from, address to, uint tokenId) external;

    function ownerOf(uint tokenId) external view returns (address);
    function transferFrom(address from, address to, uint tokenId) external;
     function collect(CollectParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1);
}

interface UniV3 {
    function snapshotCumulativesInside(int24 tickLower, int24 tickUpper)
        external
        view
        returns (
            int56 tickCumulativeInside,
            uint160 secondsPerLiquidityInsideX128,
            uint32 secondsInside
        );
    function liquidity() external view returns (uint128);
}

contract StakingRewardsV3 {

    address immutable public reward;
    address immutable public pool;

    address constant factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    PositionManagerV3 constant nftManager = PositionManagerV3(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    uint constant DURATION = 7 days;

    uint rewardRate;
    uint periodFinish;
    uint lastUpdateTime;
    uint rewardPerSecondStored;

    mapping(uint => uint) public tokenRewardPerSecondPaid;
    mapping(uint => uint) public rewards;

    address immutable owner;

    struct time {
        uint32 timestamp;
        uint32 secondsInside;
        uint160 secondsPerLiquidityInside;
    }

    mapping(uint => time) public elapsed;
    mapping(uint => address) public owners;
    mapping(address => uint[]) public tokenIds;
    mapping(uint => uint) public liquidityOf;
    uint public totalLiquidity;

    event RewardPaid(address indexed sender, uint tokenId, uint reward);
    event RewardAdded(address indexed sender, uint reward);
    event Deposit(address indexed sender, uint tokenId, uint liquidity);
    event Withdraw(address indexed sender, uint tokenId, uint liquidity);
    event Collect(address indexed sender, uint tokenId, uint amount0, uint amount1);

    constructor(address _reward, address _pool) {
        reward = _reward;
        pool = _pool;
        owner = msg.sender;
    }

    function getTokenIds(address _owner) external view returns (uint[] memory) {
        return tokenIds[_owner];
    }

    function lastTimeRewardApplicable() public view returns (uint) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerSecond() public view returns (uint) {
        return rewardPerSecondStored + ((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate);
    }

    function collect(uint tokenId) external {
        _collect(tokenId);
    }

    function _collect(uint tokenId) internal {
        PositionManagerV3.CollectParams memory _claim = PositionManagerV3.CollectParams(tokenId, owner, type(uint128).max, type(uint128).max);
        (uint amount0, uint amount1) = nftManager.collect(_claim);
        emit Collect(msg.sender, tokenId, amount0, amount1);
    }

    function getSecondsInside(uint tokenId) external view returns (uint160 secondsPerLiquidityInside, uint32 secondsInside) {
        return _getSecondsInside(tokenId);
    }

    function earned(uint tokenId) public view returns (uint claimable, uint32 secondsInside, uint160 secondsPerLiquidityInside) {
        uint _reward = rewardPerSecond() - tokenRewardPerSecondPaid[tokenId];
        claimable = rewards[tokenId];
        time memory _elapsed = elapsed[tokenId];
        (secondsPerLiquidityInside, secondsInside) = _getSecondsInside(tokenId);
        uint _maxSecondsInside = lastUpdateTime - Math.min(_elapsed.timestamp, periodFinish);
        uint _secondsInside = Math.min((secondsPerLiquidityInside - _elapsed.secondsPerLiquidityInside) * liquidityOf[tokenId], _maxSecondsInside);
        uint _fullSecondsInside = secondsInside - _elapsed.secondsInside;
        if (_fullSecondsInside > _maxSecondsInside && _secondsInside > 0) {
            _secondsInside = _secondsInside * _maxSecondsInside / _fullSecondsInside;
        }
        if (totalLiquidity > 0 && _secondsInside > 0) {
            claimable += (_reward * _secondsInside * UniV3(pool).liquidity() / totalLiquidity);
        }
    }

    function getRewardForDuration() external view returns (uint) {
        return rewardRate * DURATION;
    }

    function deposit(uint tokenId) external update(tokenId) {
        (,,address token0, address token1,uint24 fee,,,uint128 _liquidity,,,,) = nftManager.positions(tokenId);
        address _pool = PoolAddress.computeAddress(factory,PoolAddress.PoolKey({token0: token0, token1: token1, fee: fee}));

        require(pool == _pool);
        require(_liquidity > 0);

        liquidityOf[tokenId] = _liquidity;
        totalLiquidity += _liquidity;
        owners[tokenId] = msg.sender;
        tokenIds[msg.sender].push(tokenId);

        nftManager.transferFrom(msg.sender, address(this), tokenId);

        emit Deposit(msg.sender, tokenId, _liquidity);
    }

    function _findIndex(uint[] memory array, uint element) internal pure returns (uint i) {
        for (i = 0; i < array.length; i++) {
            if (array[i] == element) {
                break;
            }
        }
    }

    function _remove(uint[] storage array, uint element) internal {
        uint _index = _findIndex(array, element);
        uint _length = array.length;
        if (_index >= _length) return;
        if (_index < _length-1) {
            array[_index] = array[_length-1];
        }

        array.pop();
    }

    function withdraw(uint tokenId) public update(tokenId) {
        _collect(tokenId);
        _withdraw(tokenId);
    }

    function _withdraw(uint tokenId) internal {
        require(owners[tokenId] == msg.sender);
        uint _liquidity = liquidityOf[tokenId];
        liquidityOf[tokenId] = 0;
        totalLiquidity -= _liquidity;
        owners[tokenId] = address(0);
        _remove(tokenIds[msg.sender], tokenId);
        nftManager.safeTransferFrom(address(this), msg.sender, tokenId);

        emit Withdraw(msg.sender, tokenId, _liquidity);
    }

    function getRewards() external {
        uint[] memory _tokens = tokenIds[msg.sender];
        for (uint i = 0; i < _tokens.length; i++) {
            getReward(_tokens[i]);
        }
    }

    function getReward(uint tokenId) public update(tokenId) {
        _collect(tokenId);
        uint _reward = rewards[tokenId];
        if (_reward > 0) {
            rewards[tokenId] = 0;
            _safeTransfer(reward, _getRecipient(tokenId), _reward);

            emit RewardPaid(msg.sender, tokenId, _reward);
        }
    }

    function _getRecipient(uint tokenId) internal view returns (address) {
        if (owners[tokenId] != address(0)) {
            return owners[tokenId];
        } else {
            return nftManager.ownerOf(tokenId);
        }
    }

    function exit() external {
        uint[] memory _tokens = tokenIds[msg.sender];
        for (uint i = 0; i < _tokens.length; i++) {
            getReward(_tokens[i]);
            withdraw(_tokens[i]);
        }
    }

    function withdraw() external {
        uint[] memory _tokens = tokenIds[msg.sender];
        for (uint i = 0; i < _tokens.length; i++) {
            withdraw(_tokens[i]);
        }
    }

    function exit(uint tokenId) public {
        getReward(tokenId);
        withdraw(tokenId);
    }

    function emergencyWithdraw(uint tokenId) external {
        rewards[tokenId] = 0;
        _withdraw(tokenId);
    }

    function notify(uint amount) external update(0) {
        require(msg.sender == owner);
        if (block.timestamp >= periodFinish) {
            rewardRate = amount / DURATION;
        } else {
            uint _remaining = periodFinish - block.timestamp;
            uint _leftover = _remaining * rewardRate;

            rewardRate = (amount + _leftover) / DURATION;
        }

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + DURATION;

        _safeTransferFrom(reward, msg.sender, address(this), amount);
        emit RewardAdded(msg.sender, amount);
    }

    modifier update(uint tokenId) {
        uint _rewardPerSecondStored = rewardPerSecond();
        uint _lastUpdateTime = lastTimeRewardApplicable();
        rewardPerSecondStored = _rewardPerSecondStored;
        lastUpdateTime = _lastUpdateTime;
        if (tokenId != 0) {
            (uint _reward, uint32 _secondsInside, uint160 _secondsPerLiquidityInside) = earned(tokenId);
            tokenRewardPerSecondPaid[tokenId] = _rewardPerSecondStored;
            rewards[tokenId] = _reward;

            if (elapsed[tokenId].timestamp < _lastUpdateTime) {
                elapsed[tokenId] = time(uint32(_lastUpdateTime), _secondsInside, _secondsPerLiquidityInside);
            }
        }
        _;
    }

    function _getSecondsInside(uint256 tokenId) internal view returns (uint160 secondsPerLiquidityInside, uint32 secondsInside) {
        (,,,,,int24 tickLower,int24 tickUpper,,,,,) = nftManager.positions(tokenId);
        (,secondsPerLiquidityInside,secondsInside) = UniV3(pool).snapshotCumulativesInside(tickLower, tickUpper);
    }

    function _safeTransfer(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(erc20.transfer.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }

    function _safeTransferFrom(address token, address from, address to, uint256 value) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(erc20.transferFrom.selector, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }
}
