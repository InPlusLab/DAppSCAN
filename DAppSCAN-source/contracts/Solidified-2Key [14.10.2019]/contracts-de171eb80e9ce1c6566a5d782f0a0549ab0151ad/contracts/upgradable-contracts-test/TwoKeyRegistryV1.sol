pragma solidity ^0.4.24;

import "../2key/singleton-contracts/TwoKeyRegistry.sol";

contract TwoKeyRegistryV1 is TwoKeyRegistry {
    function getMaintainers() public view returns (address[]) {
        address [] memory add = new address[](1);
        add[0] = 0x9aace881c7a80b596d38eaff66edbb5368d2f2c5;
        return add;
    }
}
