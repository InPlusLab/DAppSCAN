// SPDX-License-Identifier: MIT
pragma solidity =0.5.16;

import './interfaces/IShibaFactory.sol';
import './ShibaPair.sol';

contract ShibaFactory is IShibaFactory {
    bytes32 public constant INIT_CODE_PAIR_HASH = keccak256(abi.encodePacked(type(ShibaPair).creationCode));

    address public feeTo;
    address public feeToSetter;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;
    address private _owner;
    uint16 private _feeAmount;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    constructor(address _feeTo, address owner, uint16 _feePercent) public {
        feeToSetter = owner;
        feeTo = _feeTo;
        _owner = owner;
        _feeAmount = _feePercent;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, 'ShibaSwap: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'ShibaSwap: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'ShibaSwap: PAIR_EXISTS'); // single check is sufficient
        bytes memory bytecode = type(ShibaPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IShibaPair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, 'ShibaSwap: FORBIDDEN');
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, 'ShibaSwap: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }

    function feeAmount() external view returns (uint16){
        return _feeAmount;
    }

    function setFeeAmount(uint16 _newFeeAmount) external{
        // This parameter allow us to lower the fee which will be send to the feeManager
        // 20 = 0.20% (all fee goes directly to the feeManager)
        // If we update it to 10 for example, 0.10% are going to LP holder and 0.10% to the feeManager
        require(msg.sender == owner(), "caller is not the owner");
        require (_newFeeAmount <= 20, "amount too big");
        _feeAmount = _newFeeAmount;
    }
}
