// Used for testing

pragma solidity ^0.5.12;

import "../VestingContractWithoutDelegation.sol";

// THIS IS A MOCK TEST CONTRACT - DO NOT AUDIT OR DEPLOY!
contract VestingContractWithoutDelegationFixedTime is VestingContractWithoutDelegation {

    uint256 time;

    constructor(IERC20 _token, uint256 _start, uint256 _end, uint256 _cliffDuration) VestingContractWithoutDelegation(_token, _start, _end, _cliffDuration) public {
        //
    }

    function fixTime(uint256 _time) external {
        time = _time;
    }

    function _getNow() internal view returns (uint256) {
        if (time != 0) {
            return time;
        }
        return block.timestamp;
    }

}
