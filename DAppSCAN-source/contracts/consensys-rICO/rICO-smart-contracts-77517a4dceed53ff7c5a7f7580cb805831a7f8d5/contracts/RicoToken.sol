pragma solidity ^0.5.0;

import "./zeppelin/token/ERC777/ERC777.sol";

interface ReversibleICO {
    function getParticipantReservedTokens(address) external view returns (uint256);
}

contract RicoToken is ERC777 {

    ReversibleICO public rICO;
    address public manager;
    bool public frozen; // default: false
    bool public initialized; // default: false

    constructor(
        uint256 _initialSupply,
        address[] memory _defaultOperators
    )
        ERC777("LYXeToken", "LYXe", _defaultOperators)
        public
    {
        _mint(msg.sender, msg.sender, _initialSupply, "", "");
        manager = msg.sender;
        frozen = true;
    }

    // since rico affects balances, changing the rico address
    // once setup should not be possible.
    function setup(address _rICO)
        public
        requireNotInitialized
        onlyManager
    {
        rICO = ReversibleICO(_rICO);
        frozen = false;
        initialized = true;
    }

    // new method for updating the rico address in case of rICO address update


    function changeManager(address _newManager) public onlyManager {
        manager = _newManager;
    }

    function setFrozen(bool _status) public onlyManager {
        frozen = _status;
    }

    function getLockedBalance(address _owner) public view returns(uint) {
        return rICO.getParticipantReservedTokens(_owner);
    }

    function getUnlockedBalance(address _owner) public view returns(uint) {
        uint256 balance = balanceOf(_owner);
        uint256 locked = rICO.getParticipantReservedTokens(_owner);
        if(balance > 0 && locked > 0 && balance >= locked) {
            return balance.sub(locked);
        }
        return balance;
    }

    // We should override burn as well. So users can't burn locked amounts
    function _burn(
        address _operator,
        address _from,
        uint256 _amount,
        bytes memory _data,
        bytes memory _operatorData
    )
        internal
        requireNotFrozen
    {
        require(_amount <= getUnlockedBalance(_from), "getUnlockedBalance: Insufficient funds");
        ERC777._burn(_operator, _from, _amount, _data, _operatorData);
    }

    // We need to override send / transfer methods in order to only allow transfers within RICO unlocked calculations
    // ricoAddress can receive any amount for withdraw functionality
    function _move(
        address _operator,
        address _from,
        address _to,
        uint256 _amount,
        bytes memory _userData,
        bytes memory _operatorData
    )
        internal
        requireNotFrozen
        requireInitialized
    {

        if(_to == address(rICO)) {
            // full balance can be sent back to rico
            require(_amount <= balanceOf(_from), "getUnlockedBalance: Insufficient funds");
        } else {
            // for every other address limit to unlocked balance
            require(_amount <= getUnlockedBalance(_from), "getUnlockedBalance: Insufficient funds");
        }

        ERC777._move(_operator, _from, _to, _amount, _userData, _operatorData);
    }

    modifier onlyManager() {
        require(msg.sender == manager, "onlyManager: Only manager can call this method");
        _;
    }

    modifier requireInitialized() {
        require(initialized == true, "Contract must be initialized.");
        _;
    }

    modifier requireNotInitialized() {
        require(initialized == false, "Contract is already initialized.");
        _;
    }

    modifier requireNotFrozen() {
        require(frozen == false, "requireNotFrozen: Contract must not be frozen");
        _;
    }

}
