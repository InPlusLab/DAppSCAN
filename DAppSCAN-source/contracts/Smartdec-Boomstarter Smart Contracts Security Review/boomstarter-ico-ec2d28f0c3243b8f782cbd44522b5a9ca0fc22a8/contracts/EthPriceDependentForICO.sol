pragma solidity 0.4.23;

import "./EthPriceDependent.sol";

contract EthPriceDependentForICO is EthPriceDependent {

    /// @dev overridden price lifetime logic
    function priceExpired() public view returns (bool) {
        return (getTime() > m_ETHPriceLastUpdate + m_ETHPriceLifetime);
    }

    /// @dev how long before price becomes invalid
    uint public m_ETHPriceLifetime = 60*60*12;
}
