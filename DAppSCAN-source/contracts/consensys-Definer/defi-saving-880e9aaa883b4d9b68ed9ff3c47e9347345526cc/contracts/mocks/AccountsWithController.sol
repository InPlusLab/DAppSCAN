pragma solidity 0.5.14;

import "../Accounts.sol";
import { IController } from "../compound/ICompound.sol";

contract AccountsWithController is Accounts {

    address comptroller;

    function initialize(
        GlobalConfig _globalConfig,
        address _comptroller
    ) public initializer {
        super.initialize(_globalConfig); // expected 3 passed 5 args
        comptroller = _comptroller;
    }

    function getBlockNumber() private view returns (uint) {
        return IController(comptroller).getBlockNumber();
    }
}