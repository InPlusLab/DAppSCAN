// Copyright 2018 Golem Factory
// Licensed under the GNU General Public License v3. See the LICENSE file.

// SWC-102-Outdated Compiler Version: L5
pragma solidity ^0.4.19;

import "./open_zeppelin/StandardToken.sol";

/// The Gate is a contract with unique address to allow a token holder
/// (called "User") to transfer tokens from original Token to the Proxy.
///
/// The Gate does not know who its User is. The User-Gate relationship is
/// managed by the Proxy.
contract Gate {
    ERC20Basic private TOKEN;
    address private PROXY;

    /// Gates are to be created by the TokenProxy.
    function Gate(ERC20Basic _token, address _proxy) public {
        TOKEN = _token;
        PROXY = _proxy;
    }

    /// Transfer requested amount of tokens from Gate to Proxy address.
    /// Only the Proxy can request this and should request transfer of all
    /// tokens.
    function transferToProxy(uint256 _value) public {
        require(msg.sender == PROXY);

        require(TOKEN.transfer(PROXY, _value));
    }
}


/// The Proxy for existing tokens implementing a subset of ERC20 interface.
///
/// This contract creates a token Proxy contract to extend the original Token
/// contract interface. The Proxy requires only transfer() and balanceOf()
/// methods from ERC20 to be implemented in the original Token contract.
///
/// All migrated tokens are in Proxy's account on the Token side and distributed
/// among Users on the Proxy side.
///
/// For an user to migrate some amount of ones tokens from Token to Proxy
/// the procedure is as follows.
///
/// 1. Create an individual Gate for migration. The Gate address will be
///    reported with the GateOpened event and accessible by getGateAddress().
/// 2. Transfer tokens to be migrated to the Gate address.
/// 3. Execute Proxy.transferFromGate() to finalize the migration.
///
/// In the step 3 the User's tokens are going to be moved from the Gate to
/// the User's balance in the Proxy.
contract TokenProxy is StandardToken {

    ERC20Basic public TOKEN;

    mapping(address => address) private gates;


    event GateOpened(address indexed gate, address indexed user);

    event Minted(address indexed to, uint256 amount);

    event Burned(address indexed from, uint256 amount);

    function TokenProxy(ERC20Basic _token) public {
        TOKEN = _token;
    }

    function getGateAddress(address _user) external view returns (address) {
        return gates[_user];
    }

    /// Create a new migration Gate for the User.
    function openGate() external {
        address user = msg.sender;

        // Do not allow creating more than one Gate per User.
        require(gates[user] == 0);

        // Create new Gate.
        address gate = new Gate(TOKEN, this);

        // Remember User - Gate relationship.
        gates[user] = gate;

        GateOpened(gate, user);
    }

    function transferFromGate() external {
        address user = msg.sender;

        address gate = gates[user];

        // Make sure the User's Gate exists.
        require(gate != 0);

        uint256 value = TOKEN.balanceOf(gate);

        Gate(gate).transferToProxy(value);

        // Handle the information about the amount of migrated tokens.
        // This is a trusted information becase it comes from the Gate.
        totalSupply_ += value;
        balances[user] += value;

        Minted(user, value);
    }

    function withdraw(uint256 _value) external {
      withdrawTo(_value, msg.sender);
    }

    function withdrawTo(uint256 _value, address _destination) public {
        address user = msg.sender;
        uint256 balance = balances[user];
        require(_value <= balance);

        balances[user] = (balance - _value);
        totalSupply_ -= _value;

        TOKEN.transfer(_destination, _value);

        Burned(user, _value);
    }
}
