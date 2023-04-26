pragma solidity 0.4.23;

import '../BoomstarterPreICO.sol';

/// @title Helper for unit-testing BoomstarterPreICO - DONT use in production!
contract BoomstarterPreICOTestHelper is BoomstarterPreICO {

    function BoomstarterPreICOTestHelper(
        address[] _owners,
        address _token,
        address _beneficiary,
        bool _production
    )
        public
        BoomstarterPreICO(_owners, _token, _beneficiary, 5, _production)
    {
        // 5 seconds update interval is set in the parent constructor
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

    function setMaximumTokensSold(uint amount) public {
      c_maximumTokensSold = amount;
    }

    uint public m_time;
}
