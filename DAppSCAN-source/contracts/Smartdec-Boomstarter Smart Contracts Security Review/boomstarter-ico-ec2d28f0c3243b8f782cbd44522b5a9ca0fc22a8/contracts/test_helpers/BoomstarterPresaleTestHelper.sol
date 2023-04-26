pragma solidity 0.4.23;

import '../BoomstarterPresale.sol';

/// @title Helper for unit-testing BoomstarterPresale - DONT use in production!
contract BoomstarterPresaleTestHelper is BoomstarterPresale {

    function BoomstarterPresaleTestHelper(address[] _owners, address _token,
                                          address _beneficiary, bool _production)
        public
        BoomstarterPresale(_owners, _token, _beneficiary, _production)
    {
        m_ETHPriceUpdateInterval = 5; // 5 seconds
        c_MinInvestmentInCents = 1 * 100; // $1
        m_ETHPriceInCents = 300*100; // $300
        m_leeway = 0; // no offset
    }

    function setTime(uint time) public {
        m_time = time;
    }

    function getTime() internal view returns (uint) {
        return m_time;
    }

    // override constants with test-friendly values
    function setPriceRiseTokenAmount(uint amount) public {
      c_priceRiseTokenAmount = amount;
    }

    function setMaximumTokensSold(uint amount) public {
      c_maximumTokensSold = amount;
    }

    uint public m_time;
}
