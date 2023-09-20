// SWC-102-Outdated Compiler Version: L2
pragma solidity ^0.4.19;

/// Contracts implementing this interface are compatible with
/// GolemNetworkTokenBatching's transferAndCall method
contract ReceivingContract {
    function onTokenReceived(address _from, uint _value, bytes _data) public;
}
