pragma solidity 0.5.17;

/**
 * @title ISavingsContract
 */
contract ISavingsContract {
    uint256 public exchangeRate;
    mapping(address => uint256) public creditBalances;
    function depositSavings(uint256 _amount) external returns (uint256 creditsIssued);
    function redeem(uint256 _amount) external returns (uint256 massetReturned);
}
