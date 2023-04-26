//SPDX-License-Identifier: MIT
pragma solidity >=0.6.11 <=0.6.12;

interface IAddressRegistry { }

contract BaseController {

    address public immutable manager;
    IAddressRegistry public immutable addressRegistry;

    constructor(address _manager, address _addressRegistry) public {
        require(_manager != address(0), "INVALID_ADDRESS");
        require(_addressRegistry != address(0), "INVALID_ADDRESS");

        manager = _manager;
        addressRegistry = IAddressRegistry(_addressRegistry);
    }

    modifier onlyManager() {
        require(address(this) == manager, "NOT_MANAGER_ADDRESS");
        _;
    }
}
