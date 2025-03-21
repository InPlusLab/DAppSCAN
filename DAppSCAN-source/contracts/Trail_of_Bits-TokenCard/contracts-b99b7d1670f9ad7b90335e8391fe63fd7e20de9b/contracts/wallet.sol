// SWC-135-Code With No Effects: L1 - L792
/**
 *  The Consumer Contract Wallet
 *  Copyright (C) 2019 The Contract Wallet Company Limited
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.

 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.

 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

pragma solidity ^0.4.25;

import "./licence.sol";
import "./internals/ownable.sol";
import "./internals/controllable.sol";
import "./internals/ensResolvable.sol";
import "./internals/tokenWhitelistable.sol";
import "./externals/SafeMath.sol";
import "./externals/ERC20.sol";
import "./externals/ERC165.sol";


/// @title ControllableOwnable combines Controllable and Ownable
/// @dev providing an additional modifier to check if Owner or Controller
contract ControllableOwnable is Controllable, Ownable {
    /// @dev Check if the sender is the Owner or one of the Controllers
    modifier onlyOwnerOrController() {
        require (_isOwner(msg.sender) || _isController(msg.sender), "either owner or controller");
        _;
    }
}


/// @title AddressWhitelist provides payee-whitelist functionality.
/// @dev This contract will allow the user to maintain a whitelist of addresses
/// @dev These addresses will live outside of the various spend limits
contract AddressWhitelist is ControllableOwnable {
    using SafeMath for uint256;

    event AddedToWhitelist(address _sender, address[] _addresses);
    event SubmittedWhitelistAddition(address[] _addresses, bytes32 _hash);
    event CancelledWhitelistAddition(address _sender, bytes32 _hash);

    event RemovedFromWhitelist(address _sender, address[] _addresses);
    event SubmittedWhitelistRemoval(address[] _addresses, bytes32 _hash);
    event CancelledWhitelistRemoval(address _sender, bytes32 _hash);

    mapping(address => bool) public whitelistMap;
    address[] public whitelistArray;
    address[] private _pendingWhitelistAddition;
    address[] private _pendingWhitelistRemoval;
    bool public submittedWhitelistAddition;
    bool public submittedWhitelistRemoval;
    bool public isSetWhitelist;

    /// @dev Check if the provided addresses contain the owner or the zero-address address.
    modifier hasNoOwnerOrZeroAddress(address[] _addresses) {
        for (uint i = 0; i < _addresses.length; i++) {
            require(!_isOwner(_addresses[i]), "provided whitelist contains the owner address");
            require(_addresses[i] != address(0), "provided whitelist contains the zero address");
        }
        _;
    }

    /// @dev Check that neither addition nor removal operations have already been submitted.
    modifier noActiveSubmission() {
        require(!submittedWhitelistAddition && !submittedWhitelistRemoval, "whitelist operation has already been submitted");
        _;
    }

    /// @dev Getter for pending addition array.
    function pendingWhitelistAddition() external view returns (address[]) {
        return _pendingWhitelistAddition;
    }

    /// @dev Getter for pending removal array.
    function pendingWhitelistRemoval() external view returns (address[]) {
        return _pendingWhitelistRemoval;
    }

    /// @dev Add initial addresses to the whitelist.
    /// @param _addresses are the Ethereum addresses to be whitelisted.
    function setWhitelist(address[] _addresses) external onlyOwner hasNoOwnerOrZeroAddress(_addresses) {
        // Require that the whitelist has not been initialized.
        require(!isSetWhitelist, "whitelist has already been initialized");
        // Add each of the provided addresses to the whitelist.
        for (uint i = 0; i < _addresses.length; i++) {
            // adds to the whitelist mapping
            whitelistMap[_addresses[i]] = true;
            // adds to the whitelist array
            whitelistArray.push(_addresses[i]);
        }
        isSetWhitelist = true;
        // Emit the addition event.
        emit AddedToWhitelist(msg.sender, _addresses);
    }

    /// @dev Add addresses to the whitelist.
    /// @param _addresses are the Ethereum addresses to be whitelisted.
    function submitWhitelistAddition(address[] _addresses) external onlyOwner noActiveSubmission hasNoOwnerOrZeroAddress(_addresses) {
        // Require that the whitelist has been initialized.
        require(isSetWhitelist, "whitelist has not been initialized");
        // Require this array of addresses not empty
        require(_addresses.length > 0, "pending whitelist addition is empty");
        // Set the provided addresses to the pending addition addresses.
        _pendingWhitelistAddition = _addresses;
        // Flag the operation as submitted.
        submittedWhitelistAddition = true;
        // Emit the submission event.
        emit SubmittedWhitelistAddition(_addresses, calculateHash(_addresses));
    }

    /// @dev Confirm pending whitelist addition.
    /// @dev This will only ever be applied post 2FA, by one of the Controllers
    /// @param _hash is the hash of the pending whitelist array, a form of lamport lock
    function confirmWhitelistAddition(bytes32 _hash) external onlyController {
        // Require that the whitelist addition has been submitted.
        require(submittedWhitelistAddition, "whitelist addition has not been submitted");
        // Require that confirmation hash and the hash of the pending whitelist addition match
        require(_hash == calculateHash(_pendingWhitelistAddition), "hash of the pending whitelist addition do not match");
        // Whitelist pending addresses.
        for (uint i = 0; i < _pendingWhitelistAddition.length; i++) {
            // check if it doesn't exist already.
            if (!whitelistMap[_pendingWhitelistAddition[i]]) {
                 // add to the Map and the Array
                whitelistMap[_pendingWhitelistAddition[i]] = true;
                whitelistArray.push(_pendingWhitelistAddition[i]);
            }
        }
        // Emit the addition event.
        emit AddedToWhitelist(msg.sender, _pendingWhitelistAddition);
        // Reset pending addresses.
        delete _pendingWhitelistAddition;
        // Reset the submission flag.
        submittedWhitelistAddition = false;
    }

    /// @dev Cancel pending whitelist addition.
    function cancelWhitelistAddition(bytes32 _hash) external onlyOwnerOrController {
        // Check if operation has been submitted.
        require(submittedWhitelistAddition, "whitelist addition has not been submitted");
        // Require that confirmation hash and the hash of the pending whitelist addition match
        require(_hash == calculateHash(_pendingWhitelistAddition), "hash of the pending whitelist addition does not match");
        // Reset pending addresses.
        delete _pendingWhitelistAddition;
        // Reset the submitted operation flag.
        submittedWhitelistAddition = false;
        // Emit the cancellation event.
        emit CancelledWhitelistAddition(msg.sender, _hash);
    }

    /// @dev Remove addresses from the whitelist.
    /// @param _addresses are the Ethereum addresses to be removed.
    function submitWhitelistRemoval(address[] _addresses) external onlyOwner noActiveSubmission {
        // Require that the whitelist has been initialized.
        require(isSetWhitelist, "whitelist has not been initialized");
        // Require that the array of addresses is not empty
        require(_addresses.length > 0, "pending whitelist removal is empty");
        // Add the provided addresses to the pending addition list.
        _pendingWhitelistRemoval = _addresses;
        // Flag the operation as submitted.
        submittedWhitelistRemoval = true;
        // Emit the submission event.
        emit SubmittedWhitelistRemoval(_addresses, calculateHash(_addresses));
    }

    /// @dev Confirm pending removal of whitelisted addresses.
    function confirmWhitelistRemoval(bytes32 _hash) external onlyController {
        // Require that the pending whitelist is not empty and the operation has been submitted.
        require(submittedWhitelistRemoval, "whitelist removal has not been submitted");
        // Require that confirmation hash and the hash of the pending whitelist removal match
        require(_hash == calculateHash(_pendingWhitelistRemoval), "hash of the pending whitelist removal does not match the confirmed hash");
        // Remove pending addresses.
        for (uint i = 0; i < _pendingWhitelistRemoval.length; i++) {
            // check if it exists
            if (whitelistMap[_pendingWhitelistRemoval[i]]) {
                whitelistMap[_pendingWhitelistRemoval[i]] = false;
                for (uint j = 0; j < whitelistArray.length.sub(1); j++) {
                    if (whitelistArray[j] == _pendingWhitelistRemoval[i]) {
                        whitelistArray[j] = whitelistArray[whitelistArray.length - 1];
                        break;
                    }
                }
                whitelistArray.length--;
            }
        }
        // Emit the removal event.
        emit RemovedFromWhitelist(msg.sender, _pendingWhitelistRemoval);
        // Reset pending addresses.
        delete _pendingWhitelistRemoval;
        // Reset the submission flag.
        submittedWhitelistRemoval = false;
    }

    /// @dev Cancel pending removal of whitelisted addresses.
    function cancelWhitelistRemoval(bytes32 _hash) external onlyOwnerOrController {
        // Check if operation has been submitted.
        require(submittedWhitelistRemoval, "whitelist removal has not been submitted");
        // Require that confirmation hash and the hash of the pending whitelist removal match
        require(_hash == calculateHash(_pendingWhitelistRemoval), "hash of the pending whitelist removal do not match");
        // Reset pending addresses.
        delete _pendingWhitelistRemoval;
        // Reset pending addresses.
        submittedWhitelistRemoval = false;
        // Emit the cancellation event.
        emit CancelledWhitelistRemoval(msg.sender, _hash);
    }

    /// @dev Method used to hash our whitelist address arrays.
    function calculateHash(address[] _addresses) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_addresses));
    }
}


/// @title DailyLimitTrait This trait allows for daily limits to be included in other contracts.
/// This contract will allow for a DailyLimit object to be instantiated and used.
contract DailyLimitTrait {
    using SafeMath for uint256;

    struct DailyLimit {
        uint value;
        uint available;
        uint limitDay;
        uint pending;
        bool set;
    }

    /// @dev Returns the available daily balance - accounts for daily limit reset.
    /// @return amount of available to spend within the current day in base units.
    function _getAvailableLimit(DailyLimit storage dl) internal view returns (uint) {
        if (now > dl.limitDay + 24 hours) {
            return dl.value;
        } else {
            return dl.available;
        }
    }

    /// @dev Use up amount within the daily limit. Will fail if amount is larger than daily limit.
    function _enforceLimit(DailyLimit storage dl, uint _amount) internal {
        // Account for the spend limit daily reset.
        _updateAvailableLimit(dl);
        require(dl.available >= _amount, "available has to be greater or equal to use amount");
        dl.available = dl.available.sub(_amount);
    }

    /// @dev Set the daily limit.
    /// @param _amount is the daily limit amount in base units.
    function _setLimit(DailyLimit storage dl, uint _amount) internal {
        // Require that the spend limit has not been set yet.
        require(!dl.set, "daily limit has already been set");
        // Modify spend limit based on the provided value.
        _modifyLimit(dl, _amount);
        // Flag the operation as set.
        dl.set = true;
    }

    /// @dev Submit a daily limit update, needs to be confirmed.
    /// @param _amount is the daily limit amount in base units.
    function _submitLimitUpdate(DailyLimit storage dl, uint _amount) internal {
        // Require that the spend limit has been set.
        require(dl.set, "limit has not been set");
        // Assign the provided amount to pending daily limit.
        dl.pending = _amount;
    }

    /// @dev Confirm pending set daily limit operation.
    function _confirmLimitUpdate(DailyLimit storage dl, uint _amount) internal {
        // Require that pending and confirmed spend limit are the same
        require(dl.pending == _amount, "confirmed and submitted limits dont match");
        // Modify spend limit based on the pending value.
        _modifyLimit(dl, dl.pending);
    }

    /// @dev Update available spend limit based on the daily reset.
    function _updateAvailableLimit(DailyLimit storage dl) private {
        if (now > dl.limitDay.add(24 hours)) {
            // Advance the current day by how many days have passed.
            uint extraDays = now.sub(dl.limitDay).div(24 hours);
            dl.limitDay = dl.limitDay.add(extraDays.mul(24 hours));
            // Set the available limit to the current spend limit.
            dl.available = dl.value;
        }
    }

    /// @dev Modify the spend limit and spend available based on the provided value.
    /// @dev _amount is the daily limit amount in wei.
    function _modifyLimit(DailyLimit storage dl, uint _amount) private {
        // Account for the spend limit daily reset.
        _updateAvailableLimit(dl);
        // Set the daily limit to the provided amount.
        dl.value = _amount;
        // Lower the available limit if it's higher than the new daily limit.
        if (dl.available > dl.value) {
            dl.available = dl.value;
        }
    }
}


/// @title  it provides daily spend limit functionality.
contract SpendLimit is ControllableOwnable, DailyLimitTrait {
    event SetSpendLimit(address _sender, uint _amount);
    event SubmittedSpendLimitUpdate(uint _amount);

    DailyLimit internal _spendLimit;

    /// @dev Constructor initializes the daily spend limit in wei.
    constructor(uint _limit_) internal {
        _spendLimit = DailyLimit(_limit_, _limit_, now, 0, false);
    }

    /// @dev Sets the initial daily spend (aka transfer) limit for non-whitelisted addresses.
    /// @param _amount is the daily limit amount in wei.
    function setSpendLimit(uint _amount) external onlyOwner {
        _setLimit(_spendLimit, _amount);
        emit SetSpendLimit(msg.sender, _amount);
    }

    /// @dev Submit a daily transfer limit update for non-whitelisted addresses.
    /// @param _amount is the daily limit amount in wei.
    function submitSpendLimitUpdate(uint _amount) external onlyOwner {
        _submitLimitUpdate(_spendLimit, _amount);
        emit SubmittedSpendLimitUpdate(_amount);
    }

    /// @dev Confirm pending set daily limit operation.
    function confirmSpendLimitUpdate(uint _amount) external onlyController {
        _confirmLimitUpdate(_spendLimit, _amount);
        emit SetSpendLimit(msg.sender, _amount);
    }

    function spendLimitAvailable() external view returns (uint) {
        return _getAvailableLimit(_spendLimit);
    }

    function spendLimitValue() external view returns (uint) {
        return _spendLimit.value;
    }

    function spendLimitSet() external view returns (bool) {
        return _spendLimit.set;
    }

    function spendLimitPending() external view returns (uint) {
        return _spendLimit.pending;
    }
}


//// @title GasTopUpLimit provides daily limit functionality.
contract GasTopUpLimit is ControllableOwnable, DailyLimitTrait {

    event SetGasTopUpLimit(address _sender, uint _amount);
    event SubmittedGasTopUpLimitUpdate(uint _amount);

    uint constant private _MINIMUM_GAS_TOPUP_LIMIT = 1 finney;
    uint constant private _MAXIMUM_GAS_TOPUP_LIMIT = 500 finney;

    DailyLimit internal _gasTopUpLimit;

    /// @dev Constructor initializes the daily gas topup limit in wei.
    constructor() internal {
        _gasTopUpLimit = DailyLimit(_MAXIMUM_GAS_TOPUP_LIMIT, _MAXIMUM_GAS_TOPUP_LIMIT, now, 0, false);
    }

    /// @dev Sets the daily gas top up limit.
    /// @param _amount is the gas top up amount in wei.
    function setGasTopUpLimit(uint _amount) external onlyOwner {
        require(_MINIMUM_GAS_TOPUP_LIMIT <= _amount && _amount <= _MAXIMUM_GAS_TOPUP_LIMIT, "gas top up amount is outside the min/max range");
        _setLimit(_gasTopUpLimit, _amount);
        emit SetGasTopUpLimit(msg.sender, _amount);
    }

    /// @dev Submit a daily gas top up limit update.
    /// @param _amount is the daily top up gas limit amount in wei.
    function submitGasTopUpLimitUpdate(uint _amount) external onlyOwner {
        require(_MINIMUM_GAS_TOPUP_LIMIT <= _amount && _amount <= _MAXIMUM_GAS_TOPUP_LIMIT, "gas top up amount is outside the min/max range");
        _submitLimitUpdate(_gasTopUpLimit, _amount);
        emit SubmittedGasTopUpLimitUpdate(_amount);
    }

    /// @dev Confirm pending set top up gas limit operation.
    function confirmGasTopUpLimitUpdate(uint _amount) external onlyController {
        _confirmLimitUpdate(_gasTopUpLimit, _amount);
        emit SetGasTopUpLimit(msg.sender, _amount);
    }

    function gasTopUpLimitAvailable() external view returns (uint) {
        return _getAvailableLimit(_gasTopUpLimit);
    }

    function gasTopUpLimitValue() external view returns (uint) {
        return _gasTopUpLimit.value;
    }

    function gasTopUpLimitSet() external view returns (bool) {
        return _gasTopUpLimit.set;
    }

    function gasTopUpLimitPending() external view returns (uint) {
        return _gasTopUpLimit.pending;
    }
}


/// @title LoadLimit provides daily load limit functionality.
contract LoadLimit is ControllableOwnable, DailyLimitTrait {

    event SetLoadLimit(address _sender, uint _amount);
    event SubmittedLoadLimitUpdate(uint _amount);

    uint constant private _MINIMUM_LOAD_LIMIT = 1 finney;
    uint private _maximumLoadLimit;

    DailyLimit internal _loadLimit;

    /// @dev Sets a daily card load limit.
    /// @param _amount is the card load amount in current stablecoin base units.
    function setLoadLimit(uint _amount) external onlyOwner {
        require(_MINIMUM_LOAD_LIMIT <= _amount && _amount <= _maximumLoadLimit, "card load amount is outside the min/max range");
        _setLimit(_loadLimit, _amount);
        emit SetLoadLimit(msg.sender, _amount);
    }

    /// @dev Submit a daily load limit update.
    /// @param _amount is the daily load limit amount in wei.
    function submitLoadLimitUpdate(uint _amount) external onlyOwner {
        require(_MINIMUM_LOAD_LIMIT <= _amount && _amount <= _maximumLoadLimit, "card load amount is outside the min/max range");
        _submitLimitUpdate(_loadLimit, _amount);
        emit SubmittedLoadLimitUpdate(_amount);
    }

    /// @dev Confirm pending set load limit operation.
    function confirmLoadLimitUpdate(uint _amount) external onlyController {
        _confirmLimitUpdate(_loadLimit, _amount);
        emit SetLoadLimit(msg.sender, _amount);
    }

    function loadLimitAvailable() external view returns (uint) {
        return _getAvailableLimit(_loadLimit);
    }

    function loadLimitValue() external view returns (uint) {
        return _loadLimit.value;
    }

    function loadLimitSet() external view returns (bool) {
        return _loadLimit.set;
    }

    function loadLimitPending() external view returns (uint) {
        return _loadLimit.pending;
    }

    /// @dev initializes the daily load limit.
    /// @param _maxLimit is the maximum load limit amount in stablecoin base units.
    function _initializeLoadLimit(uint _maxLimit) internal {
        _maximumLoadLimit = _maxLimit;
        _loadLimit = DailyLimit(_maximumLoadLimit, _maximumLoadLimit, now, 0, false);
    }
}


//// @title Asset store with extra security features.
contract Vault is AddressWhitelist, SpendLimit, ERC165, TokenWhitelistable {

    using SafeMath for uint256;

    event Received(address _from, uint _amount);
    event Transferred(address _to, address _asset, uint _amount);

    /// @dev Supported ERC165 interface ID.
    bytes4 private constant _ERC165_INTERFACE_ID = 0x01ffc9a7; // solium-disable-line uppercase

    /// @dev Constructor initializes the vault with an owner address and spend limit. It also sets up the controllable and tokenWhitelist contracts with the right name registered in ENS.
    /// @param _owner_ is the owner account of the wallet contract.
    /// @param _transferable_ indicates whether the contract ownership can be transferred.
    /// @param _tokenWhitelistNameHash_ is the ENS name hash of the Token whitelist.
    /// @param _controllerNameHash_ is the ENS name hash of the controller.
    /// @param _spendLimit_ is the initial spend limit.
    constructor(address _owner_, bool _transferable_, bytes32 _tokenWhitelistNameHash_, bytes32 _controllerNameHash_, uint _spendLimit_) SpendLimit(_spendLimit_) Ownable(_owner_, _transferable_) Controllable(_controllerNameHash_) TokenWhitelistable(_tokenWhitelistNameHash_) public {}

    /// @dev Checks if the value is not zero.
    modifier isNotZero(uint _value) {
        require(_value != 0, "provided value cannot be zero");
        _;
    }

    /// @dev Ether can be deposited from any source, so this contract must be payable by anyone.
    function() external payable {
        require(msg.data.length == 0, "msg data needs to be empty");
        emit Received(msg.sender, msg.value);
    }

    /// @dev Returns the amount of an asset owned by the contract.
    /// @param _asset address of an ERC20 token or 0x0 for ether.
    /// @return balance associated with the wallet address in wei.
    function balance(address _asset) external view returns (uint) {
        if (_asset != address(0)) {
            return ERC20(_asset).balanceOf(this);
        } else {
            return address(this).balance;
        }
    }

    /// @dev Transfers the specified asset to the recipient's address.
    /// @param _to is the recipient's address.
    /// @param _asset is the address of an ERC20 token or 0x0 for ether.
    /// @param _amount is the amount of assets to be transferred in base units.
    function transfer(address _to, address _asset, uint _amount) external onlyOwner isNotZero(_amount) {
        // Checks if the _to address is not the zero-address
        require(_to != address(0), "_to address cannot be set to 0x0");

        // If address is not whitelisted, take daily limit into account.
        if (!whitelistMap[_to]) {
            //initialize ether value in case the asset is ETH
            uint etherValue = _amount;
            // Convert token amount to ether value if asset is an ERC20 token.
            if (_asset != address(0)) {
                etherValue = convertToEther(_asset, _amount);
            }
            // Check against the daily spent limit and update accordingly
            // Check against the daily spent limit and update accordingly, require that the value is under remaining limit.
            _enforceLimit(_spendLimit, etherValue);
        }
        // Transfer token or ether based on the provided address.
        if (_asset != address(0)) {
            require(ERC20(_asset).transfer(_to, _amount), "ERC20 token transfer was unsuccessful");
        } else {
            _to.transfer(_amount);
        }
        // Emit the transfer event.
        emit Transferred(_to, _asset, _amount);
    }

    /// @dev Checks for interface support based on ERC165.
    function supportsInterface(bytes4 interfaceID) external view returns (bool) {
        return interfaceID == _ERC165_INTERFACE_ID;
    }

    /// @dev Convert ERC20 token amount to the corresponding ether amount.
    /// @param _token ERC20 token contract address.
    /// @param _amount amount of token in base units.
    function convertToEther(address _token, uint _amount) public view returns (uint) {
        // Store the token in memory to save map entry lookup gas.
        (,uint256 magnitude, uint256 rate, bool available, , , ) = _getTokenInfo(_token);
        // If the token exists require that its rate is not zero.
        if (available) {
            require(rate != 0, "token rate is 0");
            // Safely convert the token amount to ether based on the exchange rate.
            // SWC-101-Integer Overflow and Underflow: L562
            return _amount.mul(rate).div(magnitude);
        }
        return 0;
    }
}


//// @title Asset wallet with extra security features, gas top up management and card integration.
contract Wallet is ENSResolvable, Vault, GasTopUpLimit, LoadLimit {

    event ToppedUpGas(address _sender, address _owner, uint _amount);
    event LoadedTokenCard(address _asset, uint _amount);
    event ExecutedTransaction(address _destination, uint _value, bytes _data);

    uint constant private _DEFAULT_MAX_STABLECOIN_LOAD_LIMIT = 10000; //10,000 USD

    /// @dev Is the registered ENS node identifying the licence contract.
    bytes32 private _licenceNode;

    /// @dev these are needed to allow for the executeTransaction method
    uint32 private constant _TRANSFER= 0xa9059cbb;
    uint32 private constant _APPROVE = 0x095ea7b3;

    /// @dev Constructor initializes the wallet top up limit and the vault contract.
    /// @param _owner_ is the owner account of the wallet contract.
    /// @param _transferable_ indicates whether the contract ownership can be transferred.
    /// @param _ens_ is the address of the ENS registry.
    /// @param _tokenWhitelistNameHash_ is the ENS name hash of the Token whitelist.
    /// @param _controllerNameHash_ is the ENS name hash of the Controller contract.
    /// @param _licenceNameHash_ is the ENS name hash of the Licence contract.
    /// @param _spendLimit_ is the initial spend limit.
    constructor(address _owner_, bool _transferable_, address _ens_, bytes32 _tokenWhitelistNameHash_, bytes32 _controllerNameHash_, bytes32 _licenceNameHash_, uint _spendLimit_) ENSResolvable(_ens_) Vault(_owner_, _transferable_, _tokenWhitelistNameHash_, _controllerNameHash_, _spendLimit_) public {
        // Get the stablecoin's magnitude.
        ( ,uint256 stablecoinMagnitude, , , , , ) = _getStablecoinInfo();
        require(stablecoinMagnitude > 0, "stablecoin not set");
        _initializeLoadLimit(_DEFAULT_MAX_STABLECOIN_LOAD_LIMIT * stablecoinMagnitude);
        _licenceNode = _licenceNameHash_;
    }

    /// @dev Refill owner's gas balance, revert if the transaction amount is too large
    /// @param _amount is the amount of ether to transfer to the owner account in wei.
    function topUpGas(uint _amount) external isNotZero(_amount) onlyOwnerOrController {
        // Check against the daily spent limit and update accordingly, require that the value is under remaining limit.
        _enforceLimit(_gasTopUpLimit, _amount);
        // Then perform the transfer
        owner().transfer(_amount);
        // Emit the gas top up event.
        emit ToppedUpGas(msg.sender, owner(), _amount);
    }

    /// @dev Load a token card with the specified asset amount.
    /// @dev the amount send should be inclusive of the percent licence.
    /// @param _asset is the address of an ERC20 token or 0x0 for ether.
    /// @param _amount is the amount of assets to be transferred in base units.
    function loadTokenCard(address _asset, uint _amount) external payable onlyOwner {
        //check if token is allowed to be used for loading the card
        require(_isTokenLoadable(_asset), "token not loadable");
        // Convert token amount to stablecoin value.
        uint stablecoinValue = convertToStablecoin(_asset, _amount);
        // Check against the daily spent limit and update accordingly, require that the value is under remaining limit.
        _enforceLimit(_loadLimit, stablecoinValue);
        // Get the TKN licenceAddress from ENS
        address licenceAddress = _ensResolve(_licenceNode);
        if (_asset != address(0)) {
            require(ERC20(_asset).approve(licenceAddress, _amount), "ERC20 token approval was unsuccessful");
            ILicence(licenceAddress).load(_asset, _amount);
        } else {
            ILicence(licenceAddress).load.value(_amount)(_asset, _amount);
        }

        emit LoadedTokenCard(_asset, _amount);

    }

    /// @dev This function allows for the owner to send transaction from the Wallet to arbitrary addresses
    /// @param _destination address of the transaction
    /// @param _value ETH amount in wei
    /// @param _data transaction payload binary
    function executeTransaction(address _destination, uint _value, bytes _data) external onlyOwner {
        // Check if there exists at least a method signature in the transaction payload
        if (_data.length >= 4) {
            // Get method signature
            uint32 signature = _bytesToUint32(_data, 0);

            // Check if method is either ERC20 transfer or approve
            if (signature == _TRANSFER || signature == _APPROVE) {
                require(_data.length >= 4 + 32 + 32, "invalid transfer / approve transaction data");
                uint amount = _sliceUint(_data, 4 + 32);
                // The "toOrSpender" is the '_to' address for a ERC20 transfer or the '_spender; in ERC20 approve
                // + 12 because address 20 bytes and this is padded to 32
                address toOrSpender = _bytesToAddress(_data, 4 + 12);

                // Check if the toOrSpender is in the whitelist
                if (!whitelistMap[toOrSpender]) {
                    // If the address (of the token contract, e.g) is not in the TokenWhitelist used by
                    // the convert method, then etherValue will be zero
                    uint etherValue = convertToEther(_destination, amount);
                    _enforceLimit(_spendLimit, etherValue);
                }
            }
        }

        // If value is send across as a part of this executeTransaction, this will be sent to any payable
        // destination. As a result enforceLimit if destination is not whitelisted.
        if (!whitelistMap[_destination]) {
            _enforceLimit(_spendLimit, _value);
        }

        require(_externalCall(_destination, _value, _data.length, _data), "executing transaction failed");

        emit ExecutedTransaction(_destination, _value, _data);
    }

    /// @return licence contract node registered in ENS.
    function licenceNode() external view returns (bytes32) {
        return _licenceNode;
    }

    /// @dev Convert ether or ERC20 token amount to the corresponding stablecoin amount.
    /// @param _token ERC20 token contract address.
    /// @param _amount amount of token in base units.
    function convertToStablecoin(address _token, uint _amount) public view returns (uint) {
        //avoid the unnecessary calculations if the token to be loaded is the stablecoin itself
        if (_token == _stablecoin()) {
            return _amount;
        }
        //0x0 represents ether
        if (_token != address(0)) {
            //convert to eth first, same as convertToEther()
            // Store the token in memory to save map entry lookup gas.
            (,uint256 magnitude, uint256 rate, bool available, , , ) = _getTokenInfo(_token);
            // require that token both exists in the whitelist and its rate is not zero.
            require(available, "token is not available");
            require(rate != 0, "token rate is 0");
            // Safely convert the token amount to ether based on the exchange rate.
            _amount = _amount.mul(rate).div(magnitude);
        }
        //_amount now is in ether
        // Get the stablecoin's magnitude and its current rate.
        ( ,uint256 stablecoinMagnitude, uint256 stablecoinRate, bool stablecoinAvailable, , , ) = _getStablecoinInfo();
            // Check if the stablecoin rate is set.
        require(stablecoinAvailable, "token is not available");
        require(stablecoinRate != 0, "stablecoin rate is 0");
        // Safely convert the token amount to stablecoin based on its exchange rate and the stablecoin exchange rate.
        // SWC-101-Integer Overflow and Underflow: L707
        return _amount.mul(stablecoinMagnitude).div(stablecoinRate);
    }

    /// @dev This function is taken from the Gnosis MultisigWallet: https://github.com/gnosis/MultiSigWallet/
    /// @dev License: https://github.com/gnosis/MultiSigWallet/blob/master/LICENSE
    /// @dev thanks :)
    /// @dev This calls proxies arbitrary transactions to addresses
    /// @param _destination address of the transaction
    /// @param _value ETH amount in wei
    /// @param _dataLength length of the transaction data
    /// @param _data transaction payload binary
    // call has been separated into its own function in order to take advantage
    // of the Solidity's code generator to produce a loop that copies tx.data into memory.
    function _externalCall(address _destination, uint _value, uint _dataLength, bytes _data) private returns (bool) {
        bool result;
        assembly {
            let x := mload(0x40)   // "Allocate" memory for output (0x40 is where "free memory" pointer is stored by convention)
            let d := add(_data, 32) // First 32 bytes are the padded length of data, so exclude that
            result := call(
                sub(gas, 34710),   // 34710 is the value that solidity is currently emitting
                                   // It includes callGas (700) + callVeryLow (3, to pay for SUB) + callValueTransferGas (9000) +
                                   // callNewAccountGas (25000, in case the destination address does not exist and needs creating)
                _destination,
                _value,
                d,
                _dataLength,        // Size of the input (in bytes) - this is what fixes the padding problem
                x,
                0                  // Output is ignored, therefore the output size is zero
            )
        }

        return result;
    }

    /// @dev This function converts to an address
    /// @param _bts bytes
    /// @param _from start position
    function _bytesToAddress(bytes _bts, uint _from) private pure returns (address) {
        require(_bts.length >= _from + 20, "slicing out of range");

        uint160 m = 0;
        uint160 b = 0;

        for (uint8 i = 0; i < 20; i++) {
            m *= 256;
            b = uint160 (_bts[_from + i]);
            m += (b);
        }

        return address(m);
    }

    /// @dev This function slicing bytes into uint32
    /// @param _bts some bytes
    /// @param _from  a start position
    function _bytesToUint32(bytes _bts, uint _from) private pure returns (uint32) {
        require(_bts.length >= _from + 4, "slicing out of range");

        uint32 m = 0;
        uint32 b = 0;

        for (uint8 i = 0; i < 4; i++) {
            m *= 256;
            b = uint32 (_bts[_from + i]);
            m += (b);
        }

        return m;
    }

    /// @dev This function slices a uint
    /// @param _bts some bytes
    /// @param _from  a start position
    // credit to https://ethereum.stackexchange.com/questions/51229/how-to-convert-bytes-to-uint-in-solidity
    // and Nick Johnson https://ethereum.stackexchange.com/questions/4170/how-to-convert-a-uint-to-bytes-in-solidity/4177#4177
    function _sliceUint(bytes _bts, uint _from) private pure returns (uint) {
        require(_bts.length >= _from + 32, "slicing out of range");

        uint x;
        assembly {
            x := mload(add(_bts, add(0x20, _from)))
        }

        return x;
    }

}
