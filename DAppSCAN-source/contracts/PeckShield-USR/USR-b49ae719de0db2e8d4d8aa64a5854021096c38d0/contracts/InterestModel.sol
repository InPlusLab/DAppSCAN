pragma solidity 0.5.12;

import './library/Ownable';

contract InterestModel is Ownable {

    uint public interestRate;

    event SetInterestRate(address indexed admin, uint indexed InterestRate, uint indexed oldInterestRate);

    function setInterestRate(uint _interestRate) external onlyManager {
        require(interestRate != _interestRate, "setInterestRate: Old and new values cannot be the same.");
        uint _oldInterestRate = interestRate;
        interestRate = _interestRate;
        emit SetInterestRate(msg.sender, _interestRate, _oldInterestRate);
    }

    function getInterestRate() external view returns (uint) {

        return interestRate;
    }
}
