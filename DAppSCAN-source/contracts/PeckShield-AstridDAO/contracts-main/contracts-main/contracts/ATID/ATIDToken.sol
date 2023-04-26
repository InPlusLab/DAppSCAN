// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../Dependencies/CheckContract.sol";
import "../Dependencies/Ownable.sol";
import "../Dependencies/SafeMath.sol";
import "../Interfaces/IATIDToken.sol";
import "../Interfaces/ILockupContractFactory.sol";
import "../Dependencies/console.sol";
import "./LockupContractFactory.sol";

/*
* Based upon OpenZeppelin's ERC20 contract:
* https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol
*  
* and their EIP2612 (ERC20Permit / ERC712) functionality:
* https://github.com/OpenZeppelin/openzeppelin-contracts/blob/53516bc555a454862470e7860a9b5254db4d00f5/contracts/token/ERC20/ERC20Permit.sol
* 
*
*  --- Functionality added specific to the ATIDToken ---
* 
* 1) Transfer protection: blacklist of addresses that are invalid recipients (i.e. core Astrid contracts) in external 
* transfer() and transferFrom() calls. The purpose is to protect users from losing tokens by mistakenly sending ATID directly to a Astrid
* core contract, when they should rather call the right function.
*
* 2) sendToATIDStaking(): callable only by Astrid core contracts, which move ATID tokens from user -> ATIDStaking contract.
*
* 3) Supply hard-capped at 1 billion
*
* 4) CommunityIssuance and LockupContractFactory addresses are set at deployment
*
* 5) 250 million tokens are minted at deployment to the CommunityIssuance contract
*/

contract ATIDToken is CheckContract, IATIDToken, Ownable {
    using SafeMath for uint256;

    // --- ERC20 Data ---

    string constant internal _NAME = "ATID";
    string constant internal _SYMBOL = "ATID";
    string constant internal _VERSION = "1";
    uint8 constant internal  _DECIMALS = 18;

    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;
    uint private _totalSupply;

    // --- EIP 2612 Data ---

    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 private constant _PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant _TYPE_HASH = 0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;

    // Cache the domain separator as an immutable value, but also store the chain id that it corresponds to, in order to
    // invalidate the cached domain separator if the chain id changes.
    bytes32 private immutable _CACHED_DOMAIN_SEPARATOR;
    uint256 private immutable _CACHED_CHAIN_ID;

    bytes32 private immutable _HASHED_NAME;
    bytes32 private immutable _HASHED_VERSION;
    
    mapping (address => uint256) private _nonces;

    // --- ATIDToken specific data ---

    // uint for use with SafeMath
    uint internal _1_MILLION = 1e24;    // 1e6 * 1e18 = 1e24
    uint internal _1_BILLION = 1e27;    // 1e9 * 1e18 = 1e27

    uint internal immutable deploymentStartTime;

    mapping (address => uint) public communityIssuanceAddresses;

    mapping (address => uint) public atidStakingAddresses;

    // Addresses that are allowed to send before unlock time
    mapping (address => uint) public senderWhitelistAddresses;
    // Addresses that are allowed to receive before unlock time
    mapping (address => uint) public recipientWhitelistAddresses;

    ILockupContractFactory public immutable lockupContractFactory;

    uint constant internal SECONDS_IN_ONE_MONTH = 2628000;
    uint public transferUnlockTime;

    // --- Events ---

    event CommunityIssuanceAdded(address _communityIssuanceAddress, uint _atidSupply);
    event ATIDStakingSet(address _atidStakingAddress, uint _active);
    event LockupContractDeployed(
        address _lockupContractAddress,
        address _beneficiary,
        uint _amount,
        uint _monthsToWaitBeforeUnlock,
        uint _releaseSchedule
    );
    event TransferUnlockTimeSet(uint _unlockTime);
    event TransferSenderWhitelistAddressSet(address _senderAddress, uint _active);
    event TransferRecipientWhitelistAddressSet(address _recipientAddress, uint _active);

    // --- Functions ---

    constructor
    (
        // address _communityIssuanceAddress
        // address _bountyAddress,
        // address _lpRewardsAddress
    ) 
        Ownable()
    {
        deploymentStartTime  = block.timestamp;
        transferUnlockTime = block.timestamp + (3*SECONDS_IN_ONE_MONTH);

        // ATIDToken is the owner of lockupContractFactory.
        ILockupContractFactory _lockupContractFactory = new LockupContractFactory();
        lockupContractFactory = _lockupContractFactory;
        _lockupContractFactory.setATIDTokenAddress(address(this));

        bytes32 hashedName = keccak256(bytes(_NAME));
        bytes32 hashedVersion = keccak256(bytes(_VERSION));

        _HASHED_NAME = hashedName;
        _HASHED_VERSION = hashedVersion;
        _CACHED_CHAIN_ID = _chainID();
        _CACHED_DOMAIN_SEPARATOR = _buildDomainSeparator(_TYPE_HASH, hashedName, hashedVersion);
    }

    // --- Owner privileged functions ---

    // Add a community issuance.
    function addCommunityIssuance(
        address _communityIssuanceAddress,
        uint _atidSupply
    ) external onlyOwner {
        checkContract(_communityIssuanceAddress);
        // Only add and mint for community issuance if first seen, to avoid duplicate
        // add community issuance calls.
        if (communityIssuanceAddresses[_communityIssuanceAddress] != 0) {
            return;
        }
        communityIssuanceAddresses[_communityIssuanceAddress] = 1;
        _mint(_communityIssuanceAddress, _atidSupply);
        emit CommunityIssuanceAdded(_communityIssuanceAddress, _atidSupply);
    }

    // Add as an ATID staking address.
    function setATIDStaking(
        address _atidStakingAddress,
        uint _active
    ) external onlyOwner {
        checkContract(_atidStakingAddress);
        atidStakingAddresses[_atidStakingAddress] = _active;
        emit ATIDStakingSet(_atidStakingAddress, _active);
    }

    // Deploys a lockup contract for a beneficiary and mint tokens for it.
    function deployLockupContract(
        address _beneficiary,
        uint _amount,
        uint _monthsToWaitBeforeUnlock,
        uint _releaseSchedule
    ) external onlyOwner {
        address deployedAddress = lockupContractFactory.deployLockupContract(
            _beneficiary,
            _amount,
            _monthsToWaitBeforeUnlock,
            _releaseSchedule
        );
        _mint(deployedAddress, _amount);
        emit LockupContractDeployed(deployedAddress, _beneficiary, _amount, _monthsToWaitBeforeUnlock, _releaseSchedule);
    }

    // Update timestamp that enables token transfer.
    function setTransferUnlockTime(
        uint _unlockTime
    ) external onlyOwner {
        transferUnlockTime = _unlockTime;
        emit TransferUnlockTimeSet(_unlockTime);
    }

    // Set whitelist address that is allowed to be the sender of transfer() calls before tranfer unlock timestamp.
    function setSenderWhitelistAddress(
        address _senderAddress,
        uint _active
    ) external onlyOwner {
        require(_senderAddress != address(0), "ATIDToken: must be a valid address");
        senderWhitelistAddresses[_senderAddress] = _active;
        emit TransferSenderWhitelistAddressSet(_senderAddress, _active);
    }
    // Set whitelist address that is allowed to be the recipient of transfer() calls before tranfer unlock timestamp.
    function setRecipientWhitelistAddress(
        address _recipientAddress,
        uint _active
    ) external onlyOwner {
        require(_recipientAddress != address(0), "ATIDToken: must be a valid address");
        recipientWhitelistAddresses[_recipientAddress] = _active;
        emit TransferRecipientWhitelistAddressSet(_recipientAddress, _active);
    }

    // --- External functions ---

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function getDeploymentStartTime() external view override returns (uint256) {
        return deploymentStartTime;
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        _requireValidRecipient(recipient);
        require(_isTransferAllowed(msg.sender, recipient), "ATIDToken: transfer not allowed");

        // Otherwise, standard transfer functionality
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        _requireValidRecipient(recipient);
        require(_isTransferAllowed(sender, recipient), "ATIDToken: transfer not allowed");

        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, _allowances[sender][msg.sender].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) external override returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) external override returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }

    function sendToATIDStaking(address _sender, uint256 _amount) external override {
        _requireCallerIsATIDStaking();
        _transfer(_sender, msg.sender, _amount);
    }

    // --- EIP 2612 functionality ---

    function domainSeparator() public view override returns (bytes32) {    
        if (_chainID() == _CACHED_CHAIN_ID) {
            return _CACHED_DOMAIN_SEPARATOR;
        } else {
            return _buildDomainSeparator(_TYPE_HASH, _HASHED_NAME, _HASHED_VERSION);
        }
    }

    function permit
    (
        address owner, 
        address spender, 
        uint amount, 
        uint deadline, 
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) 
        external 
        override 
    {            
        require(owner != address(0), 'ATID: owner cannot be address 0');
        require(deadline >= block.timestamp, 'ATID: expired deadline');
        bytes32 digest = keccak256(abi.encodePacked('\x19\x01', 
                         domainSeparator(), keccak256(abi.encode(
                         _PERMIT_TYPEHASH, owner, spender, amount, 
                         _nonces[owner]++, deadline))));
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress == owner, 'ATID: invalid signature');
        _approve(owner, spender, amount);
    }

    function nonces(address owner) external view override returns (uint256) { // FOR EIP 2612
        return _nonces[owner];
    }

    // --- Internal operations ---

    function _chainID() private view returns (uint256 chainID) {
        assembly {
            chainID := chainid()
        }
    }

    function _buildDomainSeparator(bytes32 typeHash, bytes32 name, bytes32 version) private view returns (bytes32) {
        return keccak256(abi.encode(typeHash, name, version, _chainID(), address(this)));
    }

    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _balances[sender] = _balances[sender].sub(amount, "ERC20: transfer amount exceeds balance");
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");

        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    // --- 'require' functions ---
    
    function _requireValidRecipient(address _recipient) internal view {
        require(
            _recipient != address(0) && 
            _recipient != address(this),
            "ATID: Cannot transfer tokens directly to the ATID token contract or the zero address"
        );
        require(
            communityIssuanceAddresses[_recipient] == 0 &&
            atidStakingAddresses[_recipient] == 0,
            "ATID: Cannot transfer tokens directly to the community issuance or staking contracts"
        );
    }

    function _requireCallerIsATIDStaking() internal view {
         require(atidStakingAddresses[msg.sender] != 0, "ATIDToken: caller must be an ATIDStaking contract");
    }

    // Check if transfer is allowed.
    function _isTransferAllowed(address _sender, address _recipient) internal view returns (bool) {
        // Transfer allowed after unlock timestamp has passed.
        if (block.timestamp > transferUnlockTime) {
            return true;
        }
        // Transfer allowed if either the sender or the recipient is specially allowed.
        if (senderWhitelistAddresses[_sender] != 0 || recipientWhitelistAddresses[_recipient] != 0) {
            return true;
        }
        // Otherwise, the sender need to be CommunityIssuance or ATIDStaking.
        return communityIssuanceAddresses[_sender] != 0 || atidStakingAddresses[_sender] != 0;
    }

    // --- Optional functions ---

    function name() external pure override returns (string memory) {
        return _NAME;
    }

    function symbol() external pure override returns (string memory) {
        return _SYMBOL;
    }

    function decimals() external pure override returns (uint8) {
        return _DECIMALS;
    }

    function version() external pure override returns (string memory) {
        return _VERSION;
    }

    function permitTypeHash() external pure override returns (bytes32) {
        return _PERMIT_TYPEHASH;
    }
}
