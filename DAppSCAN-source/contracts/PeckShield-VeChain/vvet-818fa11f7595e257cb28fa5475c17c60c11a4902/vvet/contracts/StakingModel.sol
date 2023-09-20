// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "../interfaces/IStakingModel.sol";

// StakingModel tracks the in-and-out of user's VET
// And updates user's vtho balance accordingly.

// It can also track the in-and-out of user's VTHO.

// Data structure concern:
// uint48 - enough to store 30,000+ years.
// uint104 - enough to store whole vet on VeChain.
// uint104 - enough to store vtho for 100+ years.

contract StakingModel is IStakingModel {

    struct User {
        uint104 balance; // vet in wei
        uint104 energy;  // vtho in wei
        uint48 lastUpdatedTime;
    }

    mapping(address => User) private users;

    modifier restrict(uint256 amount) {
        require(amount <= type(uint104).max, "value should <= type(uint104).max");
        _;
    }

    function addVET(address addr, uint256 amount) restrict(amount) internal {
        _update(addr);
        users[addr].balance += uint104(amount);
    }

// SWC-135-Code With No Effects: L37 - L41
    function removeVET(address addr, uint256 amount) restrict(amount) internal {
        _update(addr);
        require(users[addr].balance >= uint104(amount), "insuffcient vet");
        users[addr].balance -= uint104(amount);
    }

    function vetBalance(address addr) public override view returns (uint256 amount) {
        return users[addr].balance;
    }

    function addVTHO(address addr, uint256 amount) restrict(amount) internal {
        _update(addr);
        users[addr].energy += uint104(amount);
    }

    function removeVTHO(address addr, uint256 amount) restrict(amount) internal {
        _update(addr);
        require(users[addr].energy >= uint104(amount), "insuffcient vtho");
        users[addr].energy -= uint104(amount);
    }

    function vthoBalance(address addr) public override view returns (uint256 amount) {
        User memory user = users[addr];
        if (user.lastUpdatedTime == 0) {
            return 0;
        }
        return user.energy + calculateVTHO(user.lastUpdatedTime, uint48(block.timestamp), user.balance);
    }

    // Sync the vtho balance that the address has up till current block (timestamp)
    function _update(address addr) internal {
        uint48 currentTime = uint48(block.timestamp);
        if (users[addr].lastUpdatedTime > 0) {
            assert(users[addr].lastUpdatedTime <= currentTime);
            users[addr].energy += calculateVTHO(
                users[addr].lastUpdatedTime,
                currentTime,
                users[addr].balance
            );
        }

        users[addr].lastUpdatedTime = currentTime;
    }

    // Calculate vtho generated between time t1 and t2
    // @param t1 Time in seconds
    // @param t2 Time in seconds
    // @param vetAmount VET in wei
    // @return vtho generated in wei
    // SWC-101-Integer Overflow and Underflow: L92
    function calculateVTHO(
        uint48 t1,
        uint48 t2,
        uint104 vetAmount
    ) public pure returns (uint104 vtho) {
        require(t1 <= t2, "t1 should be <= t2");

        return ((vetAmount * 5) / (10**9)) * (t2 - t1);
    }
}
