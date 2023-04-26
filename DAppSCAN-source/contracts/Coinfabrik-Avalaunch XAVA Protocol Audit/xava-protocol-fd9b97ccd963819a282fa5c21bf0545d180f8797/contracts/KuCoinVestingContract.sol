pragma solidity 0.6.12;

import "./IERC20.sol";
import "./math/SafeMath.sol";


contract KuCoinVestingContract {

    IERC20 public token;
    using SafeMath for uint256;

    // Address receiving tokens
    address public beneficiary;
    // Unlocking amounts, can't have length more than 10
    uint256[] public unlockingAmounts;
    // Unlocking times, can't have length more than 10
    uint256[] public unlockingTimes;
    // Markers, can't have length more than 10
    bool [] public isWithdrawn;

    constructor(
        address _beneficiary,
        uint256[] memory _unlockingAmounts,
        uint256[] memory _unlockingTimes
    )
    public
    {
        require(_beneficiary != address(0), "Beneficiary address can not be 0x0");
        require(_unlockingAmounts.length == _unlockingTimes.length, "Input arguments are not matching!");

        beneficiary = _beneficiary;
        for(uint i=0; i<_unlockingTimes.length; i++) {
            unlockingTimes.push(_unlockingTimes[i]);
            unlockingAmounts.push(_unlockingAmounts[i]);
        }
    }

    /// Deposit tokens which should be used to payout the beneficiary over time
    function depositTokens(
        uint256 amount
    )
    public
    {
        token.transferFrom(msg.sender, address(this), amount);
    }

    /// Withdraw function, takes always everything which is available at the moment
    function withdraw()
    public
    {
        uint256 totalToPay;
        for(uint i=0; i<unlockingAmounts.length; i++) {
            if(!isWithdrawn[i] && block.timestamp > unlockingTimes[i]) {
                totalToPay = totalToPay.add(unlockingAmounts[i]);
                isWithdrawn[i] = true;
            }
        }

        if(totalToPay > 0) {
            token.transfer(beneficiary, totalToPay);
        }
    }

}
