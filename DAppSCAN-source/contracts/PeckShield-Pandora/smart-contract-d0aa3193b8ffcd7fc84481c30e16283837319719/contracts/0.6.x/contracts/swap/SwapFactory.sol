// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;
import "@openzeppelin/contracts/math/SafeMath.sol";
import '../interfaces/ISwapFactory.sol';
import './SwapPair.sol';

contract SwapFactory is ISwapFactory {
    using SafeMath for uint256;
    address public override feeTo;
    address public override feeToSetter;
    uint256 public override feeToRate = 0;

    mapping(address => mapping(address => address)) public override getPair;
    address[] public override allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

    constructor() public {
        feeToSetter = msg.sender;
    }

    function allPairsLength() external view override returns (uint256) {
        return allPairs.length;
    }

    function pairCodeHash() external pure returns (bytes32) {
        return keccak256(type(SwapPair).creationCode);
    }

    function createPair(address tokenA, address tokenB) external override returns (address pair) {
        require(tokenA != tokenB, 'SwapFactory: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'SwapFactory: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'SwapFactory: PAIR_EXISTS'); // single check is sufficient
        bytes memory bytecode = type(SwapPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        SwapPair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external override {
        require(msg.sender == feeToSetter, 'SwapFactory: FORBIDDEN');
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external override {
        require(msg.sender == feeToSetter, 'SwapFactory: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }

    function setFeeToRate(uint256 _rate) external override {
        require(msg.sender == feeToSetter, 'SwapFactory: FORBIDDEN');
        require(_rate > 0, 'SwapFactory: FEE_TO_RATE_OVERFLOW');
        feeToRate = _rate.sub(1);
    }
}
