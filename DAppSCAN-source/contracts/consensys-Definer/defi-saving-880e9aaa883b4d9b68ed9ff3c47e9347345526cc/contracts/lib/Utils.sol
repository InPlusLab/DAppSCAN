pragma solidity 0.5.14;

import "../config/GlobalConfig.sol";

library Utils{

    function _isETH(address globalConfig, address _token) public view returns (bool) {
        return GlobalConfig(globalConfig).constants().ETH_ADDR() == _token;
    }

    function getDivisor(address globalConfig, address _token) public view returns (uint256) {
        if(_isETH(globalConfig, _token)) return GlobalConfig(globalConfig).constants().INT_UNIT();
        return 10 ** uint256(GlobalConfig(globalConfig).tokenInfoRegistry().getTokenDecimals(_token));
    }

}