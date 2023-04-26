//SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./SingleBond.sol";

contract SingleBondsFactory is Ownable {
    using SafeERC20 for IERC20;
    
    event NewBonds(address indexed bond, address _rewardtoken, uint256 _start, uint256 _duration, uint256 _phasenum,uint256 _principal,uint256 _interestone,address _debtor);

    address public epochImp; 

    constructor(address _epochImp) {  
        epochImp = _epochImp;
    }

    function newBonds(address _rewardtoken, uint256 _start, uint256 _duration, uint256 _phasenum,uint256 _principal,uint256 _interestone,address _debtor) external onlyOwner {
        IERC20 token = IERC20(_rewardtoken);
        uint totalAmount = _phasenum * _interestone + _principal;
        
        require(token.balanceOf(msg.sender)>= totalAmount, "factory:no balance");
        token.safeTransferFrom(msg.sender, address(this), totalAmount);

        SingleBond singlebond = new SingleBond(_rewardtoken);
        token.approve(address(singlebond), totalAmount);
        singlebond.setEpochImp(epochImp);
        singlebond.initBond(_start, _duration, _phasenum, _principal, _interestone, _debtor);
        emit NewBonds(address(singlebond), _rewardtoken, _start, _duration, _phasenum, _principal, _interestone, _debtor);
    }

    // 
    function renewal (SingleBond bondAddr, uint256 _phasenum,uint256 _principal,uint256 _interestone) external onlyOwner {
        IERC20 token = IERC20(bondAddr.rewardtoken());
        uint totalAmount = _phasenum * _interestone + _principal;
        require(token.balanceOf(msg.sender)>= totalAmount, "factory:no balance");
        token.safeTransferFrom(msg.sender, address(this), totalAmount);
        token.approve(address(bondAddr), totalAmount);

        bondAddr.renewal(_phasenum, _principal, _interestone);
    }

    function renewSingleEpoch(SingleBond bondAddr, uint256 id, uint256 amount, address to) external onlyOwner{ 
        IERC20 token = IERC20(bondAddr.rewardtoken());
        token.safeTransferFrom(msg.sender, address(this), amount);
        token.approve(address(bondAddr), amount);
        bondAddr.renewSingleEpoch(id,amount,to);
    }


}
