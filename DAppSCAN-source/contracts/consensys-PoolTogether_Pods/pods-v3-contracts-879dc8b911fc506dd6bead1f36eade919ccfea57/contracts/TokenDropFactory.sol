// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.8.0;

// Libraries
import "./external/ProxyFactory.sol";

// Clone Contracts
import "./Pod.sol";
import "./TokenDrop.sol";

/**
 * @title TokenDropFactory (ProxyFactory) - Clones a TokenDrop Instance
 * @notice Create a TokenDrop smart contract, which is associated with Pod smart contract for distribution of an asset token (i.e. POOL).
 * @dev The PodFactory creates/initializes TokenDrop smart contract. The factory will generally be called from the PodFactory smart contract directly.
 * @author Kames Geraghty
 */
contract TokenDropFactory is ProxyFactory {
    /***********************************|
    |   Constants                       |
    |__________________________________*/
    /**
     * @notice Contract template for deploying proxied Comptrollers
     */
    TokenDrop public tokenDropInstance;

    /***********************************|
    |   Constructor                     |
    |__________________________________*/
    /**
     * @notice Initializes the TokenDropFactory.
     * @dev Initializes the Factory with a TokenDrop instance.
     */
    constructor() {
        // TokenDrop Instance
        tokenDropInstance = new TokenDrop();
    }

    /**
     * @notice Create a TokenDrop smart contract
     */
    function create(address _measure, address _asset)
        external
        returns (TokenDrop)
    {
        // TokenDrop Deployed
        TokenDrop tokenDrop =
            TokenDrop(deployMinimal(address(tokenDropInstance), ""));

        // TokenDrop Initialize
        tokenDrop.initialize(_measure, _asset);

        // Return TokenDrop addresses
        return tokenDrop;
    }
}
