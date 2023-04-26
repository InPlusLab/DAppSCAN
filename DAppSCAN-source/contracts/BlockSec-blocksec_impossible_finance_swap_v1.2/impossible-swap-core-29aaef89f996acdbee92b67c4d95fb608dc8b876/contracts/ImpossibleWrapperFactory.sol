// SPDX-License-Identifier: GPL-3
pragma solidity =0.7.6;

import './interfaces/IImpossibleWrapperFactory.sol';
import './ImpossibleWrappedToken.sol';

/**
    @title  Wrapper Factory for Impossible Swap V3
    @author Impossible Finance
    @notice This factory builds upon basic Uni V2 factory by changing "feeToSetter"
            to "governance" and adding a whitelist
    @dev    See documentation at: https://docs.impossible.finance/impossible-swap/overview
*/

contract ImpossibleWrapperFactory is IImpossibleWrapperFactory {
    address public governance;
    mapping(address => address) public override tokensToWrappedTokens;
    mapping(address => address) public override wrappedTokensToTokens;

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
     @notice Sets the address for IF governance
     @dev Can only be called by IF governance
     @param _governance The address of the new IF governance
    */
    function setGovernance(address _governance) external onlyGovernance {
        governance = _governance;
    }

    /**
     @notice Creates a pair with some ratio
     @dev underlying The address of token to wrap
     @dev ratioNumerator The numerator value of the ratio to apply for ratio * underlying = wrapped underlying
     @dev ratioDenominator The denominator value of the ratio to apply for ratio * underlying = wrapped underlying
    */
    function createPairing(
        address underlying,
        uint256 ratioNumerator,
        uint256 ratioDenominator
    ) external onlyGovernance returns (address) {
        require(
            tokensToWrappedTokens[underlying] == address(0x0) && wrappedTokensToTokens[underlying] == address(0x0),
            'IF: PAIR_EXISTS'
        );
        require(ratioDenominator != 0, 'IF: INVALID_DENOMINATOR');
        ImpossibleWrappedToken wrapper = new ImpossibleWrappedToken(underlying, ratioNumerator, ratioDenominator);
        tokensToWrappedTokens[underlying] = address(wrapper);
        wrappedTokensToTokens[address(wrapper)] = underlying;
        emit WrapCreated(underlying, address(wrapper), ratioNumerator, ratioDenominator);
        return address(wrapper);
    }

    /**
     @notice Deletes a pairing
     @notice requires supply of wrapped token to be 0
     @dev wrapper The address of the wrapper
    */
    function deletePairing(address wrapper) external onlyGovernance {
        require(ImpossibleWrappedToken(wrapper).totalSupply() == 0, 'IF: NONZERO_SUPPLY');
        address _underlying = wrappedTokensToTokens[wrapper];
        require(ImpossibleWrappedToken(wrapper).underlying() == _underlying, 'IF: INVALID_TOKEN');
        require(_underlying != address(0x0), 'IF: Address must have pair');
        delete tokensToWrappedTokens[_underlying];
        delete wrappedTokensToTokens[wrapper];
        emit WrapDeleted(_underlying, address(wrapper));
    }
}
