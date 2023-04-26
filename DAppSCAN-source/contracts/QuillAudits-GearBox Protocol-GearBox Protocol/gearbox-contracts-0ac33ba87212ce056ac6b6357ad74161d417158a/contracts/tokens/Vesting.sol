// SPDX-License-Identifier: MIT
// Gearbox. Generalized leverage protocol that allows to take leverage and then use it across other DeFi protocols and platforms in a composable way.
// (c) Gearbox.fi, 2021
pragma solidity ^0.7.4;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../interfaces/IGearToken.sol";

contract StepVesting {
    using SafeMath for uint256;
    using SafeERC20 for IGearToken;

    event ReceiverChanged(address oldWallet, address newWallet);

    uint256 public immutable started;
    IGearToken public immutable token;
    uint256 public immutable cliffDuration;
    uint256 public immutable stepDuration;
    uint256 public immutable cliffAmount;
    uint256 public immutable stepAmount;
    uint256 public immutable numOfSteps;

    address public receiver;
    uint256 public claimed;

    modifier onlyReceiver {
        require(msg.sender == receiver, "access denied");
        _;
    }

    constructor(
        IGearToken _token,
        uint256 _started,
        uint256 _cliffDuration,
        uint256 _stepDuration,
        uint256 _cliffAmount,
        uint256 _stepAmount,
        uint256 _numOfSteps,
        address _receiver
    ) {
        token = _token;
        started = _started;
        cliffDuration = _cliffDuration;
        stepDuration = _stepDuration;
        cliffAmount = _cliffAmount;
        stepAmount = _stepAmount;
        numOfSteps = _numOfSteps;
        setReceiver(_receiver);
    }

    function available() public view returns (uint256) {
        return claimable().sub(claimed);
    }

    function claimable() public view returns (uint256) {
        if (block.timestamp < started.add(cliffDuration)) {
            return 0;
        }

        uint256 passedSinceCliff = block.timestamp.sub(
            started.add(cliffDuration)
        );
        uint256 stepsPassed = Math.min(
            numOfSteps,
            passedSinceCliff.div(stepDuration)
        );
        return cliffAmount.add(stepsPassed.mul(stepAmount));
    }

    function setReceiver(address _receiver) public onlyReceiver {
        require(_receiver != address(0), "Receiver is zero address");
        emit ReceiverChanged(receiver, _receiver);
        receiver = _receiver;
    }

    function delegate(address delegatee) external onlyReceiver {
        token.delegate(delegatee);
    }

    function claim() external onlyReceiver {
        uint256 amount = available();
        claimed = claimed.add(amount);
        token.safeTransfer(msg.sender, amount);
    }
}
