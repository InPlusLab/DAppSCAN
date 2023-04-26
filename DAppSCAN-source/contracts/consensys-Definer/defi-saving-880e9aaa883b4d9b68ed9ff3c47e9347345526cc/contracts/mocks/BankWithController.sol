pragma solidity 0.5.14;

import "../Bank.sol";
import { IController } from "../compound/ICompound.sol";

contract BankWithController is Bank {

    address comptroller;

    function initialize(
        GlobalConfig _globalConfig,
        address _comptroller
    ) external initializer {
        super.initialize(_globalConfig); // expected 3 passed 5 args
        comptroller = _comptroller;
    }

    function getBlockNumber() private view returns (uint) {
        return IController(comptroller).getBlockNumber();
    }
}