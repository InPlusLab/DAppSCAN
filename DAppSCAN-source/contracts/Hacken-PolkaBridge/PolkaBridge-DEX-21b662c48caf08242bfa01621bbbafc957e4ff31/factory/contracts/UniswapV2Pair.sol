// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import './interfaces/IUniswapV2Pair.sol';
import './UniswapV2ERC20.sol';
import './libraries/Math.sol';
import './libraries/UQ112x112.sol';
import './interfaces/IERC20.sol';
import './interfaces/IUniswapV2Factory.sol';

contract UniswapV2Pair is IUniswapV2Pair, UniswapV2ERC20 {
    using UQ112x112 for uint224;
    // string public name = 'PolkaBridgeAMM: Pair';
    // uint256 public constant override MINIMUM_LIQUIDITY = 10**3;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    address public override factory;
    address public override token0;
    address public override token1;

    // address ownerAddress;

    address treasury;

    uint112 private reserve0; // uses single storage slot, accessible via getReserves
    uint112 private reserve1; // uses single storage slot, accessible via getReserves
    uint32 private blockTimestampLast; // uses single storage slot, accessible via getReserves

    uint public override price0CumulativeLast;
    uint public override price1CumulativeLast;
    // uint public override kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    uint256 private unlocked = 1;
    uint256 private releaseTime;
    uint256 private lockTime = 2 days;

    modifier lock() {
        require(unlocked == 1, 'PolkaBridge AMM: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    function getReserves()
        public
        view
        override
        returns (
            uint112 _reserve0,
            uint112 _reserve1,
            uint32 _blockTimestampLast
        )
    {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function _safeTransfer(
        address token,
        address to,
        uint256 value
    ) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'PolkaBridge AMM: TRANSFER_FAILED');
    }

    constructor() {
        factory = msg.sender;
    }

    // called once by the factory at time of deployment
    function initialize(address _token0, address _token1, address _treasury) external override {
        require(msg.sender == factory, 'PolkaBridge AMM: FORBIDDEN'); // sufficient check
        token0 = _token0;
        token1 = _token1;
        // ownerAddress = _owner;
        treasury = _treasury;
    }

    // function skim(address to) external override lock {
    //     address _token0 = token0; // gas savings
    //     address _token1 = token1; // gas savings
    //     _safeTransfer(_token0, to, IERC20(_token0).balanceOf(address(this)) - reserve0);
    //     _safeTransfer(_token1, to, IERC20(_token1).balanceOf(address(this)) - reserve1);
    // }

    // force reserves to match balances
    function sync() external override lock {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }

    // update reserves and, on the first call per block, price accumulators
    function _update(uint balance0, uint balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= uint112(int112(-1)) && balance1 <= uint112(int112(-1)), 'PolkaBridge AMM: OVERFLOW');
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            price0CumulativeLast += uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            price1CumulativeLast += uint(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    // if fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k)
    // function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
    //     // address feeTo = address(0);//IUniswapV2Factory(factory).feeTo();
    //     // feeOn = feeTo != address(0);
    //     // uint _kLast = kLast; // gas savings
    //     // if (feeOn) {
    //     //     if (_kLast != 0) {
    //     //         uint rootK = Math.sqrt(uint(_reserve0) * _reserve1);
    //     //         uint rootKLast = Math.sqrt(_kLast);
    //     //         if (rootK > rootKLast) {
    //     //             uint numerator = totalSupply * (rootK - rootKLast);
    //     //             uint denominator = rootK * 5 + rootKLast;
    //     //             uint liquidity = numerator / denominator;
    //     //             if (liquidity > 0) _mint(feeTo, liquidity);
    //     //         }
    //     //     }
    //     // } else if (_kLast != 0) {
    //     //     kLast = 0;
    //     // }
    //     feeOn = false;
    //     kLast = 0;
    // }

    // this low-level function should be called from a contract which performs important safety checks
    function mint(address to) external override lock returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves(); // gas savings
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        // bool feeOn = false;//_mintFee(_reserve0, _reserve1);
        // uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        if (totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * amount1);// - MINIMUM_LIQUIDITY;
            // _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = Math.min(amount0 * totalSupply / _reserve0, amount1 * totalSupply / _reserve1);
        }
        require(liquidity > 0, 'PolkaBridge AMM: INSUFFICIENT_LIQUIDITY_MINTED');
        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);
        // if (feeOn) kLast = uint(reserve0) * reserve1; // reserve0 and reserve1 are up-to-date
        emit Mint(msg.sender, amount0, amount1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function burn(address to) external override lock returns (uint256 amount0, uint256 amount1) {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves(); // gas savings
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        uint256 balance0 = IERC20(_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(_token1).balanceOf(address(this));
        uint256 liquidity = balanceOf[address(this)];

        // bool feeOn = _mintFee(_reserve0, _reserve1);
        // uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        amount0 = liquidity * balance0 / totalSupply; // using balances ensures pro-rata distribution
        amount1 = liquidity * balance1 / totalSupply; // using balances ensures pro-rata distribution
        require(amount0 > 0 && amount1 > 0, 'PolkaBridge AMM: INSUFFICIENT_LIQUIDITY_BURNED');
        _burn(address(this), liquidity);
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);
        // if (feeOn) kLast = uint(reserve0) * reserve1; // reserve0 and reserve1 are up-to-date
        emit Burn(msg.sender, amount0, amount1, to);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function swap(uint amount0Out, uint amount1Out, address to) external override lock {
        require(amount0Out > 0 || amount1Out > 0, 'PolkaBridge AMM: INSUFFICIENT_OUTPUT_AMOUNT');
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        require(amount0Out < _reserve0 && amount1Out < _reserve1, 'PolkaBridge AMM: INSUFFICIENT_LIQUIDITY');

        uint256 balance0;
        uint256 balance1;
        {
            // scope for _token{0,1}, avoids stack too deep errors
            // address _token0 = token0;
            // address _token1 = token1;
            require(to != token0 && to != token1, 'PolkaBridge AMM: INVALID_TO');

            if (amount0Out > 0) _safeTransfer(token0, to, amount0Out); // optimistically transfer tokens
            if (amount1Out > 0) _safeTransfer(token1, to, amount1Out); // optimistically transfer tokens
            balance0 = IERC20(token0).balanceOf(address(this));
            balance1 = IERC20(token1).balanceOf(address(this));
        }
        uint256 amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, 'PolkaBridge AMM: INSUFFICIENT_INPUT_AMOUNT');
        { // scope for reserve{0,1}Adjusted, avoids stack too deep errors
            uint balance0Adjusted = balance0 * 1000 - amount0In * 2;
            uint balance1Adjusted = balance1 * 1000 - amount1In * 2;
            // require(false, string(abi.encodePacked(uint2str(_reserve0), ' : ', uint2str(_reserve1), ' : ', uint2str(balance0), ' : ', uint2str(balance1), ' : ', uint2str(amount0In), ' : ', uint2str(amount1In))));
            require(balance0Adjusted - balance1Adjusted >= uint(_reserve0) * _reserve1 * (1000**2), 'PolkaBridge AMM: K');
        }

        uint256 amount0Treasury = amount0In / 2500; // amount0In * 4 / 10000;
        uint256 amount1Treasury = amount1In / 2500; // amount1In * 4 / 10000;
        if (amount0Treasury > 0) {
            require(treasury != address(0), 'Treasury address error');
            _safeTransfer(token0, treasury, amount0Treasury);
            balance0 = balance0 - amount0Treasury;
        }
        if (amount1Treasury > 0) {
            require(treasury != address(0), 'Treasury address error');
            _safeTransfer(token1, treasury, amount1Treasury);
            balance1 = balance1 - amount1Treasury;
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    // function setTreasuryAddress(address _treasury) external override {
    //     require(msg.sender == ownerAddress, 'Only ownerAddress can set treasury');
    //     {
    //         require(block.timestamp - releaseTime >= lockTime, "current time is before release time");
    //         treasury = _treasury;
    //         releaseTime = block.timestamp;
    //         emit TreasurySet(_treasury);
    //     }
    // }
}
