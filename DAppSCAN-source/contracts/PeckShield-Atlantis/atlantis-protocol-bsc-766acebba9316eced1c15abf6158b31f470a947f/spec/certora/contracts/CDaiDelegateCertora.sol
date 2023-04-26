pragma solidity ^0.5.16;

import "../../../contracts/ADaiDelegate.sol";

contract ADaiDelegateCertora is ADaiDelegate {
    function getCashOf(address account) public view returns (uint) {
        return EIP20Interface(underlying).balanceOf(account);
    }
}
