pragma solidity ^0.4.18;

import "zeppelin-solidity/contracts/token/ERC20/TokenVesting.sol";

contract TokenVestingMock is TokenVesting {
    function TokenVestingMock(address _beneficiary, uint256 _start, uint256 _cliff, uint256 _duration, bool _revocable) public TokenVesting(_beneficiary, _start, _cliff, _duration, _revocable) {
        

    }
}