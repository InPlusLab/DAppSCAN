/*

    Copyright 2020 DODO ZOO.
    SPDX-License-Identifier: Apache-2.0

*/

pragma solidity 0.6.9;

import {Ownable} from "../lib/Ownable.sol";

interface IQuota {
    function getUserQuota(address user) external view returns (int);
}

contract UserQuota is Ownable, IQuota {

    mapping(address => uint256) public userQuota;
    uint256 constant quota = 375 * 10**6; //For example 375u on eth

    function setUserQuota(address[] memory users) external onlyOwner {
        for(uint256 i = 0; i< users.length; i++) {
            require(users[i] != address(0), "USER_INVALID");
            userQuota[users[i]] = quota;
        }
    }

    function getUserQuota(address user) override external view returns (int) {
        return int(userQuota[user]);
    }
}
