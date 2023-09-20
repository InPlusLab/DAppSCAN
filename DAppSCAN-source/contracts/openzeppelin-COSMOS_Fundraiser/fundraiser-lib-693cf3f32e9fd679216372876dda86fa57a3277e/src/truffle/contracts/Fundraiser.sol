// SWC-101-Integer Overflow and Underflow: L9-L133
// SWC-102-Outdated Compiler Version: L9-L133

//! Fundraiser contract. Just records who sent what.
//! By Parity Technologies, 2017.
//! Released under the Apache Licence 2.
//! Modified by the Interchain Foundation.

pragma solidity ^0.4.7;

/// Will accept Ether "contributions" and record each both as a log and in a
/// queryable record.
contract Fundraiser {


    // How much is enough?
    uint public constant dust = 1 finney; // XXX: change for production


    // Special addresses: 
    //  administrator can halt/unhalt/kill/adjustRate;
    //  treasury receives all the funds
    address public admin;
    address public treasury;

    // Begin and end block for the fundraising period
    uint public beginBlock;
    uint public endBlock;

    // Number of atoms per ether.
    // Correspondingly, number of 10^(-18)atoms per wei
    uint public atomRate; 

    // Are contributions abnormally halted?
    bool public isHalted = false;

    // The record maps cosmos addresses to the product of their donation amount and the current atomRate.
    // The returns maps cosmos addresses to their ethereum return addresses.
    // NOTE: We could use a struct instead but would currently
    // save only one SSLOAD/SSTORE and at the expense
    // of relying on solidity type packing :o !
    mapping (address => uint) public record;
    mapping (address => address) public returnAddresses;

    // The total amount of ether raised
    uint public totalEther = 0;
    // The total amount of atoms suggested for allocation
    uint public totalAtom = 0;

    /// Constructor. `_admin` has the ability to pause the
    /// contribution period and, eventually, kill this contract. `_treasury`
    /// receives all funds. `_beginBlock` and `_endBlock` define the begin and
    /// end of the period. `_atomRate` is the ratio of atoms to ether.
    function Fundraiser(address _admin, address _treasury, uint _beginBlock, uint _endBlock, uint _atomRate) {
        admin = _admin;
        treasury = _treasury;
        beginBlock = _beginBlock;
        endBlock = _endBlock;
	atomRate = _atomRate;
    }

    // Can only be called by _admin.
    modifier only_admin { if (msg.sender != admin) throw; _; }
    // Can only be called by prior to the period.
    modifier only_before_period { if (block.number >= beginBlock) throw; _; }
    // Can only be called during the period when not halted.
    modifier only_during_period { if (block.number < beginBlock || block.number >= endBlock || isHalted) throw; _; }
    // Can only be called during the period when halted.
    modifier only_during_halted_period { if (block.number < beginBlock || block.number >= endBlock || !isHalted) throw; _; }
    // Can only be called after the period.
    modifier only_after_period { if (block.number < endBlock) throw; _; }
    // The value of the message must be sufficiently large to not be considered dust.
    modifier is_not_dust { if (msg.value < dust) throw; _; }

    /// Some contribution `amount` received from `recipient` at rate of `currentRate`.
    event Received(address indexed recipient, uint amount, uint currentRate);
    /// Period halted abnormally.
    event Halted();
    /// Period restarted after abnormal halt.
    event Unhalted();

    /// Fallback function throws. Successful donation requires arguments
    function() {
	throw;
    }

    /// Receive a contribution for a donor cosmos address.
    /// Also store returnAddress just-in-case.
    function donate(address _donor, address _returnAddress, bytes32 checksum) payable only_during_period is_not_dust {
	// checksum is the sha3 of the xor of the bytes32 versions of the cosmos address and the return address
	if (!(sha3(bytes32(_donor)^bytes32(_returnAddress)) == checksum)) throw;

	// forward the funds to the treasurer
        // SWC-107-Reentrancy: L92
        if (!treasury.call.value(msg.value)()) throw;

	// calculate the number of atoms at the current rate
	var atoms = msg.value * atomRate;

	// update the donor details
        record[_donor] += atoms;
        returnAddresses[_donor] = _returnAddress; // XXX: overwrites

	// update the totals
        totalEther += msg.value;
	totalAtom += atoms;

        Received(_donor, msg.value, atomRate);
    }

    /// Adjust the atomRate
    /// NOTE: Should we allow rate to adjust before the period starts?
    function adjustRate(uint newRate) only_admin only_during_period {
	atomRate = newRate;
    }

    /// Halt the contribution period. Any attempt at contributing will fail.
    function halt() only_admin only_during_period {
        isHalted = true;
        Halted();
    }

    /// Unhalt the contribution period.
    function unhalt() only_admin only_during_halted_period {
        isHalted = false;
        Unhalted();
    }

    /// Kill this contract.
    function kill() only_admin only_after_period {
        suicide(treasury);
    }
}
