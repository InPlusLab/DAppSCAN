// SPDX-License-Identifier: MIT
/*
TODO: info
TODO: fundOpen = false doesn't disallow soft commits anymore


*/

pragma solidity ^0.6.11;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol"; // call ERC20 safely
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../Interfaces/IMinter.sol";

contract GaugeD1 is ReentrancyGuard {
	using SafeERC20 for IERC20;
	using Address for address;
    using SafeMath for uint256;

    address public governance;
    address public vcHolding; // holding account for all committed funds
    address public STACK; // STACK ERC20 token contract
    address public acceptToken; // set up gauge for +ETH, +BTC, +LINK, etc.
    address public vaultGaugeBridge; // the bridge address to allow people one transaction to do: (token <-> yEarn token <-> commit)

    uint256 public emissionRate; // amount of STACK/block given

    uint256 public depositedCommitSoft;
    uint256 public depositedCommitHard;

    uint256 public constant commitSoftWeight = 1;
    uint256 public constant commitHardWeight = 4;

    struct CommitState {
    	uint256 balanceCommitSoft;
    	uint256 balanceCommitHard;
    	uint256 tokensAccrued;
    }

    mapping(address => CommitState) public balances; // balance of acceptToken by user by commit

    event Deposit(address indexed from, uint256 amountCommitSoft, uint256 amountCommitHard);
    event Withdraw(address indexed to, uint256 amount);
    event Upgrade(address indexed user, uint256 amount);

    bool public fundOpen = true; // reject all new deposits and upgradeCommits

    // uint256 public constant startBlock = 100;
    // uint256 public endBlock = startBlock + 100;

    uint256 public constant startBlock = 11226037 + 100;
    uint256 public endBlock = startBlock + 598154;

    uint256 public lastBlock; // last block the distribution has ran
    uint256 public tokensAccrued; // tokens to distribute per weight scaled by 1e18

    constructor(address _vcHolding, address _STACK, address _acceptToken, address _vaultGaugeBridge, uint256 _emissionRate) public {
    	governance = msg.sender;

    	vcHolding = _vcHolding;
    	STACK = _STACK;
    	acceptToken = _acceptToken;
    	vaultGaugeBridge = _vaultGaugeBridge;
    	emissionRate = _emissionRate;
    }

    function setGovernance(address _new) external {
    	require(msg.sender == governance);
    	governance = _new;
    }

    function setVCHolding(address _new) external {
    	require(msg.sender == governance, "GAUGE: !governance");
    	vcHolding = _new;
    }

    function setEmissionRate(uint256 _new) external {
    	require(msg.sender == governance, "GAUGE: !governance");
    	_kick(); // catch up the contract to the current block for old rate
    	emissionRate = _new;
    }

    function setFundOpen(bool _open) external {
    	require(msg.sender == governance, "GAUGE: !governance");
    	fundOpen = _open;
    }

    function setEndBlock(uint256 _block) external {
    	require(msg.sender == governance, "GAUGE: !governance");
    	require(block.number <= endBlock, "GAUGE: distribution already done, must start another");

    	endBlock = _block;
    }

    function deposit(uint256 _amountCommitSoft, uint256 _amountCommitHard, address _creditTo) nonReentrant external {
    	require(block.number <= endBlock, "GAUGE: distribution 1 over");
    	require(fundOpen || _amountCommitHard == 0, "GAUGE: !fundOpen, only soft commit allowed"); // when the fund closes, soft commits are still accepted
    	require(msg.sender == _creditTo || msg.sender == vaultGaugeBridge, "GAUGE: !bridge for creditTo"); // only the bridge contract can use the "creditTo" to credit !msg.sender

    	_claimSTACK(_creditTo); // new deposit doesn't get tokens right away

    	// transfer tokens from sender to account
    	uint256 _acceptTokenAmount = _amountCommitSoft.add(_amountCommitHard);
    	if (_acceptTokenAmount > 0){
    		IERC20(acceptToken).safeTransferFrom(msg.sender, address(this), _acceptTokenAmount);
    	}

    	CommitState memory _state = balances[_creditTo];
    	// no need to update _state.tokensAccrued because that's already done in _claimSTACK
    	if (_amountCommitSoft > 0){
    		_state.balanceCommitSoft = _state.balanceCommitSoft.add(_amountCommitSoft);
			depositedCommitSoft = depositedCommitSoft.add(_amountCommitSoft);
    	}
    	if (_amountCommitHard > 0){
    		_state.balanceCommitHard = _state.balanceCommitHard.add(_amountCommitHard);
			depositedCommitHard = depositedCommitHard.add(_amountCommitHard);

            IERC20(acceptToken).transfer(vcHolding, _amountCommitHard);
    	}

		emit Deposit(_creditTo, _amountCommitSoft, _amountCommitHard);
		balances[_creditTo] = _state;
    }

    function upgradeCommit(uint256 _amount) nonReentrant external {
    	// upgrading from soft -> hard commit
    	require(block.number <= endBlock, "GAUGE: distribution 1 over");
    	require(fundOpen, "GAUGE: !fundOpen"); // soft commits cannot be upgraded after the fund closes. they can be deposited though

    	_claimSTACK(msg.sender);

    	CommitState memory _state = balances[msg.sender];

        require(_amount <= _state.balanceCommitSoft, "GAUGE: insufficient balance softCommit");
        _state.balanceCommitSoft = _state.balanceCommitSoft.sub(_amount);
        _state.balanceCommitHard = _state.balanceCommitHard.add(_amount);
        depositedCommitSoft = depositedCommitSoft.sub(_amount);
        depositedCommitHard = depositedCommitHard.add(_amount);

        IERC20(acceptToken).safeTransfer(vcHolding, _amount);

    	emit Upgrade(msg.sender, _amount);
    	balances[msg.sender] = _state;
    }

    // withdraw funds that haven't been committed to VC fund (fund in commitSoft before deadline)
    function withdraw(uint256 _amount, address _withdrawFor) nonReentrant external {
        require(block.number <= endBlock, ">endblock");
        require(msg.sender == _withdrawFor || msg.sender == vaultGaugeBridge, "GAUGE: !bridge for withdrawFor"); // only the bridge contract can use the "withdrawFor" to withdraw for !msg.sender 

    	_claimSTACK(_withdrawFor); // claim tokens from all blocks including this block on withdraw

    	CommitState memory _state = balances[_withdrawFor];

    	require(_amount <= _state.balanceCommitSoft, "GAUGE: insufficient balance softCommit");

    	// update globals & add amtToWithdraw to final tally.
    	_state.balanceCommitSoft = _state.balanceCommitSoft.sub(_amount);
    	depositedCommitSoft = depositedCommitSoft.sub(_amount);
    	
    	emit Withdraw(_withdrawFor, _amount);
    	balances[_withdrawFor] = _state;

    	// IMPORTANT: send tokens to msg.sender, not _withdrawFor. This will send to msg.sender OR vaultGaugeBridge (see second require() ).
        // the bridge contract will then forward these tokens to the sender (after withdrawing from yEarn)
    	IERC20(acceptToken).safeTransfer(msg.sender, _amount);
    }

    function claimSTACK() nonReentrant external {
    	_claimSTACK(msg.sender);
    }

    function _claimSTACK(address _user) internal {
    	_kick();

    	CommitState memory _state = balances[_user];
    	if (_state.tokensAccrued == tokensAccrued){ // user doesn't have any accrued tokens
    		return;
    	}
    	// user has accrued tokens from their commit
    	else {
    		uint256 _tokensAccruedDiff = tokensAccrued.sub(_state.tokensAccrued);
    		uint256 _tokensGive = _tokensAccruedDiff.mul(getUserWeight(_user)).div(1e18);

    		_state.tokensAccrued = tokensAccrued;
    		balances[_user] = _state;

    		// now send tokens to user
    		IERC20(STACK).safeTransfer(_user, _tokensGive);
    	}
    }

    function _kick() internal {   	
    	uint256 _totalWeight = getTotalWeight();
    	// if there are no tokens committed, then don't kick.
    	if (_totalWeight == 0){ 
    		return;
    	}
    	// already done for this block || already did all blocks || not started yet
    	if (lastBlock == block.number || lastBlock >= endBlock || block.number < startBlock){ 
    		return; 
    	}
    	// accrue tokens to account from minter, and add the proportion to tokensAccrued
    	if (IMinter(STACK).minters(address(this))){

    		uint256 _deltaBlock;
    		// edge case where kick was not called for the entire period of blocks.
    		if (lastBlock <= startBlock && block.number >= endBlock){
    			_deltaBlock = endBlock.sub(startBlock);
    		}
    		// where block.number is past the endBlock
    		else if (block.number >= endBlock){
    			_deltaBlock = endBlock.sub(lastBlock);
    		}
    		// where last block is before start
    		else if (lastBlock <= startBlock){
    			_deltaBlock = block.number.sub(startBlock);
    		}
    		// normal case, where we are in the middle of the distribution
    		else {
    			_deltaBlock = block.number.sub(lastBlock);
    		}

    		// mint tokens & update tokensAccrued global
    		uint256 _tokensToMint = _deltaBlock.mul(emissionRate);
    		tokensAccrued = tokensAccrued.add(_tokensToMint.mul(1e18).div(_totalWeight));
    		IMinter(STACK).mint(address(this), _tokensToMint);
    	}

    	// if not allowed to mint it's just like the emission rate = 0. So just update the lastBlock.
    	// always update last block 
    	lastBlock = block.number;
    }

    // a one-time use function to sweep any commitSoft to the vc fund rewards pool, after the 3 month window
    function sweepCommitSoft() nonReentrant public {
    	require(msg.sender == governance, "GAUGE: !governance");
    	require(block.number > endBlock, "GAUGE: <=endBlock");

        // transfer all remaining ERC20 tokens to the VC address. Fund entry has closed, VC fund will start.
    	IERC20(acceptToken).safeTransfer(vcHolding, IERC20(acceptToken).balanceOf(address(this)));
    }

    function getTotalWeight() public view returns (uint256){
    	uint256 soft = depositedCommitSoft.mul(commitSoftWeight);
    	uint256 hard = depositedCommitHard.mul(commitHardWeight);

    	return soft.add(hard);
    }

    function getTotalBalance() public view returns(uint256){
    	return depositedCommitSoft.add(depositedCommitHard);
    }

    function getUserWeight(address _user) public view returns (uint256){
    	uint256 soft = balances[_user].balanceCommitSoft.mul(commitSoftWeight);
    	uint256 hard = balances[_user].balanceCommitHard.mul(commitHardWeight);

    	return soft.add(hard);
    }

    function getUserBalance(address _user) public view returns (uint256){
    	uint256 soft = balances[_user].balanceCommitSoft;
    	uint256 hard = balances[_user].balanceCommitHard;

    	return soft.add(hard);
    }

    function getCommitted() public view returns (uint256, uint256, uint256){
        return (depositedCommitSoft, depositedCommitHard, getTotalBalance());
    }
}