// Copyright 2018 Golem Factory
// Licensed under the GNU General Public License v3. See the LICENSE file.

// SWC-102-Outdated Compiler Version: L5
pragma solidity ^0.4.19;

import "./ReceivingContract.sol";
import "./TokenProxy.sol";


/// GolemNetworkTokenBatching can be treated as an upgraded GolemNetworkToken.
/// 1. It is fully ERC20 compliant (GNT is missing approve and transferFrom)
/// 2. It implements slightly modified ERC677 (transferAndCall method)
/// 3. It provides batchTransfer method - an optimized way of executing multiple transfers
///
/// On how to convert between GNT and GNTB see TokenProxy documentation.
contract GolemNetworkTokenBatching is TokenProxy {

    string public constant name = "Golem Network Token Batching";
    string public constant symbol = "GNTB";
    uint8 public constant decimals = 18;


    event BatchTransfer(address indexed from, address indexed to, uint256 value,
        uint64 closureTime);

    function GolemNetworkTokenBatching(ERC20Basic _gntToken) TokenProxy(_gntToken) public {
    }

    function batchTransfer(bytes32[] payments, uint64 closureTime) external {
        require(block.timestamp >= closureTime);

        uint balance = balances[msg.sender];

        for (uint i = 0; i < payments.length; ++i) {
            // A payment contains compressed data:
            // first 96 bits (12 bytes) is a value,
            // following 160 bits (20 bytes) is an address.
            bytes32 payment = payments[i];
            address addr = address(payment);
            uint v = uint(payment) / 2**160;
            require(v <= balance);
            balances[addr] += v;
            balance -= v;
            BatchTransfer(msg.sender, addr, v, closureTime);
        }

        balances[msg.sender] = balance;
    }

    function transferAndCall(address to, uint256 value, bytes data) external {
      // Transfer always returns true so no need to check return value
      transfer(to, value);

      // No need to check whether recipient is a contract, this method is
      // supposed to used only with contract recipients
      ReceivingContract(to).onTokenReceived(msg.sender, value, data);
    }
}
