pragma solidity ^0.4.18;

import "../token/TokenHolder.sol";
import "../token/IERC20Token.sol";

//can transfer mass tokens 
contract MassTransfer is TokenHolder {
    IERC20Token token;
    mapping(address=>bool) public allowedUsers;
    
    function MassTransfer(IERC20Token _token, address[] users) {
        token = _token;
        allowedUsers[msg.sender] = true;
        for(uint i = 0; i < users.length; ++i) {
            allowedUsers[users[i]] = true;
        }
    }

    function changeUser(address user, bool state) public ownerOnly {
        allowedUsers[user] = state;
    }

    function transferEqual(uint256 amount, address[] receivers) public {
        require(allowedUsers[msg.sender]);

        for(uint256 i = 0; i < receivers.length; ++i) {
            token.transfer(receivers[i], amount);
        }
    }

    function transfer(address[] receivers, uint256[] amounts) public ownerOnly {
        require(allowedUsers[msg.sender]);
        
        for(uint256 i = 0; i < receivers.length; ++i) {
            token.transfer(receivers[i], amounts[i]);
        }
    }
}