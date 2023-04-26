// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;


import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/SafeERC20.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/math/Math.sol";
import "../UpgradeableOwnable.sol";


contract Vesting is UpgradeableOwnable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct PlanInfo {
        uint256 end;
        uint256 rate;
        uint256 lastRewardTime;
    }

    IERC20 public token;

    mapping (address => PlanInfo) public plans;

    uint256 public planned;

    // solium-disable-next-line
    constructor() public {
    }

    event Add(address indexed user, uint256 start, uint256 end, uint256 rate);
    event Remove(address indexed user, uint256 remaining);
    event Vest(address indexed user, uint256 ts, uint256 amount, uint256 remaining);

    function initialize(IERC20 tk) external onlyOwner {
        token = tk;
    }

    function _remaining(PlanInfo storage plan) internal view returns (uint256) {
        return plan.rate.mul(plan.end.sub(plan.lastRewardTime));
    }

    function remaining(address receiver) external view returns (uint256) {
        return _remaining(plans[receiver]);
    }

    function _add(address receiver, uint256 start, uint256 end, uint256 totalAmount) internal {
        PlanInfo storage plan = plans[receiver];
        require (plan.end == 0, "already planned");

        plan.end = end;
        plan.lastRewardTime = start.sub(1);
        plan.rate = totalAmount.div(end.sub(start).add(1));

        planned = planned.add(_remaining(plan));
        require (planned <= token.balanceOf(address(this)), "insufficient balance");

        emit Add(receiver, start, end, plan.rate);
    }

    function add(address receiver, uint256 start, uint256 end, uint256 totalAmount) external onlyOwner {
        _add(receiver, start, end, totalAmount);
    }

    function addBatch(address[] memory receivers, uint256 start, uint256 end, uint256 totalAmount) external onlyOwner {
        for (uint256 i = 0; i < receivers.length; i++) {
            _add(receivers[i], start, end, totalAmount);
        }
    }

    function _remove(address receiver) internal {
        PlanInfo storage plan = plans[receiver];
        require (plan.end != 0, "already planned");

        emit Remove(receiver, _remaining(plan));

        planned = planned.sub(_remaining(plan));
        plan.end = 0;
        plan.rate = 0;
        plan.lastRewardTime = 0;
    }

    function remove(address receiver) external onlyOwner {
        _remove(receiver);
    }

    function removeBatch(address[] memory receivers) external onlyOwner {
        for (uint256 i = 0; i < receivers.length; i++) {
            _remove(receivers[i]);
        }
    }

    function _vestAt(uint256 ts, address receiver) internal {
        PlanInfo storage plan = plans[receiver];
        require (plan.end != 0, "not planned");

        uint256 time = Math.min(ts, plan.end);
        uint256 amount = time.sub(plan.lastRewardTime).mul(plan.rate);
        uint256 oldRemaining = _remaining(plan);

        token.safeTransfer(receiver, amount);
        planned = planned.sub(amount);
        plan.lastRewardTime = time;
        assert (oldRemaining.sub(_remaining(plan)) == amount);
        emit Vest(receiver, time, amount, _remaining(plan));
    }

    function vestAt(uint256 ts, address receiver) external onlyOwner {
        // For test purpose.
        _vestAt(ts, receiver);
    }

    function vest(address receiver) external {
        _vestAt(block.timestamp, receiver);
    }
}
