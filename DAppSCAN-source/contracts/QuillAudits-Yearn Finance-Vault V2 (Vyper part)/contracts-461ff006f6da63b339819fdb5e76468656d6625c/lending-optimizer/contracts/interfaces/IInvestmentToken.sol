pragma solidity ^0.6.2;

interface IInvestmentToken {
    function isInvestmentToken(address _investmentToken)
        external
        view
        returns (bool);

    function removeInvestmentToken(address _investmentToken) external;

    function addInvestmentToken(address _investmentToken) external;
}
