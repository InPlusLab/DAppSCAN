/*
 * Hubii Nahmii
 *
 * Compliant with the Hubii Nahmii specification v0.12.
 *
 * Copyright (C) 2017-2018 Hubii AS
 */

pragma solidity ^0.4.25;

import {Ownable} from "./Ownable.sol";

contract Migrations is Ownable {
    //
    // Variables
    // -----------------------------------------------------------------------------------------------------------------
    uint public last_completed_migration;

    //
    // Constructor
    // -----------------------------------------------------------------------------------------------------------------
    constructor() Ownable(msg.sender) public  {
    }

    //
    // Functions
    // -----------------------------------------------------------------------------------------------------------------
    function setCompleted(uint completed)
    public
    onlyDeployer
    {
        last_completed_migration = completed;
    }

    function upgrade(address newAddress)
    public
    onlyDeployer
    {
        Migrations upgraded = Migrations(newAddress);
        upgraded.setCompleted(last_completed_migration);
    }
}
