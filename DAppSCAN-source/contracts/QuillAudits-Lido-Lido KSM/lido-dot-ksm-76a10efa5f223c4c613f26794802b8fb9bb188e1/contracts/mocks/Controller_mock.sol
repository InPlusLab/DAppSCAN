// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;


contract Controller_mock {
    event Bond (
        address caller,
        bytes32 stash,
        bytes32 controller,
        uint256 amount
    );

    event BondExtra (
        address caller,
        bytes32 stash,
        uint256 amount
    );

    event Unbond (
        address caller,
        bytes32 stash,
        uint256 amount
    );

    event Rebond (
        address caller,
        bytes32 stash,
        uint256 amount
    );

    event Withdraw (
        address caller,
        bytes32 stash
    );

    event Nominate (
        address caller,
        bytes32 stash,
        bytes32[] validators
    );

    event Chill (
        address caller,
        bytes32 stash
    );

    event TransferToRelaychain (
        address from,
        bytes32 to,
        uint256 amount
    );

    event TransferToParachain (
        bytes32 from,
        address to,
        uint256 amount
    );

    mapping(address => bytes32) public senderToAccount;


    function newSubAccount(uint16 index, bytes32 accountId, address paraAddress) external {
        senderToAccount[paraAddress] = accountId;
    }

    function getSenderAccount() internal returns(bytes32) {
        return senderToAccount[msg.sender];
    }

    function nominate(bytes32[] calldata validators) external {
        emit Nominate(msg.sender, getSenderAccount(), validators);
    }

    function bond(bytes32 controller, uint256 amount) external {
        emit Bond(msg.sender, getSenderAccount(), controller, amount);
    }

    function bondExtra(uint256 amount) external {
        emit BondExtra(msg.sender, getSenderAccount(), amount);
    }

    function unbond(uint256 amount) external {
        emit Unbond(msg.sender, getSenderAccount(), amount);
    }

    function withdrawUnbonded() external {
        emit Withdraw(msg.sender, getSenderAccount());
    }

    function rebond(uint256 amount) external {
        emit Rebond(msg.sender, getSenderAccount(), amount);
    }

    function chill() external {
        emit Chill(msg.sender, getSenderAccount());
    }

    function transferToParachain(uint256 amount) external {
        emit TransferToParachain(getSenderAccount(), msg.sender, amount);
    }

    function transferToRelaychain(uint256 amount) external {
        emit TransferToRelaychain(msg.sender, getSenderAccount(), amount);
    }
}
