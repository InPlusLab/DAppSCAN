pragma solidity ^0.5.16;

import "openzeppelin-solidity-2.3.0/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-solidity-2.3.0/contracts/math/Math.sol";
import "openzeppelin-solidity-2.3.0/contracts/math/SafeMath.sol";

import "synthetix-2.43.1/contracts/SafeDecimalMath.sol";
import "openzeppelin-solidity-2.3.0/contracts/utils/ReentrancyGuard.sol";
import "synthetix-2.43.1/contracts/Owned.sol";

contract VestingEscrow is ReentrancyGuard, Owned {
    using Math for uint256;
    using SafeMath for uint256;

    address public token;
    uint256 public startTime;
    uint256 public endTime;
    mapping(address => uint256) public initialLocked;
    mapping(address => uint256) public totalClaimed;

    uint256 public initialLockedSupply;
    uint256 public unallocatedSupply;

    constructor(
        address _owner,
        address _token,
        uint256 _startTime,
        uint256 _endTime
    ) public Owned(_owner) {
        require(_startTime >= block.timestamp, "Start time must be in future");
        require(_endTime > _startTime, "End time must be greater than start time");

        token = _token;
        startTime = _startTime;
        endTime = _endTime;
    }

    function addTokens(uint256 _amount) external onlyOwner {
        require(ERC20(token).transferFrom(msg.sender, address(this), _amount), "Transfer failed");
        unallocatedSupply = unallocatedSupply.add(_amount);
    }

    function fund(address[] calldata _recipients, uint256[] calldata _amounts) external onlyOwner {
        uint256 _totalAmount = 0;
        for (uint256 index = 0; index < _recipients.length; index++) {
            uint256 amount = _amounts[index];
            address recipient = _recipients[index];
            if (recipient == address(0)) {
                break;
            }
            _totalAmount = _totalAmount.add(amount);
            initialLocked[recipient] = initialLocked[recipient].add(amount);
            emit Fund(recipient, amount);
        }

        initialLockedSupply = initialLockedSupply.add(_totalAmount);
        unallocatedSupply -= _totalAmount;
    }
//SWC-101-Integer Overflow and Underflow:L57
    function _totalVestedOf(address _recipient, uint256 _time) internal view returns (uint256) {
        uint256 start = startTime;
        uint256 end = endTime;
        uint256 locked = initialLocked[_recipient];

        if (_time < start) return 0;
        return Math.min(locked.mul(_time.sub(start)).div(end.sub(start)), locked);
    }

    function _totalVested() internal view returns (uint256) {
        uint256 start = startTime;
        uint256 end = endTime;
        uint256 locked = initialLockedSupply;

        if (block.timestamp < start) {
            return 0;
        }

        return Math.min(locked.mul(block.timestamp.sub(start)).div(end.sub(start)), locked);
    }

    function vestedSupply() public view returns (uint256) {
        return _totalVested();
    }

    function vestedOf(address _recipient) public view returns (uint256) {
        return _totalVestedOf(_recipient, block.timestamp);
    }

    function lockedSupply() public view returns (uint256) {
        return initialLockedSupply.sub(_totalVested());
    }

    function balanceOf(address _recipient) public view returns (uint256) {
        return _totalVestedOf(_recipient, block.timestamp).sub(totalClaimed[_recipient]);
    }

    function lockedOf(address _recipient) public view returns (uint256) {
        return initialLocked[_recipient].sub(_totalVestedOf(_recipient, block.timestamp));
    }

    function _selfDestruct(address payable beneficiary) external onlyOwner {
        //only callable a year after end time
        require(block.timestamp > (endTime + 365 days), "Contract can only be selfdestruct a year after endtime");

        // Transfer the balance rather than the deposit value in case there are any synths left over
        // from direct transfers.
        IERC20(token).transfer(beneficiary, IERC20(token).balanceOf(address(this)));

        // Destroy the option tokens before destroying the market itself.
        selfdestruct(beneficiary);
    }

    function claim() external nonReentrant {
        uint256 claimable = balanceOf(msg.sender);
        require(claimable > 0, "nothing to claim");
        totalClaimed[msg.sender] = totalClaimed[msg.sender].add(claimable);
        require(ERC20(token).transfer(msg.sender, claimable));
        emit Claim(msg.sender, claimable);
    }

    event Fund(address indexed _recipient, uint256 _amount);
    event Claim(address indexed _address, uint256 _amount);
}
