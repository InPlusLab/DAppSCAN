pragma solidity ^0.4.24;

contract IUpgradableExchange {

    function buyRate2key() public view returns (uint);
    function sellRate2key() public view returns (uint);

    function buyTokens(
        address _beneficiary
    )
    public
    payable
    returns (uint);

    function buyStableCoinWith2key(
        uint _twoKeyUnits,
        address _beneficiary
    )
    public
    payable
    returns (uint);
}
