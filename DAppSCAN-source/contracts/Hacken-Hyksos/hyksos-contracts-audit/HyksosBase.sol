// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import './DepositQueue.sol';
import './IHyksos.sol';

abstract contract HyksosBase is IHyksos, DepositQueue {

    struct DepositedNft {
        uint256 timeDeposited;
        address owner;
        uint16 rateModifier;
        Deposit[] shareholders;
    }

    IAutoCompound immutable public autoCompound;
    uint256 immutable public roiPctg;
    uint256 immutable public depositLength;

    mapping(address => uint256) internal erc20BalanceMap;
    mapping(uint256 => DepositedNft) internal depositedNfts;
    uint256 internal totalErc20Balance;

    constructor(address _autoCompound, uint256 _depositLength, uint256 _roiPctg) {
        autoCompound = IAutoCompound(_autoCompound);
        roiPctg = _roiPctg;
        depositLength = _depositLength;
    }

    function payErc20(address _receiver, uint256 _amount) internal virtual;
//SWC-128-DoS With Block Gas Limit: L32-85
    function distributeRewards(uint256 _id, uint256 _reward, uint256 _nftWorkValue) internal {
            withdrawNftAndRewardCaller(_id, _reward, _nftWorkValue);
    }

    function withdrawNftAndRewardCaller(uint256 _id, uint256 _reward, uint256 _nftWorkValue) internal {
        for (uint i = 0; i < depositedNfts[_id].shareholders.length; i++) {
            Deposit memory d = depositedNfts[_id].shareholders[i];
            uint256 payback = d.amount * 100 / roiPctg;
            payRewardAccordingToStrategy(d.sender, payback);
        }
        payErc20(msg.sender, _reward - _nftWorkValue);
    }

    function selectShareholders(uint256 _id, uint256 _loanAmount) internal {
        require(totalErc20Balance >= _loanAmount, "Not enough erc-20 tokens in pool to fund a loan.");
        // loop variables
        uint256 selectedAmount;
        uint256 depositAmount;
        uint256 resultingAmount;
        uint256 usedAmount;
        uint256 leftAmount;

        while (!isDepositQueueEmpty()) {
            Deposit memory d = getTopDeposit();
            if (erc20BalanceMap[d.sender] == 0) {
                popDeposit();
                continue;
            }
            if (erc20BalanceMap[d.sender] < d.amount) {
                depositAmount = erc20BalanceMap[d.sender];
            } else {
                depositAmount = d.amount;
            }
            resultingAmount = selectedAmount + depositAmount;
            if (resultingAmount > _loanAmount) {
                usedAmount = _loanAmount - selectedAmount;
                leftAmount = depositAmount - usedAmount;
                setTopDepositAmount(leftAmount);
                depositedNfts[_id].shareholders.push(Deposit(usedAmount, d.sender));
                erc20BalanceMap[d.sender] -= usedAmount;
                return;
            } else {
                depositedNfts[_id].shareholders.push(Deposit(depositAmount, d.sender));
                selectedAmount = resultingAmount;
                erc20BalanceMap[d.sender] -= depositAmount;
                popDeposit();
                if (resultingAmount == _loanAmount) {
                    return;
                }
            }
        }
        // if while loop does not return early, we don't have enough bananas.
        revert("Not enough deposits.");
    }

    function payRewardAccordingToStrategy(address _receiver, uint256 _amount) internal {
        if (autoCompound.getStrategy(_receiver)) {
            erc20BalanceMap[_receiver] += _amount;
            pushDeposit(_amount, _receiver);
            totalErc20Balance += _amount;
        } else {
            payErc20(_receiver, _amount);
        }
    }

    function erc20Balance(address _addr) external view override returns(uint256) {
        return erc20BalanceMap[_addr];
    }

    function totalErc20() external view override returns(uint256) {
        return totalErc20Balance;
    }

    function depositedNft(uint256 _id) external view returns(DepositedNft memory) {
        return depositedNfts[_id];
    }
}
