// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";

abstract contract AvatarArtContext is Context {
    function _now() internal view returns(uint){
        return block.timestamp;
    }
}