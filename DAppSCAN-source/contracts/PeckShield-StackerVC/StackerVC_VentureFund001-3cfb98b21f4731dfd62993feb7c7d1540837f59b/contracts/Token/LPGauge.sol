// SPDX-License-Identifier: MIT
/*
A simple guage contract to measure the amount of tokens locked, and reward users in a different token.
*/

pragma solidity ^0.6.11;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol"; // call ERC20 safely
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../Interfaces/IMinter.sol";

contract LPGauge is ReentrancyGuard {
	using SafeERC20 for IERC20;
	using Address for address;
    using SafeMath for uint256;

    address public governance;
    address public STACK;
    address public token;

    uint256 public emissionRate; // amount of STACK/block given

    uint256 public deposited;

    // TODO: make endBlock updateable during the distribution???
    uint256 public constant startBlock = 300;
    uint256 public endBlock = startBlock + 100;

    // uint256 public constant startBlock = 11226037 + 100;
    // uint256 public endBlock = startBlock + 2425846;
    uint256 public lastBlock; // last block the distribution has ran
    uint256 public tokensAccrued; // tokens to distribute per weight scaled by 1e18

    struct DepositState{
    	uint256 balance;
    	uint256 tokensAccrued;
    }

    mapping(address => DepositState) public balances;

    event Deposit(address indexed from, uint256 amount);
    event Withdraw(address indexed to, uint256 amount);

    constructor(address _STACK, address _token, uint256 _emissionRate) public {
    	governance = msg.sender;

    	STACK = _STACK;
    	token = _token;
    	emissionRate = _emissionRate;
    }

    function setGovernance(address _new) external {
    	require(msg.sender == governance);
    	governance = _new;
    }

    function setEmissionRate(uint256 _new) external {
    	require(msg.sender == governance, "LPGAUGE: !governance");
    	_kick(); // catch up the contract to the current block for old rate
    	emissionRate = _new;
    }

    function setEndBlock(uint256 _block) external {
    	require(msg.sender == governance, "LPGAUGE: !governance");
    	require(block.number <= endBlock, "LPGAUGE: distribution already done, must start another");
        require(block.number <= _block, "LPGAUGE: can't set endBlock to past block");
    	
    	endBlock = _block;
    }
	//SWC-107-Reentrancy: L75-L89
    function deposit(uint256 _amount) nonReentrant external {
    	require(block.number <= endBlock, "LPGAUGE: distribution over");

    	_claimSTACK(msg.sender);

    	IERC20(token).safeTransferFrom(msg.sender, address(this), _amount);

    	DepositState memory _state = balances[msg.sender];
    	_state.balance = _state.balance.add(_amount);
    	deposited = deposited.add(_amount);

    	emit Deposit(msg.sender, _amount);

    	balances[msg.sender] = _state;
    }

    function withdraw(uint256 _amount) nonReentrant external {
    	_claimSTACK(msg.sender);

    	uint256 _amtToWithdraw = 0;

    	DepositState memory _state = balances[msg.sender];

    	require(_amount <= _state.balance, "LPGAUGE: insufficient balance");

    	_state.balance = _state.balance.sub(_amount);
    	deposited = deposited.sub(_amount);
    	_amtToWithdraw = _amtToWithdraw.add(_amount);

    	emit Withdraw(msg.sender, _amount);

    	balances[msg.sender] = _state;

    	IERC20(token).safeTransfer(msg.sender, _amtToWithdraw);
    }

    function claimSTACK() nonReentrant external {
    	_claimSTACK(msg.sender);
    }

    function _claimSTACK(address _user) internal {
    	_kick();

    	DepositState memory _state = balances[_user];
    	if (_state.tokensAccrued == tokensAccrued){ // user doesn't have any accrued tokens
    		return;
    	}
    	else {
    		uint256 _tokensAccruedDiff = tokensAccrued.sub(_state.tokensAccrued);
    		uint256 _tokensGive = _tokensAccruedDiff.mul(_state.balance).div(1e18);

    		_state.tokensAccrued = tokensAccrued;
    		balances[_user] = _state;

    		IERC20(STACK).safeTransfer(_user, _tokensGive);
    	}
    }

    function _kick() internal {
    	uint256 _totalDeposited = deposited;
    	// if there are no tokens committed, then don't kick.
    	if (_totalDeposited == 0){
    		return;
    	}
    	// already done for this block || already did all blocks || not started yet
    	if (lastBlock == block.number || lastBlock >= endBlock || block.number < startBlock){
    		return;
    	}

    	if (IMinter(STACK).minters(address(this))){

    		uint256 _deltaBlock;
    		// edge case where kick was not called for entire period of blocks.
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

    		uint256 _tokensToMint = _deltaBlock.mul(emissionRate);
    		tokensAccrued = tokensAccrued.add(_tokensToMint.mul(1e18).div(_totalDeposited));
    		IMinter(STACK).mint(address(this), _tokensToMint);
    	}

    	// if not allowed to mint it's just like the emission rate = 0. So just update the lastBlock.
    	// always update last block 
    	lastBlock = block.number;
    }
}