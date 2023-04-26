// SPDX-License-Identifier: Apache-2.0

pragma solidity =0.6.12;

import "./interfaces/IUniswapV2Factory.sol";
import "./UniswapV2Pair.sol";

contract UniswapV2Factory is IUniswapV2Factory {
    address public override feeTo;
    address public override poolTo;
    address public override treasuryTo;
    address public override feeToSetter;
    address public override migrator;

    mapping(address => mapping(address => address)) public override getPair;
    address[] public override allPairs;

    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint256
    );

    constructor(address _feeToSetter) public {
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() external view override returns (uint256) {
        return allPairs.length;
    }

    function pairCodeHash() external pure returns (bytes32) {
        return keccak256(type(UniswapV2Pair).creationCode);
    }

    function createPair(address tokenA, address tokenB)
        external
        override
        returns (address pair)
    {
        require(tokenA != tokenB, "Liter: IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        require(token0 != address(0), "Liter: ZERO_ADDRESS");
        require(getPair[token0][token1] == address(0), "Liter: PAIR_EXISTS"); // single check is sufficient
        bytes memory bytecode = type(UniswapV2Pair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        UniswapV2Pair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external override {
        require(msg.sender == feeToSetter, "Liter: FORBIDDEN");
        feeTo = _feeTo;
    }

    function setPoolTo(address _poolTo) external override {
        require(msg.sender == feeToSetter, "Liter: FORBIDDEN");
        poolTo = _poolTo;
    }

    function setTreasuryTo(address _treasuryTo) external override {
        require(msg.sender == feeToSetter, "Liter: FORBIDDEN");
        treasuryTo = _treasuryTo;
    }

    function setFeeToSetter(address _feeToSetter) external override {
        require(msg.sender == feeToSetter, "Liter: FORBIDDEN");
        feeToSetter = _feeToSetter;
    }

    function setMigrator(address _migrator) external override {
        require(msg.sender == feeToSetter, "Liter: FORBIDDEN");
        migrator = _migrator;
    }
}
