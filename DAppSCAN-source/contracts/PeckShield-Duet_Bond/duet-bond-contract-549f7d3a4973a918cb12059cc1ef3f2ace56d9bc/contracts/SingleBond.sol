//SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./Epoch.sol";
import "./CloneFactory.sol";

contract SingleBond is Ownable, CloneFactory {
    using Strings for uint256;

    address[] private epoches;
    address public rewardtoken;
    address public debtor;

    uint256 public start;
    uint256 public duration;
    uint256 public phasenum;
    uint256 public end;

    address public epochImp;

    event NewEpoch(address indexed epoch);

    function getEpoches() external view returns(address[] memory){
        return epoches;
    }

    function setEpochImp(address _epochImp) external onlyOwner {
        epochImp = _epochImp;
    }

    function getEpoch(uint256 id) external view returns(address){
        return epoches[id];
    }

    constructor(address _rewardtoken) {
        rewardtoken = _rewardtoken;
    }

    function initBond(uint256 _start, uint256 _duration, uint256 _phasenum,uint256 _principal,uint256 _interestone,address _debtor) external onlyOwner {
        require(start == 0 && end == 0, "aleady inited");
        debtor = _debtor;
        start = _start;
        duration = _duration;
        phasenum = _phasenum;

        for (uint256 i = 0; i < phasenum; i++){
            uint256 epend = start + (i+1) * duration;
            uint256 amount = _interestone;
            if(i == phasenum - 1) {
                amount = _principal + _interestone;
            }
            string memory name = string(abi.encodePacked(string("Epoch#"), i.toString()));
            string memory symbol = string(abi.encodePacked(string("EP#"), i.toString()));

            address ep = createClone(epochImp);

            Epoch(ep).initialize(rewardtoken, epend, debtor, amount, name, symbol);
            epoches.push(ep);
            emit NewEpoch(ep);

            IERC20(rewardtoken).transferFrom(msg.sender, ep, amount);
        }
        end = start + phasenum * duration;
    }

    //renewal bond will start at next phase
    function renewal (uint256 _phasenum,uint256 _principal,uint256 _interestone) external onlyOwner {
        uint256 needcreate = 0;
        uint256 newstart = end;
        uint256 renewphase = (block.timestamp - start)/duration + 1;
        if(block.timestamp + duration >= end){ 
            needcreate = _phasenum;
            newstart = block.timestamp;
            start = block.timestamp;
            phasenum = 0;
        }else{
            if(block.timestamp + duration*_phasenum <= end) {
                needcreate = 0;
            } else {
                needcreate = _phasenum - (end - block.timestamp)/duration;
            }
        }

        uint256 needrenew = _phasenum - needcreate;
        IERC20 token = IERC20(rewardtoken);
        for(uint256 i = 0; i < needrenew; i++){
            address renewEP = epoches[renewphase+i];
            uint256 amount = _interestone;
            if(i == _phasenum-1){
                amount = _interestone + _principal;
            }
            Epoch(renewEP).mint(debtor, amount);
            token.transferFrom(msg.sender, renewEP, amount);
        }
        uint256 idnum = epoches.length;
        for(uint256 j = 0; j < needcreate; j++){
            uint256 amount = _interestone;
            if(needrenew + j == _phasenum - 1){
                amount = _principal + _interestone;
            }
            string memory name = string(abi.encodePacked(string("Epoch#"), (j+idnum).toString()));
            string memory symbol = string(abi.encodePacked(string("EP#"), (j+idnum).toString()));

            address ep = createClone(epochImp);
            Epoch(ep).initialize(rewardtoken, newstart + (j+1)*duration, debtor, amount, name, symbol);
            epoches.push(ep);
            emit NewEpoch(address(ep));
            token.transferFrom(msg.sender, ep, amount);
        }

        end = newstart + needcreate * duration;
        phasenum = phasenum + needcreate;
    }

    function renewSingleEpoch(uint256 id, uint256 amount, address to) external onlyOwner{
        require(epoches[id] != address(0), "unavailable epoch"); 
        IERC20(rewardtoken).transferFrom(msg.sender, epoches[id], amount);
        Epoch(epoches[id]).mint(to, amount);    
    }

    // redeem all 
    function redeemAll(address to) external {
        address user = msg.sender;
        for( uint256 i = 0; i < epoches.length; i++ ){
            Epoch ep = Epoch(epoches[i]);
            if( block.timestamp > ep.end() ){
                uint256 user_balance = ep.balanceOf(user);
                if( user_balance > 0 ){
                    ep.redeem(user, to, user_balance);
                }
            } else {
                break;
            }
        }
    }

    function redeem(address[] memory epochs, uint[] memory amounts, address to) external {
        require(epochs.length == amounts.length, "mismatch length");
        address user = msg.sender;
        
        for( uint256 i = 0; i < epochs.length; i++ ){
            Epoch ep = Epoch(epochs[i]);
            require( block.timestamp > ep.end(), "epoch not end");
            ep.redeem(user, to, amounts[i]);
        }
    }

    function redeemOrTransfer(address[] memory epochs, uint[] memory amounts, address to) external {
        require(epochs.length == amounts.length, "mismatch length");
        address user = msg.sender;
        
        for( uint256 i = 0; i < epochs.length; i++){
            Epoch ep = Epoch(epochs[i]);
            if( block.timestamp > ep.end()) {
                ep.redeem(user, to, amounts[i]);
            } else {
                ep.multiTransfer(user, to, amounts[i]);
            }
        }
    }

    function multiTransfer(address[] memory epochs, uint[] memory amounts, address to) external {
        require(epochs.length == amounts.length, "mismatch length");
        address user = msg.sender;
        for( uint256 i = 0; i < epochs.length; i++){
            Epoch ep = Epoch(epochs[i]);
            ep.multiTransfer(user, to, amounts[i]);
        }
    }

}
