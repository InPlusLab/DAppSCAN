pragma solidity ^0.4.24;

import "../CErc20Interface.sol";

contract MockCErc20 is CErc20Interface {

    constructor(address _underlying) public {
        underlying = _underlying;
    }

    function mint(uint mintAmount) external returns (uint) {
        return 0;
    }
}
