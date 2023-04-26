// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./Interfaces/IBAIToken.sol";
import "./Dependencies/SafeMath.sol";
import "./Dependencies/CheckContract.sol";
import "./Dependencies/console.sol";
import "./Dependencies/Ownable.sol";
/*
*
* Based upon OpenZeppelin's ERC20 contract:
* https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol
*  
* and their EIP2612 (ERC20Permit / ERC712) functionality:
* https://github.com/OpenZeppelin/openzeppelin-contracts/blob/53516bc555a454862470e7860a9b5254db4d00f5/contracts/token/ERC20/ERC20Permit.sol
* 
*
* --- Functionality added specific to the BAIToken ---
* 
* 1) Transfer protection: blacklist of addresses that are invalid recipients (i.e. core Astrid contracts) in external 
* transfer() and transferFrom() calls. The purpose is to protect users from losing tokens by mistakenly sending BAI directly to a Astrid 
* core contract, when they should rather call the right function. 
*
* 2) sendToPool() and returnFromPool(): functions callable only Astrid core contracts, which move BAI tokens between Astrid <-> user.
*/

contract BAIToken is CheckContract, IBAIToken, Ownable {
    using SafeMath for uint256;
    
    uint256 private _totalSupply;
    string constant internal _NAME = "BAI Stablecoin";
    string constant internal _SYMBOL = "BAI";
    string constant internal _VERSION = "1";
    uint8 constant internal _DECIMALS = 18;
    
    // --- Data for EIP2612 ---
    
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
    
    // User data for BAI token
    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;  
    
    // --- Addresses ---
    mapping (address => uint) public vaultManagerAddresses;
    mapping (address => uint) public stabilityPoolAddresses;
    mapping (address => uint) public borrowerOperationsAddresses;

    // address public immutable vaultManagerAddress;
    // address public immutable stabilityPoolAddress;
    // address public immutable borrowerOperationsAddress;

    constructor
    ( 
        // address _vaultManagerAddress,
        // address _stabilityPoolAddress,
        // address _borrowerOperationsAddress
    ) Ownable()
    {  
        // checkContract(_vaultManagerAddress);
        // checkContract(_stabilityPoolAddress);
        // checkContract(_borrowerOperationsAddress);

        // vaultManagerAddress = _vaultManagerAddress;
        // emit VaultManagerAddressChanged(_vaultManagerAddress);

        // stabilityPoolAddress = _stabilityPoolAddress;
        // emit StabilityPoolAddressChanged(_stabilityPoolAddress);

        // borrowerOperationsAddress = _borrowerOperationsAddress;        
        // emit BorrowerOperationsAddressChanged(_borrowerOperationsAddress);
        
        bytes32 hashedName = keccak256(bytes(_NAME));
        bytes32 hashedVersion = keccak256(bytes(_VERSION));
        
        _HASHED_NAME = hashedName;
        _HASHED_VERSION = hashedVersion;
        _CACHED_CHAIN_ID = _chainID();
        _CACHED_DOMAIN_SEPARATOR = _buildDomainSeparator(_TYPE_HASH, hashedName, hashedVersion);
    }

    // --- Events ---

    event VaultManagerAddressSet(address _vaultManagerAddress, uint _active);
    event StabilityPoolAddressSet(address _stabilityPoolAddress, uint _active);
    event BorrowerOperationsAddressSet(address _borrowerOperationsAddress, uint _active);

    // --- Privileged operations ---

    function setVaultManagerAddress(address _vaultManagerAddress, uint _active) external onlyOwner {
        checkContract(_vaultManagerAddress);
        vaultManagerAddresses[_vaultManagerAddress] = _active;
        emit VaultManagerAddressSet(_vaultManagerAddress, _active);
    }
    function setStabilityPoolAddress(address _stabilityPoolAddress, uint _active) external onlyOwner {
        checkContract(_stabilityPoolAddress);
        stabilityPoolAddresses[_stabilityPoolAddress] = _active;
        emit StabilityPoolAddressSet(_stabilityPoolAddress, _active);
    }
    function setBorrowerOperationsAddress(address _borrowerOperationsAddress, uint _active) external onlyOwner {
        checkContract(_borrowerOperationsAddress);
        borrowerOperationsAddresses[_borrowerOperationsAddress] = _active;
        emit BorrowerOperationsAddressSet(_borrowerOperationsAddress, _active);
    }

    // --- Functions for intra-Astrid calls ---

    function mint(address _account, uint256 _amount) external override {
        _requireCallerIsBorrowerOperations();
        _mint(_account, _amount);
    }

    function burn(address _account, uint256 _amount) external override {
        _requireCallerIsBOorVaultMorSP();
        _burn(_account, _amount);
    }

    function sendToPool(address _sender,  address _poolAddress, uint256 _amount) external override {
        _requireCallerIsStabilityPool();
        _transfer(_sender, _poolAddress, _amount);
    }

    function returnFromPool(address _poolAddress, address _receiver, uint256 _amount) external override {
        _requireCallerIsVaultMorSP();
        _transfer(_poolAddress, _receiver, _amount);
    }

    // --- External functions ---

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        _requireValidRecipient(recipient);
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

    // --- EIP 2612 Functionality ---

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
        require(owner != address(0), "BAI: owner cannot be address 0");
        require(deadline >= block.timestamp, "BAI: expired deadline");
        bytes32 digest = keccak256(abi.encodePacked('\x19\x01', 
                         domainSeparator(), keccak256(abi.encode(
                         _PERMIT_TYPEHASH, owner, spender, amount, 
                         _nonces[owner]++, deadline))));
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress == owner, "BAI: invalid signature");
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

    // --- Internal operations ---
    // Warning: sanity checks (for sender and recipient) should have been done before calling these internal functions

    function _transfer(address sender, address recipient, uint256 amount) internal {
        assert(sender != address(0));
        assert(recipient != address(0));

        _balances[sender] = _balances[sender].sub(amount, "ERC20: transfer amount exceeds balance");
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }

    function _mint(address account, uint256 amount) internal {
        assert(account != address(0));

        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal {
        assert(account != address(0));
        
        _balances[account] = _balances[account].sub(amount, "ERC20: burn amount exceeds balance");
        _totalSupply = _totalSupply.sub(amount);
        emit Transfer(account, address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        assert(owner != address(0));
        assert(spender != address(0));

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    // --- 'require' functions ---

    function _requireValidRecipient(address _recipient) internal view {
        require(
            _recipient != address(0) && 
            _recipient != address(this),
            "BAI: Cannot transfer tokens directly to the BAI token contract or the zero address"
        );
        require(
            stabilityPoolAddresses[_recipient] == 0 && 
            vaultManagerAddresses[_recipient] == 0 && 
            borrowerOperationsAddresses[_recipient] == 0, 
            "BAI: Cannot transfer tokens directly to the StabilityPool, VaultManager or BorrowerOps"
        );
    }

    function _requireCallerIsBorrowerOperations() internal view {
        require(borrowerOperationsAddresses[msg.sender] != 0, "BAIToken: Caller is not BorrowerOperations");
    }

    function _requireCallerIsBOorVaultMorSP() internal view {
        require(
            borrowerOperationsAddresses[msg.sender] != 0 ||
            vaultManagerAddresses[msg.sender] != 0 ||
            stabilityPoolAddresses[msg.sender] != 0,
            "BAI: Caller is neither BorrowerOperations nor VaultManager nor StabilityPool"
        );
    }

    function _requireCallerIsStabilityPool() internal view {
        require(stabilityPoolAddresses[msg.sender] != 0, "BAI: Caller is not the StabilityPool");
    }

    function _requireCallerIsVaultMorSP() internal view {
        require(
            vaultManagerAddresses[msg.sender] != 0 || stabilityPoolAddresses[msg.sender] != 0,
            "BAI: Caller is neither VaultManager nor StabilityPool");
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
