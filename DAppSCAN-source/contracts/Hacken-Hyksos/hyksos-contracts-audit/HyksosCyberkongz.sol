// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import './HyksosBase.sol';

interface IKongz is IERC721 {
    function balanceOG(address _user) external view returns(uint256);
    function getReward() external;
}

interface IBananas is IERC20 {
    function BASE_RATE() external view returns(uint256);
}

contract HyksosCyberkongz is HyksosBase {
    
    IKongz immutable public nft;
    IBananas immutable public erc20;
    uint256 immutable public kongWorkValue;
    uint256 immutable public loanAmount;
    uint256 immutable public baseRate;
    uint256 constant public MIN_DEPOSIT = 10 ether;


    constructor(address _bananas, address _kongz, address _autoCompound, uint256 _depositLength, uint256 _roiPctg) HyksosBase(_autoCompound, _depositLength, _roiPctg) {
        nft = IKongz(_kongz);
        erc20 = IBananas(_bananas);
        baseRate = erc20.BASE_RATE();
        kongWorkValue = baseRate * depositLength / 1 days;
        loanAmount = kongWorkValue * roiPctg / 100;
    }
//SWC-104-Unchecked Call Return Value: L35-37
    function payErc20(address _receiver, uint256 _amount) internal override {
        require(erc20.transfer(_receiver, _amount));
    }
//SWC-104-Unchecked Call Return Value: L39-46
    function depositErc20(uint256 _amount) external override {
        require(_amount >= MIN_DEPOSIT, "Deposit amount too small.");
        erc20BalanceMap[msg.sender] += _amount;
        pushDeposit(_amount, msg.sender);
        totalErc20Balance += _amount;
        require(erc20.transferFrom(msg.sender, address(this), _amount));
        emit Erc20Deposit(msg.sender, _amount);
    }
//SWC-104-Unchecked Call Return Value: L48-54
    function withdrawErc20(uint256 _amount) external override {
        require(_amount <= erc20BalanceMap[msg.sender], "Withdrawal amount too big.");
        totalErc20Balance -= _amount;
        erc20BalanceMap[msg.sender] -= _amount;
        require(erc20.transfer(msg.sender, _amount));
        emit Erc20Withdrawal(msg.sender, _amount);
    }

    function depositNft(uint256 _id) external override {
        require(isValidKong(_id), "Can't deposit this Kong.");
        depositedNfts[_id].timeDeposited = block.timestamp;
        depositedNfts[_id].owner = msg.sender;
        selectShareholders(_id, loanAmount);
        totalErc20Balance -= loanAmount;
        nft.transferFrom(msg.sender, address(this), _id);
        require(erc20.transfer(msg.sender, loanAmount));
        emit NftDeposit(msg.sender, _id);
    }

    function withdrawNft(uint256 _id) external override {
        require(depositedNfts[_id].timeDeposited + depositLength < block.timestamp, "Too early to withdraw.");
        uint256 reward = calcReward(block.timestamp - depositedNfts[_id].timeDeposited);
        nft.getReward();
        distributeRewards(_id, reward, kongWorkValue);
        nft.transferFrom(address(this), depositedNfts[_id].owner, _id);
        emit NftWithdrawal(depositedNfts[_id].owner, _id);
        delete depositedNfts[_id];
    }

    function isValidKong(uint256 _id) internal pure returns(bool) {
        return _id < 1001;
    }

    function calcReward(uint256 _time) internal view returns(uint256) {
        return baseRate * _time / 86400;
    }
}