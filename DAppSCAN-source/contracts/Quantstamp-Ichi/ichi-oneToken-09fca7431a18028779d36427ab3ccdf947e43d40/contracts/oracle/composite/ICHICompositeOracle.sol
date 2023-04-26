// SPDX-License-Identifier: Unlicensed

pragma solidity 0.7.6;

import "../OracleCommon.sol";
import "../../interface/IERC20Extended.sol";

/**
 @notice Relies on external Oracles using any price quote methodology.
 */

contract ICHICompositeOracle is OracleCommon {

    address[] public oracleContracts;
    address[] public interimTokens;

    /**
     @notice addresses and oracles define a chain of currency conversions (e.g. through ETH) that will be executed in order of declation
     @dev output of oracles is used as input for the next oracle. 
     @param description_ human-readable name has no bearing on internal logic
     @param indexToken_ a registered usdToken to use for quote indexed
     @param oracles_ a sequential list of unregisted contracts that support the IOracle interface and return quotes in any currency
     */
    constructor(address oneTokenFactory_, string memory description_, address indexToken_, address[] memory interimTokens_, address[] memory oracles_)
        OracleCommon(oneTokenFactory_, description_, indexToken_)
    {
        require(interimTokens_.length == oracles_.length, 'ICHICompositeOracle: unequal interimTokens and Oracles list lengths');
        oracleContracts = oracles_;
        interimTokens = interimTokens_;
        indexToken = indexToken_;
    }

    /**
     @notice intialization is called when the factory assigns an oracle to an asset
     @dev there is nothing to do. Deploy separate instances configured for distinct baseTokens
     */
    function init(address baseToken) external onlyModuleOrFactory override {
        for(uint i=0; i<oracleContracts.length; i++) {
            IOracle(oracleContracts[i]).init(interimTokens[i]);
        }
        emit OracleInitialized(msg.sender, baseToken, indexToken);
    }

    /**
     @notice update is called when a oneToken wants to persist observations
     @dev chain length is constrained by gas
     */
    function update(address /* token */) external override {
        for(uint i=0; i<oracleContracts.length; i++) {
            IOracle(oracleContracts[i]).update(interimTokens[i]);
        }
        // no event, for gas optimization
    }

    /**
     @notice returns equivalent amount of index tokens for an amount of baseTokens and volatility metric
     @dev volatility is calculated by the final oracle
     */
    function read(address /* token */, uint amount) public view override returns(uint amountOut, uint volatility) {
        amountOut = amount;
        for(uint i=0; i<oracleContracts.length; i++) {
            ( amountOut, volatility ) = IOracle(oracleContracts[i]).read(interimTokens[i], amountOut);
        }
    }

    /**
     @notice returns the tokens needed to reach a target usd value
     */
    function amountRequired(address /* token */, uint amountUsd) external view override returns(uint tokens, uint volatility) {
        /// @notice it is always 1:1 with no volatility
        this; // silence visibility warning
        tokens = amountUsd;
        volatility = 0;
    }
}
