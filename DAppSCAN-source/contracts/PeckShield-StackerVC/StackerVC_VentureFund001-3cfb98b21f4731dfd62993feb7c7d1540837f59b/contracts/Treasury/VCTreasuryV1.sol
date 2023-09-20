// SPDX-License-Identifier: MIT
/*
This is a Stacker.vc VC Treasury version 1 contract. It initiates a 3 year VC Fund that makes investments in ETH, and tries to sell previously acquired ERC20's at a profit.
This fund also has veto functionality by SVC001 token holders. A token holder can stop all buys and sells OR even close the fund early.
*/

pragma solidity ^0.6.11;
pragma experimental ABIEncoderV2; // for memory return types

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol"; // call ERC20 safely
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../Interfaces/IMinter.sol";

contract VCTreasuryV1 is ERC20, ReentrancyGuard {
	using SafeERC20 for IERC20;
	using Address for address;
    using SafeMath for uint256;

	address public councilMultisig;
	address public deployer;
	address payable public treasury;

	enum FundStates {setup, active, paused, closed}
	FundStates public currentState;

	uint256 public fundStartTime;
	uint256 public fundCloseTime;

	uint256 public totalStakedToPause;
	uint256 public totalStakedToKill;
	mapping(address => uint256) stakedToPause;
	mapping(address => uint256) stakedToKill;
	bool public killed;
	address public constant BET_TOKEN = 0xfdd4E938Bb067280a52AC4e02AaF1502Cc882bA6;
	address public constant STACK_TOKEN = 0x514910771AF9Ca656af840dff83E8264EcF986CA; // TODO: need to deploy this contract, incorrect address, this is LINK token

	// we have some looping in the contract. have a limit for loops so that they succeed.
	// loops & especially unbounded loops are bad solidity design.
	uint256 public constant LOOP_LIMIT = 50; 

	// fixed once set
	uint256 public initETH;
	uint256 public constant investmentCap = 200; // percentage of initETH that can be invested of "max"
	uint256 public maxInvestment;

	uint256 public constant pauseQuorum = 300; // must be over this percent for a pause to take effect (of "max")
	uint256 public constant killQuorum = 500; // must be over this percent for a kill to take effect (of "max")
	uint256 public constant max = 1000;

	// used to determine total amount invested in last 30 days
	uint256 public currentInvestmentUtilization;
	uint256 public lastInvestTime;

	uint256 public constant ONE_YEAR = 365 days; // 365 days * 24 hours * 60 minutes * 60 seconds = 31,536,000
	uint256 public constant THIRTY_DAYS = 30 days; // 30 days * 24 hours * 60 minutes * 60 seconds = 2,592,000
	uint256 public constant THREE_DAYS = 3 days; // 3 days * 24 hours * 60 minutes * 60 seconds = 259,200
	uint256 public constant ONE_WEEK = 7 days; // 7 days * 24 hours * 60 minutes * 60 seconds = 604,800

	struct BuyProposal {
		uint256 buyId;
		address tokenAccept;
		uint256 amountInMin;
		uint256 ethOut;
		address taker;
		uint256 maxTime;
	}

	BuyProposal public currentBuyProposal; // only one buy proposal at a time, unlike sells
	uint256 public nextBuyId;
	mapping(address => bool) public boughtTokens; // a list of all tokens purchased (executed successfully)

	struct SellProposal {
		address tokenSell;
		uint256 ethInMin;
		uint256 amountOut;
		address taker;
		uint256 vetoTime;
		uint256 maxTime;
	}

	mapping(uint256 => SellProposal) public currentSellProposals; // can have multiple sells at a time
	uint256 public nextSellId;

	// fees, assessed after one year. fraction of `max`
	uint256 public constant stackFee = 25;
	uint256 public constant councilFee = 25;

	event InvestmentProposed(uint256 buyId, address tokenAccept, uint256 amountInMin, uint256 amountOut, address taker, uint256 maxTime);
	event InvestmentRevoked(uint256 buyId, uint256 time);
	event InvestmentExecuted(uint256 buyId, address tokenAccept, uint256 amountIn, uint256 amountOut, address taker, uint256 time);
	event DevestmentProposed(uint256 sellId, address tokenSell, uint256 ethInMin, uint256 amountOut, address taker, uint256 vetoTime, uint256 maxTime);
	event DevestmentRevoked(uint256 sellId, uint256 time);
	event DevestmentExecuted(uint256 sellId, address tokenSell, uint256 ethIn, uint256 amountOut, address taker, uint256 time);

	constructor(address _multisig, address payable _treasury) public ERC20("Stacker.vc Fund001", "SVC001") {
		deployer = msg.sender;
		councilMultisig = _multisig;
		treasury = _treasury;

		currentState = FundStates.setup;
		
		_setupDecimals(18);
	}

	// receive ETH, do nothing
	receive() payable external {
		return;
	}

	// change the multisig account
	function setCouncilMultisig(address _new) external {
		require(msg.sender == councilMultisig, "TREASURYV1: !councilMultisig");
		councilMultisig = _new;
	}

	// change deployer account, only used for setup (no need to funnel setup calls thru multisig)
	function setDeployer(address _new) external {
		require(msg.sender == councilMultisig || msg.sender == deployer, "TREASURYV1: !(councilMultisig || deployer)");
		deployer = _new;
	}

	function setTreasury(address payable _new) external {
		require(msg.sender == treasury, "TREASURYV1: !treasury");
		treasury = _new;
	}

	// mark a token as bought and able to be distributed when the fund closes. this would be for some sort of airdrop or "freely" acquired token sent to the contract
	function setBoughtToken(address _new) external {
		require(msg.sender == councilMultisig, "TREASURYV1: !councilMultisig");
		boughtTokens[_new] = true;
	}

	// basic mapping get functions

	function getBoughtToken(address _token) external view returns (bool){
		return boughtTokens[_token];
	}

	function getStakedToPause(address _user) external view returns (uint256){
		return stakedToPause[_user];
	}

	function getStakedToKill(address _user) external view returns (uint256){
		return stakedToKill[_user];
	}

	function getSellProposal(uint256 _sellId) external view returns (SellProposal memory){
		return currentSellProposals[_sellId];
	}

	// start main logic
	
	// mint SVC001 tokens to users, fund cannot be started. SVC001 distribution must be audited and checked before the funds is started. Cannot mint tokens after fund starts.
	function issueTokens(address[] calldata _user, uint256[] calldata _amount) external {
		require(currentState == FundStates.setup, "TREASURYV1: !FundStates.setup");
		require(msg.sender == deployer, "TREASURYV1: !deployer");
		require(_user.length == _amount.length, "TREASURYV1: length mismatch");
		require(_user.length <= LOOP_LIMIT, "TREASURYV1: length > LOOP_LIMIT"); // don't allow unbounded loops, bad design, gas issues

		for (uint256 i = 0; i < _user.length; i++){
			_mint(_user[i], _amount[i]);
		}
	}

	// seed the fund with ETH and start it up. 3 years until the fund is dissolved
	function startFund() payable external {
		require(currentState == FundStates.setup, "TREASURYV1: !FundStates.setup");
		require(msg.sender == councilMultisig, "TREASURYV1: !councilMultisig");
		require(totalSupply() > 0, "TREASURYV1: invalid setup"); // means fund tokens were not issued

		fundStartTime = block.timestamp;
		fundCloseTime = block.timestamp.add(ONE_YEAR);

		initETH = msg.value;
		//SWC-101-Integer Overflow and Underflow: L181
		maxInvestment = msg.value.div(max).mul(investmentCap);

		_changeFundState(FundStates.active); // set fund active!
	}

	// make an offer to invest in a project by sending ETH to the project in exchange for tokens. one investment at a time. get ERC20, give ETH
	function investPropose(address _tokenAccept, uint256 _amountInMin, uint256 _ethOut, address _taker) external {
		_checkCloseTime();
		require(currentState == FundStates.active, "TREASURYV1: !FundStates.active");
		require(msg.sender == councilMultisig, "TREASURYV1: !councilMultisig");

		// checks that the investment utilization (30 day rolling average) isn't exceeded. will revert(). otherwise will update to new rolling average
		_updateInvestmentUtilization(_ethOut);

		BuyProposal memory _buy;
		_buy.buyId = nextBuyId;
		_buy.tokenAccept = _tokenAccept;
		_buy.amountInMin = _amountInMin;
		_buy.ethOut = _ethOut;
		_buy.taker = _taker;
		_buy.maxTime = block.timestamp.add(THREE_DAYS); // three days maximum to accept a buy

		currentBuyProposal = _buy;
		nextBuyId = nextBuyId.add(1);
		
		InvestmentProposed(_buy.buyId, _tokenAccept, _amountInMin, _ethOut, _taker, _buy.maxTime);
	}

	// revoke an uncompleted investment offer
	function investRevoke(uint256 _buyId) external {
		_checkCloseTime();
		require(currentState == FundStates.active || currentState == FundStates.paused, "TREASURYV1: !(FundStates.active || FundStates.paused)");
		require(msg.sender == councilMultisig, "TREASURYV1: !councilMultisig");

		BuyProposal memory _buy = currentBuyProposal;
		require(_buyId == _buy.buyId, "TREASURYV1: buyId not active");

		BuyProposal memory _reset;
		currentBuyProposal = _reset;

		InvestmentRevoked(_buy.buyId, block.timestamp);
	}

	// execute an investment offer by sending tokens to the contract, in exchange for ETH
	function investExecute(uint256 _buyId, uint256 _amount) nonReentrant external  {
		_checkCloseTime();
		require(currentState == FundStates.active, "TREASURYV1: !FundStates.active");

		BuyProposal memory _buy = currentBuyProposal;
		require(_buyId == _buy.buyId, "TREASURYV1: buyId not active");
		require(_buy.tokenAccept != address(0), "TREASURYV1: !tokenAccept");
		require(_amount >= _buy.amountInMin, "TREASURYV1: _amount < amountInMin");
		require(_buy.taker == msg.sender || _buy.taker == address(0), "TREASURYV1: !taker"); // if taker is set to 0x0, anyone can accept this investment
		require(block.timestamp <= _buy.maxTime, "TREASURYV1: time > maxTime");

		BuyProposal memory _reset;
		currentBuyProposal = _reset; // set investment proposal to a blank proposal, re-entrancy guard

		uint256 _before = IERC20(_buy.tokenAccept).balanceOf(address(this));
		IERC20(_buy.tokenAccept).safeTransferFrom(msg.sender, address(this), _amount);
		uint256 _after = IERC20(_buy.tokenAccept).balanceOf(address(this));
		require(_after.sub(_before) >= _buy.amountInMin, "TREASURYV1: received < amountInMin"); // check again to verify received amount was correct

		boughtTokens[_buy.tokenAccept] = true;

		InvestmentExecuted(_buy.buyId, _buy.tokenAccept, _amount, _buy.ethOut, msg.sender, block.timestamp);

		msg.sender.transfer(_buy.ethOut); // send the ETH out 
	}

	// allow advisory multisig to propose a new sell. get ETH, give ERC20 prior investment
	function devestPropose(address _tokenSell, uint256 _ethInMin, uint256 _amountOut, address _taker) external {
		_checkCloseTime();
		require(currentState == FundStates.active, "TREASURYV1: !FundStates.active");
		require(msg.sender == councilMultisig, "TREASURYV1: !councilMultisig");

		SellProposal memory _sell;
		_sell.tokenSell = _tokenSell;
		_sell.ethInMin = _ethInMin;
		_sell.amountOut = _amountOut;
		_sell.taker = _taker;
		_sell.vetoTime = block.timestamp.add(THREE_DAYS);
		_sell.maxTime = block.timestamp.add(THREE_DAYS).add(THREE_DAYS);

		currentSellProposals[nextSellId] = _sell;
		
		DevestmentProposed(nextSellId, _tokenSell, _ethInMin, _amountOut, _taker, _sell.vetoTime, _sell.maxTime);

		nextSellId = nextSellId.add(1);
	}

	// revoke an uncompleted sell offer
	function devestRevoke(uint256 _sellId) external {
		_checkCloseTime();
		require(currentState == FundStates.active || currentState == FundStates.paused, "TREASURYV1: !(FundStates.active || FundStates.paused)");
		require(msg.sender == councilMultisig, "TREASURYV1: !councilMultisig");
		require(_sellId < nextSellId, "TREASURYV1: !sellId");

		SellProposal memory _reset;
		currentSellProposals[_sellId] = _reset;

		DevestmentRevoked(_sellId, block.timestamp);
	}

	// execute a divestment of funds
	function devestExecute(uint256 _sellId) nonReentrant external payable {
		_checkCloseTime();
		require(currentState == FundStates.active, "TREASURYV1: !FundStates.active");

		SellProposal memory _sell = currentSellProposals[_sellId];
		require(_sell.tokenSell != address(0), "TREASURYV1: !tokenSell");
		require(msg.value >= _sell.ethInMin, "TREASURYV1: <ethInMin");
		require(_sell.taker == msg.sender || _sell.taker == address(0), "TREASURYV1: !taker"); // if taker is set to 0x0, anyone can accept this devestment
		require(block.timestamp > _sell.vetoTime, "TREASURYV1: time < vetoTime");
		require(block.timestamp <= _sell.maxTime, "TREASURYV1: time > maxTime");

		SellProposal memory _reset;
		currentSellProposals[_sellId] = _reset; // set devestment proposal to a blank proposal, re-entrancy guard

		DevestmentExecuted(_sellId, _sell.tokenSell, msg.value, _sell.amountOut, msg.sender, block.timestamp);
		IERC20(_sell.tokenSell).safeTransfer(msg.sender, _sell.amountOut); // we already received msg.value >= _sell.ethInMin, by above assertions

		// if we completely sell out of an asset, mark this as not owned anymore
		if (IERC20(_sell.tokenSell).balanceOf(address(this)) == 0){
			boughtTokens[_sell.tokenSell] = false;
		}
	}

	// stake SVC001 tokens to the fund. this signals unhappyness with the fund management
	// Pause: if 30% of SVC tokens are staked here, then all sells & buys will be disabled. They will be reenabled when tokens staked drops under 30%
	// tokens staked to stakeToKill() count as 
	function stakeToPause(uint256 _amount) external {
		_checkCloseTime();
		require(currentState == FundStates.active || currentState == FundStates.paused, "TREASURYV1: !(FundStates.active || FundStates.paused)");
		require(balanceOf(msg.sender) >= _amount, "TREASURYV1: insufficient balance to stakeToPause");

		_transfer(msg.sender, address(this), _amount);

		stakedToPause[msg.sender] = stakedToPause[msg.sender].add(_amount);
		totalStakedToPause = totalStakedToPause.add(_amount);

		_updateFundStateAfterStake();
	}

	// Kill: if 50% of SVC tokens are staked here, then the fund will close, and assets will be retreived
	// if 30% of tokens are staked here, then the fund will be paused. See above stakeToPause()
	function stakeToKill(uint256 _amount) external {
		_checkCloseTime();
		require(currentState == FundStates.active || currentState == FundStates.paused, "TREASURYV1: !(FundStates.active || FundStates.paused)");
		require(balanceOf(msg.sender) >= _amount, "TREASURYV1: insufficient balance to stakeToKill");

		_transfer(msg.sender, address(this), _amount);

		stakedToKill[msg.sender] = stakedToKill[msg.sender].add(_amount);
		totalStakedToKill = totalStakedToKill.add(_amount);

		_updateFundStateAfterStake();
	}

	function unstakeToPause(uint256 _amount) external {
		_checkCloseTime();
		require(currentState != FundStates.setup, "TREASURYV1: FundStates.setup");
		require(stakedToPause[msg.sender] >= _amount, "TREASURYV1: insufficent balance to unstakeToPause");

		_transfer(address(this), msg.sender, _amount);

		stakedToPause[msg.sender] = stakedToPause[msg.sender].sub(_amount);
		totalStakedToPause = totalStakedToPause.sub(_amount);

		_updateFundStateAfterStake();
	}

	function unstakeToKill(uint256 _amount) external {
		_checkCloseTime();
		require(currentState != FundStates.setup, "TREASURYV1: FundStates.setup");
		require(stakedToKill[msg.sender] >= _amount, "TREASURYV1: insufficent balance to unstakeToKill");

		_transfer(address(this), msg.sender, _amount);

		stakedToKill[msg.sender] = stakedToKill[msg.sender].sub(_amount);
		totalStakedToKill = totalStakedToKill.sub(_amount);

		_updateFundStateAfterStake();
	}

	function _updateFundStateAfterStake() internal {
		// closes are final, cannot unclose
		if (currentState == FundStates.closed){
			return;
		}
		// check if the fund will irreversibly close
		if (totalStakedToKill > killQuorumRequirement()){
			killed = true;
			_changeFundState(FundStates.closed);
			return;
		}
		// check if the fund will pause/unpause
		uint256 _pausedStake = totalStakedToPause.add(totalStakedToKill);
		if (_pausedStake > pauseQuorumRequirement() && currentState == FundStates.active){
			_changeFundState(FundStates.paused);
			return;
		}
		if (_pausedStake <= pauseQuorumRequirement() && currentState == FundStates.paused){
			_changeFundState(FundStates.active);
			return;
		}
	}

	function killQuorumRequirement() public view returns (uint256) {
		return totalSupply().div(max).mul(killQuorum);
	}

	function pauseQuorumRequirement() public view returns (uint256) {
		return totalSupply().div(max).mul(pauseQuorum);
	}

	function checkCloseTime() external {
		_checkCloseTime();
	}

	// maintenance function: check if the fund is out of time, if so, close it.
	function _checkCloseTime() internal {
		if (block.timestamp >= fundCloseTime && currentState != FundStates.setup){
			_changeFundState(FundStates.closed);
		}
	}

	function _changeFundState(FundStates _state) internal {
		// cannot be changed AWAY FROM closed or TO setup
		if (currentState == FundStates.closed || _state == FundStates.setup){
			return;
		}
		currentState = _state;

		// if closing the fund AND the fund was not `killed`, assess the fee.
		if (_state == FundStates.closed && !killed){
			_assessFee();
		}
	}

	// when closing the fund, assess the fee for STACK holders/council. then close fund.
	function _assessFee() internal {
		uint256 _stackAmount = totalSupply().div(max).mul(stackFee);
		uint256 _councilAmount = totalSupply().div(max).mul(councilFee);

		_mint(treasury, _stackAmount);
		_mint(councilMultisig, _councilAmount);
	}

	// fund is over, claim your proportional proceeds with SVC001 tokens. if fund is not closed but time's up, this will also close the fund
	function claim(address[] calldata _tokens) nonReentrant external {
		_checkCloseTime();
		require(currentState == FundStates.closed, "TREASURYV1: !FundStates.closed");
		require(_tokens.length <= LOOP_LIMIT, "TREASURYV1: length > LOOP_LIMIT"); // don't allow unbounded loops, bad design, gas issues

		// we should be able to send about 50 ERC20 tokens at a maximum in a loop
		// if we have more tokens than this in the fund, we can find a solution...
			// one would be wrapping all "valueless" tokens in another token (via sell / buy flow)
			// users can claim this bundled token, and if a "valueless" token ever has value, then they can do a similar cash out to the valueless token
			// there is a very low chance that there's >50 tokens that users want to claim. Probably more like 5-10 (given a normal VC story of many fails, some big successes)
		// we could alternatively make a different claim flow that doesn't use loops, but the gas and hassle of making 50 txs to claim 50 tokens is way worse

		uint256 _balance = balanceOf(msg.sender);
		uint256 _proportionE18 = _balance.mul(1e18).div(totalSupply());

		_burn(msg.sender, _balance);

		// automatically send a user their ETH balance, everyone wants ETH, the goal of the fund is to make ETH.
		uint256 _proportionToken = address(this).balance.mul(_proportionE18).div(1e18);
		msg.sender.transfer(_proportionToken);

		for (uint256 i = 0; i < _tokens.length; i++){
			require(_tokens[i] != address(this), "can't claim address(this)");
			require(boughtTokens[_tokens[i]], "!boughtToken");
			// don't allow BET/STACK to be claimed if the fund was "killed"
			if (_tokens[i] == BET_TOKEN || _tokens[i] == STACK_TOKEN){
				require(!killed, "BET/STACK can only be claimed if fund wasn't killed");
			}

			_proportionToken = IERC20(_tokens[i]).balanceOf(address(this)).mul(_proportionE18).div(1e18);
			IERC20(_tokens[i]).safeTransfer(msg.sender, _proportionToken);
		}
	}

	// updates currentInvestmentUtilization based on a 30 day rolling average. If there are 30 days since the last investment, the utilization is zero. otherwise, deprec. it at a constant rate.
	function _updateInvestmentUtilization(uint256 _newInvestment) internal {
		uint256 proposedUtilization = getUtilization(_newInvestment);
		require(proposedUtilization <= maxInvestment, "TREASURYV1: utilization > maxInvestment");

		currentInvestmentUtilization = proposedUtilization;
		lastInvestTime = block.timestamp;
	}

	// get the total utilization from a possible _newInvestment
	function getUtilization(uint256 _newInvestment) public view returns (uint256){
		uint256 _lastInvestTimeDiff = block.timestamp.sub(lastInvestTime);
		if (_lastInvestTimeDiff >= THIRTY_DAYS){
			return _newInvestment;
		}
		else {
			// current * ((thirty_days - time elapsed) / thirty_days)
			uint256 _depreciateUtilization = currentInvestmentUtilization.div(THIRTY_DAYS).mul(THIRTY_DAYS.sub(_lastInvestTimeDiff));
			return _newInvestment.add(_depreciateUtilization);
		}
	}

	// get the maximum amount possible to invest at this time
	function availableToInvest() external view returns (uint256){
		return maxInvestment.sub(getUtilization(0));
	}

	// only called in emergencies. if the contract is bricked or for some reason cannot function, we escape all assets and will return to their owners manually.
	// prioritize fund safety & retreivability of assets
	// the checks are: only callable by councilMultisig, and the fund must be closed, and the fund must not be `killed` by SVC001 holders
	function emergencyEscape(address _tokenContract, uint256 _amount) nonReentrant external {
		require(msg.sender == councilMultisig && !killed && currentState == FundStates.closed, "TREASURYV1: escape check failed");

		if (_tokenContract != address(0)){
			IERC20(_tokenContract).safeTransfer(treasury, _amount);
		}
		else { // if _tokenContract is 0x0, then escape ETH
			treasury.transfer(_amount);
		}
	}
}