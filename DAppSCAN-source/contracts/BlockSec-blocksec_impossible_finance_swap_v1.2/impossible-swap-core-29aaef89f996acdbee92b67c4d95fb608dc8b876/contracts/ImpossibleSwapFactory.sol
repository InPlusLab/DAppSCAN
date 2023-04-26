// SPDX-License-Identifier: GPL-3
pragma solidity =0.7.6;

import './interfaces/IImpossibleSwapFactory.sol';
import './ImpossiblePair.sol';
import './ImpossibleWrappedToken.sol';

/**
    @title  Swap Factory for Impossible Swap V3
    @author Impossible Finance
    @notice This factory builds upon basic Uni V2 factory by changing "feeToSetter"
            to "governance" and adding a whitelist
    @dev    See documentation at: https://docs.impossible.finance/impossible-swap/overview
*/

contract ImpossibleSwapFactory is IImpossibleSwapFactory {
    address public override feeTo;
    address public override governance;
    address public router;
    bool public whitelist;
    mapping(address => bool) public approvedTokens;

    mapping(address => mapping(address => address)) public override getPair;
    address[] public override allPairs;

    /**
     @notice The constructor for the IF swap factory
     @param _governance The address for IF Governance
    */
    constructor(address _governance) {
        governance = _governance;
    }

    modifier onlyGovernance() {
        require(msg.sender == governance, 'IF: FORBIDDEN');
        _;
    }

    /**
     @notice The constructor for the IF swap factory
     @dev _governance The address for IF Governance
     @return uint256 The current number of pairs in the IF swap
    */
    function allPairsLength() external view override returns (uint256) {
        return allPairs.length;
    }

    /**
     @notice Sets router address in factory
     @dev Router is checked in pair contracts to ensure calls are from IF routers only
     @dev Can only be set by IF governance
     @param _router The address of the IF router
    */
    function setRouter(address _router) external onlyGovernance {
        router = _router;
    }

    /**
     @notice Either allow or stop a token from being a valid token for new pair contracts
     @dev Changes can only be made by IF governance
     @param token The address of the token
     @param allowed The boolean to include/exclude this token in the whitelist
    */
    function changeTokenAccess(address token, bool allowed) external onlyGovernance {
        approvedTokens[token] = allowed;
    }

    /**
     @notice Turns on or turns off the whitelist feature
     @dev Can only be set by IF governance
     @param b The boolean that whitelist is set to
    */
    function setWhitelist(bool b) external onlyGovernance {
        whitelist = b;
    }

    /**
     @notice Creates a new Impossible Pair contract
     @dev If whitelist is on, can only use approved tokens in whitelist
     @dev tokenA must not be equal to tokenB
     @param tokenA The address of token A. Token A will be in the new Pair contract
     @param tokenB The address of token B. Token B will be in the new Pair contract
     @return pair The address of the created pair containing token A and token B
    */
    function createPair(address tokenA, address tokenB) external override returns (address pair) {
        if (whitelist) {
            require(approvedTokens[tokenA] && approvedTokens[tokenB], 'IF: RESTRICTED_TOKENS');
        }
        require(tokenA != tokenB, 'IF: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'IF: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'IF: PAIR_EXISTS');

        bytes memory bytecode = type(ImpossiblePair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }

        IImpossiblePair(pair).initialize(token0, token1, router);

        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    /**
     @notice Sets the address that fees from the swap are paid to
     @dev Can only be called by IF governance
     @param _feeTo The address that will receive swap fees
    */
    function setFeeTo(address _feeTo) external override onlyGovernance {
        feeTo = _feeTo;
    }

    /**
     @notice Sets the address for IF governance
     @dev Can only be called by IF governance
     @param _governance The address of the new IF governance
    */
    function setGovernance(address _governance) external override onlyGovernance {
        governance = _governance;
    }
}
