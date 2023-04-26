pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract TreasuryVester is Ownable {
    using SafeMath for uint256;

    address public immutable blid;
    address public recipient;

    uint256 public immutable vestingAmount;
    uint256 public immutable vestingBegin;
    uint256 public immutable vestingCliff;
    uint256 public immutable vestingEnd;

    uint256 public lastUpdate;

    constructor(
        address blid_,
        address recipient_,
        uint256 vestingAmount_,
        uint256 vestingBegin_,
        uint256 vestingCliff_,
        uint256 vestingEnd_
    ) {
        require(vestingBegin_ >= block.timestamp, "TreasuryVester::constructor: vesting begin too early");
        require(vestingCliff_ >= vestingBegin_, "TreasuryVester::constructor: cliff is too early");
        require(vestingEnd_ > vestingCliff_, "TreasuryVester::constructor: end is too early");

        blid = blid_;
        recipient = recipient_;

        vestingAmount = vestingAmount_;
        vestingBegin = vestingBegin_;
        vestingCliff = vestingCliff_;
        vestingEnd = vestingEnd_;

        lastUpdate = vestingBegin_;
    }

    function setRecipient(address recipient_) public {
        require(msg.sender == owner(), "TreasuryVester::setRecipient: unauthorized");
        recipient = recipient_;
    }

    function claim() public {
        require(block.timestamp >= vestingCliff, "TreasuryVester::claim: not time yet");
        uint256 amount;
        if (block.timestamp >= vestingEnd) {
            amount = IBlid(blid).balanceOf(address(this));
        } else {
            amount = vestingAmount * 10**18;
            amount = amount.mul(block.timestamp - lastUpdate).div(vestingEnd - vestingBegin);
            lastUpdate = block.timestamp;
        }
        IBlid(blid).transfer(recipient, amount);
    }
}

interface IBlid {
    function balanceOf(address account) external view returns (uint256);

    function transfer(address dst, uint256 rawAmount) external returns (bool);
}
