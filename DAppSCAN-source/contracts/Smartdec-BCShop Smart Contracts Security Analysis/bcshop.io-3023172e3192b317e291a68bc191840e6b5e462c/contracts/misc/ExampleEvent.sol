pragma solidity ^0.4.10;

contract ExampleEvent {

    uint256 public intVar;
    bool public boolVar;
    string public stringVar;
    bytes32 public bytesVar;
    address public addrVar;

    event TestEvent(address indexed _addrVar, uint256 indexed _intVar, bool _boolVar, string _stringVar, bytes32 _bytesVar);

    function ExampleEvent(address _addrVar, uint256 _intVar, bool _boolVar, string _stringVar, bytes32 _bytesVar) public {
        intVar = _intVar;
        addrVar = _addrVar;
        boolVar = _boolVar;
        stringVar = _stringVar;
        bytesVar = _bytesVar;
    }

    function set(address _addrVar, uint256 _intVar, bool _boolVar, string _stringVar, bytes32 _bytesVar) public {
        addrVar = _addrVar;
        intVar = _intVar;
        boolVar = _boolVar;
        stringVar = _stringVar;
        bytesVar = _bytesVar;
    }
        
    function emitEvent() public {
        TestEvent(addrVar, intVar, boolVar, stringVar, bytesVar);
    }
}