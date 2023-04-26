pragma solidity 0.5.10;

import "./lib/CompoundOracleInterface.sol";
import "./OptionsUtils.sol";
import "./lib/UniswapFactoryInterface.sol";
import "./lib/UniswapExchangeInterface.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract OptionsExchange is OptionsUtils {

    uint256 constant LARGE_BLOCK_SIZE = 1651753129000;

    constructor (address _uniswapFactory, address _compoundOracle)
        OptionsUtils(_uniswapFactory, _compoundOracle)
        public
    {
    }

    // TODO: write these functions later
    function sellPTokens(uint256 _pTokens, address payoutTokenAddress) public {
        // TODO: first need to boot strap the uniswap exchange to get the address.
        // uniswap transfer input _pTokens to payoutTokens
    }

    // TODO: write these functions later
    function buyPTokens(uint256 _pTokens, address paymentTokenAddress) public payable {
        // uniswap transfer output. This transfer enough paymentToken to get desired pTokens.
    }

}
