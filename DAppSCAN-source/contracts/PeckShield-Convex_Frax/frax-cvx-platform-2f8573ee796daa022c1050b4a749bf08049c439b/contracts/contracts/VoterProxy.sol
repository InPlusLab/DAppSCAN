// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./interfaces/IFeeDistro.sol";
import "./interfaces/IDeposit.sol";
import "./interfaces/IVoteEscrow.sol";
import "./interfaces/IGauge.sol";
import "./interfaces/IVoting.sol";
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';


contract FraxVoterProxy {
    using SafeERC20 for IERC20;

    address public constant fxs = address(0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0);
    address public constant escrow = address(0xc8418aF6358FFddA74e09Ca9CC3Fe03Ca6aDC5b0);
    address public constant gaugeController = address(0x44ade9AA409B0C29463fF7fcf07c9d3c939166ce);
    
    address public owner;
    address public operator;
    address public depositor;
    
    constructor(){
        owner = msg.sender;
    }

    function getName() external pure returns (string memory) {
        return "FraxVoterProxy";
    }

    function setOwner(address _owner) external {
        require(msg.sender == owner, "!auth");
        owner = _owner;
    }

    function setOperator(address _operator) external {
        require(msg.sender == owner, "!auth");
        require(operator == address(0) || IDeposit(operator).isShutdown() == true, "needs shutdown");
        
        //require isshutdown interface
        require(IDeposit(_operator).isShutdown() == false, "no shutdown interface");
        
        operator = _operator;
    }

    function setDepositor(address _depositor) external {
        require(msg.sender == owner, "!auth");

        depositor = _depositor;
    }

    function createLock(uint256 _value, uint256 _unlockTime) external returns(bool){
        require(msg.sender == depositor, "!auth");
        IERC20(fxs).safeApprove(escrow, 0);
        IERC20(fxs).safeApprove(escrow, _value);
        IVoteEscrow(escrow).create_lock(_value, _unlockTime);
        return true;
    }

    function increaseAmount(uint256 _value) external returns(bool){
        require(msg.sender == depositor, "!auth");
        IERC20(fxs).safeApprove(escrow, 0);
        IERC20(fxs).safeApprove(escrow, _value);
        IVoteEscrow(escrow).increase_amount(_value);
        return true;
    }

    function increaseTime(uint256 _value) external returns(bool){
        require(msg.sender == depositor, "!auth");
        IVoteEscrow(escrow).increase_unlock_time(_value);
        return true;
    }

    function release() external returns(bool){
        require(msg.sender == depositor, "!auth");
        IVoteEscrow(escrow).withdraw();
        return true;
    }

    function voteGaugeWeight(address _gauge, uint256 _weight) external returns(bool){
        require(msg.sender == operator, "!auth");

        //vote
        IVoting(gaugeController).vote_for_gauge_weights(_gauge, _weight);
        return true;
    }

    function checkpointFeeRewards(address _distroContract) external{
        require(msg.sender == depositor || msg.sender == operator, "!auth");
        IFeeDistro(_distroContract).checkpoint();
    }

    function claimFees(address _distroContract, address _token, address _claimTo) external returns (uint256){
        require(msg.sender == operator, "!auth");
        IFeeDistro(_distroContract).getYield();
        uint256 _balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(_claimTo, _balance);
        return _balance;
    }    

    function execute(
        address _to,
        uint256 _value,
        bytes calldata _data
    ) external returns (bool, bytes memory) {
        require(msg.sender == operator,"!auth");

        (bool success, bytes memory result) = _to.call{value:_value}(_data);

        return (success, result);
    }

}