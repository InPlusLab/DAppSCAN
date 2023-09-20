// SPDX-License-Identifier: MIT
/*
	The farmboss contracts allows for a whitelist of contracts and functions a "farmer" is allowed to call. Tokens can be whitelisted, and contracts approved for call by DAO governance.
	Farmers need to be approved by DAO governance as well, before they are allowed to call any whitelisted contract/function. 

	If needed, the governance can directly execute any action and bypass the whitelist.

	This contract needs to be inherited by another contract that implements _initFirstFarms() which gets called in the constructor. This initializes the first farms that the fund
	is allowed to invest into, so a governance proposal isn't needed right away.
*/

pragma solidity ^0.6.11;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol"; // call ERC20 safely
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "./FarmTreasuryV1.sol";
import "../Interfaces/IUniswapRouterV2.sol";

abstract contract FarmBossV1 {
	using SafeERC20 for IERC20;
	using SafeMath for uint256;
	using Address for address;

	mapping(address => mapping(bytes4 => uint256)) public whitelist; // contracts -> mapping (functionSig -> allowed, msg.value allowed)
	mapping(address => bool) public farmers;

	// constants for the whitelist logic
	bytes4 constant internal FALLBACK_FN_SIG = 0xffffffff;
	// 0 = not allowed ... 1 = allowed however value must be zero ... 2 = allowed with msg.value either zero or non-zero
	uint256 constant internal NOT_ALLOWED = 0;
	uint256 constant internal ALLOWED_NO_MSG_VALUE = 1;
	uint256 constant internal ALLOWED_W_MSG_VALUE = 2; 

	uint256 internal constant LOOP_LIMIT = 200;
	uint256 public constant max = 10000;
	uint256 public CRVTokenTake = 1500; // pct of max

	// for passing to functions more cleanly
	struct WhitelistData {
		address account;
		bytes4 fnSig;
		bool valueAllowed;
	}

	// for passing to functions more cleanly
	struct Approves {
		address token;
		address allow;
	}

	address payable public governance;
	address public daoCouncilMultisig;
	address public treasury;
	address public underlying;

	// constant - if the addresses change, assume that the functions will be different too and this will need a rewrite
	address public constant UniswapRouter = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;	
	address public constant SushiswapRouter = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
	address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
	address public constant CRVToken = 0xD533a949740bb3306d119CC777fa900bA034cd52;

	event NewFarmer(address _farmer);
	event RmFarmer(address _farmer);

	event NewWhitelist(address _contract, bytes4 _fnSig, uint256 _allowedType);
	event RmWhitelist(address _contract, bytes4 _fnSig);

	event NewApproval(address _token, address _contract);
	event RmApproval(address _token, address _contract);

	event ExecuteSuccess(bytes _returnData);
	event ExecuteERROR(bytes _returnData);

	constructor(address payable _governance, address _daoMultisig, address _treasury, address _underlying) public {
		governance = _governance;
		daoCouncilMultisig = _daoMultisig;
		treasury = _treasury;
		underlying = _underlying;

		farmers[msg.sender] = true;
		emit NewFarmer(msg.sender);
		
		// no need to set to zero first on safeApprove, is brand new contract
		IERC20(_underlying).safeApprove(_treasury, type(uint256).max); // treasury has full control over underlying in this contract

		_initFirstFarms();
	}

	receive() payable external {}

	// function stub, this needs to be implemented in a contract which inherits this for a valid deployment
    // some fixed logic to set up the first farmers, farms, whitelists, approvals, etc. future farms will need to be approved by governance
	// called on init only
    // IMPLEMENT THIS
	function _initFirstFarms() internal virtual;

	function setGovernance(address payable _new) external {
		require(msg.sender == governance, "FARMBOSSV1: !governance");

		governance = _new;
	}

	function setDaoCouncilMultisig(address _new) external {
		require(msg.sender == governance || msg.sender == daoCouncilMultisig, "FARMBOSSV1: !(governance || multisig)");

		daoCouncilMultisig = _new;
	}

	function setCRVTokenTake(uint256 _new) external {
		require(msg.sender == governance || msg.sender == daoCouncilMultisig, "FARMBOSSV1: !(governance || multisig)");
		require(_new <= max.div(2), "FARMBOSSV1: >half CRV to take");

		CRVTokenTake = _new;
	}

	function getWhitelist(address _contract, bytes4 _fnSig) external view returns (uint256){
		return whitelist[_contract][_fnSig];
	}

	function changeFarmers(address[] calldata _newFarmers, address[] calldata _rmFarmers) external {
		require(msg.sender == governance, "FARMBOSSV1: !governance");
		require(_newFarmers.length.add(_rmFarmers.length) <= LOOP_LIMIT, "FARMBOSSV1: >LOOP_LIMIT"); // dont allow unbounded loops

		// add the new farmers in
		for (uint256 i = 0; i < _newFarmers.length; i++){
			farmers[_newFarmers[i]] = true;

			emit NewFarmer(_newFarmers[i]);
		}
		// remove farmers
		for (uint256 j = 0; j < _rmFarmers.length; j++){
			farmers[_rmFarmers[j]] = false;

			emit RmFarmer(_rmFarmers[j]);
		}
	}

	// callable by the DAO Council multisig, we can instantly remove a group of malicious farmers (no delay needed from DAO voting)
	function emergencyRemoveFarmers(address[] calldata _rmFarmers) external {
		require(msg.sender == daoCouncilMultisig, "FARMBOSSV1: !multisig");
		require(_rmFarmers.length <= LOOP_LIMIT, "FARMBOSSV1: >LOOP_LIMIT"); // dont allow unbounded loops

		// remove farmers
		for (uint256 j = 0; j < _rmFarmers.length; j++){
			farmers[_rmFarmers[j]] = false;

			emit RmFarmer(_rmFarmers[j]);
		}
	}

	function changeWhitelist(WhitelistData[] calldata _newActions, WhitelistData[] calldata _rmActions, Approves[] calldata _newApprovals, Approves[] calldata _newDepprovals) external {
		require(msg.sender == governance, "FARMBOSSV1: !governance");
		require(_newActions.length.add(_rmActions.length).add(_newApprovals.length).add(_newDepprovals.length) <= LOOP_LIMIT, "FARMBOSSV1: >LOOP_LIMIT"); // dont allow unbounded loops

		// add to whitelist, or change a whitelist entry if want to allow/disallow msg.value
		for (uint256 i = 0; i < _newActions.length; i++){
			_addWhitelist(_newActions[i].account, _newActions[i].fnSig, _newActions[i].valueAllowed);
		}
		// remove from whitelist
		for (uint256 j = 0; j < _rmActions.length; j++){
			whitelist[_rmActions[j].account][_rmActions[j].fnSig] = NOT_ALLOWED;

			emit RmWhitelist(_rmActions[j].account, _rmActions[j].fnSig);
		}
		// approve safely, needs to be set to zero, then max.
		for (uint256 k = 0; k < _newApprovals.length; k++){
			_approveMax(_newApprovals[k].token, _newApprovals[k].allow);
		}
		// de-approve these contracts
		for (uint256 l = 0; l < _newDepprovals.length; l++){
			IERC20(_newDepprovals[l].token).safeApprove(_newDepprovals[l].allow, 0);

			emit RmApproval(_newDepprovals[l].token, _newDepprovals[l].allow);
		}
	}

	function _addWhitelist(address _contract, bytes4 _fnSig, bool _msgValueAllowed) internal {
		if (_msgValueAllowed){
			whitelist[_contract][_fnSig] = ALLOWED_W_MSG_VALUE;
			emit NewWhitelist(_contract, _fnSig, ALLOWED_W_MSG_VALUE);
		}
		else {
			whitelist[_contract][_fnSig] = ALLOWED_NO_MSG_VALUE;
			emit NewWhitelist(_contract, _fnSig, ALLOWED_NO_MSG_VALUE);
		}
	}

	function _approveMax(address _token, address _account) internal {
		IERC20(_token).safeApprove(_account, 0);
		IERC20(_token).safeApprove(_account, type(uint256).max);

		emit NewApproval(_token, _account);
	}

	// callable by the DAO Council multisig, we can instantly remove a group of malicious contracts / approvals (no delay needed from DAO voting)
	function emergencyRemoveWhitelist(WhitelistData[] calldata _rmActions, Approves[] calldata _newDepprovals) external {
		require(msg.sender == daoCouncilMultisig, "FARMBOSSV1: !multisig");
		require(_rmActions.length.add(_newDepprovals.length) <= LOOP_LIMIT, "FARMBOSSV1: >LOOP_LIMIT"); // dont allow unbounded loops

		// remove from whitelist
		for (uint256 j = 0; j < _rmActions.length; j++){
			whitelist[_rmActions[j].account][_rmActions[j].fnSig] = NOT_ALLOWED;

			emit RmWhitelist(_rmActions[j].account, _rmActions[j].fnSig);
		}
		// de-approve these contracts
		for (uint256 l = 0; l < _newDepprovals.length; l++){
			IERC20(_newDepprovals[l].token).safeApprove(_newDepprovals[l].allow, 0);

			emit RmApproval(_newDepprovals[l].token, _newDepprovals[l].allow);
		}
	}
//SWC-104-Unchecked Call Return Value:L221
	function govExecute(address payable _target, uint256 _value, bytes calldata _data) external returns (bool, bytes memory){
		require(msg.sender == governance, "FARMBOSSV1: !governance");

		return _execute(_target, _value, _data);
	}

	function farmerExecute(address payable _target, uint256 _value, bytes calldata _data) external returns (bool, bytes memory){
		require(farmers[msg.sender] || msg.sender == daoCouncilMultisig, "FARMBOSSV1: !(farmer || multisig)");
		
		require(_checkContractAndFn(_target, _value, _data), "FARMBOSSV1: target.fn() not allowed. ask DAO for approval.");
		return _execute(_target, _value, _data);
	}

	// farmer is NOT allowed to call the functions approve, transfer on an ERC20
	// this will give the farmer direct control over assets held by the contract
	// governance must approve() farmer to interact with contracts & whitelist these contracts
	// even if contracts are whitelisted, farmer cannot call transfer/approve (many vault strategies will have ERC20 inheritance)
	// these approvals must also be called when setting up a new strategy from governance

	// if there is a strategy that has additonal functionality for the farmer to take control of assets ie: Uniswap "add a send"
	// then a "safe" wrapper contract must be made, ie: you can call Uniswap but "add a send is disabled, only msg.sender in this field"
	// strategies must be checked carefully so that farmers cannot take control of assets. trustless farming!
	function _checkContractAndFn(address _target, uint256 _value, bytes calldata _data) internal view returns (bool) {

		bytes4 _fnSig;
		if (_data.length < 4){ // we are calling a payable function, or the data is otherwise invalid (need 4 bytes for any fn call)
			_fnSig = FALLBACK_FN_SIG;
		}
		else { // we are calling a normal function, get the function signature from the calldata (first 4 bytes of calldata)

			//////////////////
			// NOTE: here we must use assembly in order to covert bytes -> bytes4
			// See consensys code for bytes -> bytes32: https://github.com/GNSPS/solidity-bytes-utils/blob/master/contracts/BytesLib.sol
			//////////////////

			bytes memory _fnSigBytes = bytes(_data[0:4]);
			assembly {
	            _fnSig := mload(add(add(_fnSigBytes, 0x20), 0))
	        }
			// _fnSig = abi.decode(bytes(_data[0:4]), (bytes4)); // NOTE: does not work, open solidity issue: https://github.com/ethereum/solidity/issues/9170
		}

		bytes4 _transferSig = 0xa9059cbb;
		bytes4 _approveSig = 0x095ea7b3;
		if (_fnSig == _transferSig || _fnSig == _approveSig || whitelist[_target][_fnSig] == NOT_ALLOWED){
			return false;
		}
		// check if value not allowed & value
		else if (whitelist[_target][_fnSig] == ALLOWED_NO_MSG_VALUE && _value > 0){
			return false;
		}
		// either ALLOWED_W_MSG_VALUE or ALLOWED_NO_MSG_VALUE with zero value
		return true;
	}

	// call arbitrary contract & function, forward all gas, return success? & data
	function _execute(address payable _target, uint256 _value, bytes memory _data) internal returns (bool, bytes memory){
		bool _success;
		bytes memory _returnData;

		if (_data.length == 4 && _data[0] == 0xff && _data[1] == 0xff && _data[2] == 0xff && _data[3] == 0xff){ // check if fallback function is invoked, send w/ no data
			(_success, _returnData) = _target.call{value: _value}("");
		}
		else {
			(_success, _returnData) = _target.call{value: _value}(_data);
		}

		if (_success){
			emit ExecuteSuccess(_returnData);
		}
		else {
			emit ExecuteERROR(_returnData);
		}

		return (_success, _returnData);
	}

	// we can call this function on the treasury from farmer/govExecute, but let's make it easy
	function rebalanceUp(uint256 _amount, address _farmerRewards) external {
		require(msg.sender == governance || farmers[msg.sender] || msg.sender == daoCouncilMultisig, "FARMBOSSV1: !(governance || farmer || multisig)");

		FarmTreasuryV1(treasury).rebalanceUp(_amount, _farmerRewards);
	}

	// is a Sushi/Uniswap wrapper to sell tokens for extra safety. This way, the swapping routes & destinations are checked & much safer than simply whitelisting the function
	// the function takes the calldata directly as an input. this way, calling the function is very similar to a normal farming call
	function sellExactTokensForUnderlyingToken(bytes calldata _data, bool _isSushi) external returns (uint[] memory amounts){
		require(msg.sender == governance || farmers[msg.sender] || msg.sender == daoCouncilMultisig, "FARMBOSSV1: !(governance || farmer || multisig)");

		(uint256 amountIn, uint256 amountOutMin, address[] memory path, address to, uint256 deadline) = abi.decode(_data[4:], (uint256, uint256, address[], address, uint256));

		// check the data to make sure it's an allowed sell
		require(to == address(this), "FARMBOSSV1: invalid sell, to != address(this)");

		// strictly require paths to be [token, WETH, underlying] 
		// note: underlying can be WETH --> [token, WETH]
		if (underlying == WETH){
			require(path.length == 2, "FARMBOSSV1: path.length != 2");
			require(path[1] == WETH, "FARMBOSSV1: WETH invalid sell, output != underlying");
		}
		else {
			require(path.length == 3, "FARMBOSSV1: path.length != 3");
			require(path[1] == WETH, "FARMBOSSV1: path[1] != WETH");
			require(path[2] == underlying, "FARMBOSSV1: invalid sell, output != underlying");
		}

		// DAO takes some percentage of CRVToken pre-sell as part of a long term strategy 
		if (path[0] == CRVToken && CRVTokenTake > 0){
			uint256 _amtTake = amountIn.mul(CRVTokenTake).div(max); // take some portion, and send to governance

			// redo the swap input variables, to account for the amount taken
			amountIn = amountIn.sub(_amtTake);
			amountOutMin = amountOutMin.mul(max.sub(CRVTokenTake)).div(max); // reduce the amountOutMin by the same ratio, therefore target slippage pct is the same

			IERC20(CRVToken).safeTransfer(governance, _amtTake);
		}

		if (_isSushi){ // sell on Sushiswap
			return IUniswapRouterV2(SushiswapRouter).swapExactTokensForTokens(amountIn, amountOutMin, path, to, deadline);
		}
		else { // sell on Uniswap
			return IUniswapRouterV2(UniswapRouter).swapExactTokensForTokens(amountIn, amountOutMin, path, to, deadline);
		}
	}

	function rescue(address _token, uint256 _amount) external {
        require(msg.sender == governance, "FARMBOSSV1: !governance");

        if (_token != address(0)){
            IERC20(_token).safeTransfer(governance, _amount);
        }
        else { // if _tokenContract is 0x0, then escape ETH
            governance.transfer(_amount);
        }
    }
}