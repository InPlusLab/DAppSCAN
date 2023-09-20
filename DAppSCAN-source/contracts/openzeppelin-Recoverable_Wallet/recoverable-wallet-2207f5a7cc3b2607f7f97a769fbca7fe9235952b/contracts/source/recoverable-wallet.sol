pragma solidity 0.5.8;

interface Erc1820Registry {
	function setInterfaceImplementer(address _addr, bytes32 _interfaceHash, address _implementer) external;
}

contract Erc777TokensRecipient {
	constructor() public {
		Erc1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24).setInterfaceImplementer(address(this), keccak256(abi.encodePacked("ERC777TokensRecipient")), address(this));
	}
	function tokensReceived(address, address, address, uint256, bytes calldata, bytes calldata) external { }
	function canImplementInterfaceForAddress(address, bytes32) external pure returns(bytes32) { return keccak256(abi.encodePacked("ERC1820_ACCEPT_MAGIC")); }
}

contract Ownable {
	event ownership_transfer_started(address indexed owner, address indexed pending_owner);
	event ownership_transfer_cancelled(address indexed owner, address indexed pending_owner);
	event ownership_transfer_finished(address indexed old_owner, address indexed new_owner);

	address public owner;
	address public pending_owner;

	constructor(address _owner) public {
		require(_owner != address(0), "Contract must have an owner.");
		owner = _owner;
	}

	modifier only_owner() {
		require(msg.sender == owner, "Only the owner may call this method.");
		_;
	}

	modifier only_pending_owner() {
		require(msg.sender == pending_owner, "Only the pending owner can call this method.");
		_;
	}

	//SWC-114-Transaction Order Dependence: L39-L57
	function start_ownership_transfer(address _pending_owner) external only_owner {
		require(_pending_owner != address(0), "Contract must have an owner.");
		pending_owner = _pending_owner;
		emit ownership_transfer_started(owner, pending_owner);
	}

	function cancel_ownership_transfer() external only_owner {
		address _pending_owner = pending_owner;
		pending_owner = address(0);
		emit ownership_transfer_cancelled(owner, _pending_owner);
	}

	function accept_ownership() external only_pending_owner {
		address _old_owner = owner;
		owner = pending_owner;
		pending_owner = address(0);
		emit ownership_transfer_finished(_old_owner, owner);
	}
}

contract RecoverableWallet is Ownable, Erc777TokensRecipient {
	event recovery_address_added(address indexed new_recoverer, uint256 recovery_delay_in_days);
	event recovery_address_removed(address indexed old_recoverer);
	event recovery_started(address indexed new_owner);
	event recovery_cancelled();
	event recovery_finished(address indexed new_pending_owner);

	mapping(address => uint16) public recovery_delays;
	address public active_recovery_address;
	//SWC-131-Presence of unused variables: L68
	uint256 public active_recovery_end_time = uint256(-1);

	modifier only_during_recovery() {
		require(active_recovery_address != address(0), "This method can only be called during a recovery.");
		_;
	}

	modifier only_outside_recovery() {
		require(active_recovery_address == address(0), "This method cannot be called during a recovery.");
		_;
	}

	constructor(address _initial_owner) Ownable(_initial_owner) public {
		//swc-Code With No Effects: L83
		reset_recovery();
	}

	// accept ETH into this contract
	function () external payable { }

	//SWC-114-Transaction Order Dependence: L88-L128
	function add_recovery_address(address _new_recovery_address, uint16 _recovery_delay_in_days) external only_owner only_outside_recovery {
		require(_recovery_delay_in_days > 0, "Recovery delay must be at least 1 day.");
		recovery_delays[_new_recovery_address] = _recovery_delay_in_days;
		emit recovery_address_added(_new_recovery_address, _recovery_delay_in_days);
	}

	function remove_recovery_address(address _old_recovery_address) external only_owner only_outside_recovery {
		recovery_delays[_old_recovery_address] = 0;
		emit recovery_address_removed(_old_recovery_address);
	}

	function start_recovery() external {
		uint16 _proposed_recovery_delay = recovery_delays[msg.sender];
		require(_proposed_recovery_delay != 0, "Only designated recovery addresseses can initiate the recovery process.");

		bool _in_recovery = active_recovery_address != address(0);
		if (_in_recovery) {
			// NOTE: the recovery address cannot change during recovery, so we can rely on this being != 0
			uint16 _active_recovery_delay = recovery_delays[active_recovery_address];
			require(_proposed_recovery_delay < _active_recovery_delay, "Recovery is already under way and new recovery doesn't have a higher priority.");
		}

		active_recovery_address = msg.sender;
		active_recovery_end_time = block.timestamp + _proposed_recovery_delay * 1 days;
		emit recovery_started(msg.sender);
	}

	function cancel_recovery() external only_owner only_during_recovery {
		reset_recovery();
		emit recovery_cancelled();
	}

	function finish_recovery() external only_during_recovery {
		//SWC-135-Code With No Effects: L124
		require(active_recovery_address != address(0), "No recovery in progress.");
		require(block.timestamp > active_recovery_end_time, "You must wait until the recovery delay is over before finishing the recovery.");

		pending_owner = active_recovery_address;
		reset_recovery();
		emit recovery_finished(pending_owner);
	}

	function deploy(uint256 _value, bytes calldata _data, uint256 _salt) external payable only_owner only_outside_recovery returns (address) {
		bytes memory _data2 = _data;
		address new_contract;
		/* solium-disable-next-line */
		assembly {
			new_contract := create2(_value, add(_data2, 32), mload(_data2), _salt)
		}
		require(new_contract != address(0), "Contract creation failed.");
		return new_contract;
	}

	function execute(address payable _to, uint256 _value, bytes calldata _data) external payable only_owner only_outside_recovery returns (bytes memory) {
		(bool _success, bytes memory _result) = _to.call.value(_value)(_data);
		require(_success, "Contract execution failed.");
		return _result;
	}

	function reset_recovery() private {
		//SWC-131-Presence of unused variables: L146
		active_recovery_address = address(0);
		active_recovery_end_time = uint256(-1);
	}
}

contract RecoverableWalletFactory {
	event wallet_created(address indexed owner, RecoverableWallet indexed wallet);

	function create_wallet() external returns (RecoverableWallet) {
		RecoverableWallet wallet = new RecoverableWallet(msg.sender);
		emit wallet_created(msg.sender, wallet);
		return wallet;
	}

	function exists() external pure returns (bytes32) {
		return 0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef;
	}
}
