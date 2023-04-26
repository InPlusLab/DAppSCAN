pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";

contract Vester {
    using SafeMath for uint;

    address public idle;
    address public recipient;

    uint public vestingAmount;
    uint public vestingBegin;
    uint public vestingCliff;
    uint public vestingEnd;

    uint public lastUpdate;

    constructor(
        address idle_,
        address recipient_,
        uint vestingAmount_,
        uint vestingBegin_,
        uint vestingCliff_,
        uint vestingEnd_
    ) public {
        require(vestingBegin_ >= block.timestamp, 'TreasuryVester::constructor: vesting begin too early');
        require(vestingCliff_ >= vestingBegin_, 'TreasuryVester::constructor: cliff is too early');
        require(vestingEnd_ > vestingCliff_, 'TreasuryVester::constructor: end is too early');

        idle = idle_;
        recipient = recipient_;

        vestingAmount = vestingAmount_;
        vestingBegin = vestingBegin_;
        vestingCliff = vestingCliff_;
        vestingEnd = vestingEnd_;

        lastUpdate = vestingBegin;

        // Delegate voting power to recipient
        IIdle(idle_).delegate(recipient_);
    }

    function setRecipient(address recipient_) public {
        require(msg.sender == recipient, 'TreasuryVester::setRecipient: unauthorized');
        recipient = recipient_;
    }

    function claim() public {
        require(block.timestamp >= vestingCliff, 'TreasuryVester::claim: not time yet');
        uint amount;
        if (block.timestamp >= vestingEnd) {
            amount = IIdle(idle).balanceOf(address(this));
        } else {
            amount = vestingAmount.mul(block.timestamp - lastUpdate).div(vestingEnd - vestingBegin);
            lastUpdate = block.timestamp;
        }
        IIdle(idle).transfer(recipient, amount);
    }

    // Add ability to delegate vote in governance
    function setDelegate(address delegatee) public {
        require(msg.sender == recipient, 'TreasuryVester::setDelegate: unauthorized');

        IIdle(idle).delegate(delegatee);
    }
}

interface IIdle {
    function balanceOf(address account) external view returns (uint);
    function transfer(address dst, uint rawAmount) external returns (bool);
    function delegate(address delegatee) external;
}
