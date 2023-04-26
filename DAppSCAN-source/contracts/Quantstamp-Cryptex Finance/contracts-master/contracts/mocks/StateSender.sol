// SPDX-License-Identifier: MIT
pragma solidity 0.7.5;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

interface IStateReceiver {
    function onStateReceive(uint256 stateId, bytes calldata data) external;
}

contract StateSender is Ownable {
    using SafeMath for uint256;

    uint256 public counter;
    mapping(address => address) public registrations;

    event NewRegistration(
        address indexed user,
        address indexed sender,
        address indexed receiver
    );
    event RegistrationUpdated(
        address indexed user,
        address indexed sender,
        address indexed receiver
    );
    event StateSynced(
        uint256 indexed id,
        address indexed contractAddress,
        bytes data
    );

    modifier onlyRegistered(address receiver) {
        require(registrations[receiver] == msg.sender, "Invalid sender");
        _;
    }

    function syncState(address receiver, bytes calldata data)
        external
        onlyRegistered(receiver)
    {
        counter = counter.add(1);
//			The call below is mocked to make a direct call to an L2 contract
        IStateReceiver(receiver).onStateReceive(counter, data);
    }

    // register new contract for state sync
    function register(address sender, address receiver) public {
        require(
            msg.sender == owner() || registrations[receiver] == msg.sender,
            "StateSender.register: Not authorized to register"
        );
        if (registrations[receiver] == address(0)) {
            emit NewRegistration(msg.sender, sender, receiver);
        } else {
            emit RegistrationUpdated(msg.sender, sender, receiver);
        }
				registrations[receiver] = sender;
    }
}
