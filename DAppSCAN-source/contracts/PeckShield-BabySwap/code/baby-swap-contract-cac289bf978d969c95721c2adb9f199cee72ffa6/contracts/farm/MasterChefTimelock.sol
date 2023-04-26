// SPDX-License-Identifier: MIT

pragma solidity >=0.6.12;

import '../core/Timelock.sol';
import './MasterChef.sol';
import '../interfaces/IBEP20.sol';
import 'hardhat/console.sol';

contract MasterChefTimelock is Timelock {

    mapping(address => bool) public existsPools;
    mapping(address => uint) public pidOfPool;
    MasterChef masterChef;

    struct SetMigratorData {
        address migrator;
        uint timestamp;
        bool exists;
    }
    SetMigratorData setMigratorData;

    struct TransferOwnershipData {
        address newOwner;
        uint timestamp;
        bool exists;
    }
    TransferOwnershipData transferOwnershipData;

    constructor(MasterChef masterChef_, address admin_, uint delay_) Timelock(admin_, delay_) {
        require(address(masterChef_) != address(0), "illegal masterChef address");
        require(admin_ != address(0), "illegal admin address");
        masterChef = masterChef_;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Timelock::cancelTransaction: Call must come from admin.?");
        _;
    }

    function addExistsPools(address pool, uint pid) external onlyAdmin {
        require(existsPools[pool] == false, "Timelock:: pair already exists");
        existsPools[pool] = true;
        pidOfPool[pool] = pid;
    }

    function delExistsPools(address pool) external onlyAdmin {
        require(existsPools[pool] == true, "Timelock:: pair not exists");
        delete existsPools[pool];
        delete pidOfPool[pool];
    }

    function updateMultiplier(uint256 multiplierNumber) external onlyAdmin {
        masterChef.updateMultiplier(multiplierNumber);
    }

    function add(uint256 _allocPoint, IBEP20 _lpToken, bool _withUpdate) external onlyAdmin {
        require(address(_lpToken) != address(0), "_lpToken address cannot be 0");
        require(existsPools[address(_lpToken)] == false, "Timelock:: pair already exists");
        uint pid = masterChef.poolLength();
        masterChef.add(_allocPoint, _lpToken, _withUpdate);
        pidOfPool[address(_lpToken)] = pid;
        existsPools[address(_lpToken)] = true;
    }

    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) external onlyAdmin {
        require(_pid < masterChef.poolLength(), 'Pool does not exist');
        masterChef.set(_pid, _allocPoint, _withUpdate);
    }

    function setMigrator(IMigratorChef _migrator) external onlyAdmin {
        require(address(_migrator) != address(0), "_migrator address cannot be 0");
        if (setMigratorData.exists) {
            cancelTransaction(address(masterChef), 0, "", abi.encodeWithSignature("setMigrator(address)", address(_migrator)), setMigratorData.timestamp);
        }
        queueTransaction(address(masterChef), 0, "", abi.encodeWithSignature("setMigrator(address)", address(_migrator)), block.timestamp + delay);
        setMigratorData.migrator = address(_migrator);
        setMigratorData.timestamp = block.timestamp + delay;
        setMigratorData.exists = true;
    }

    function executeSetMigrator() external onlyAdmin {
        require(setMigratorData.exists, "Timelock::setMigrator not prepared");
        executeTransaction(address(masterChef), 0, "", abi.encodeWithSignature("setMigrator(address)", address(setMigratorData.migrator)), setMigratorData.timestamp);
        setMigratorData.migrator = address(0);
        setMigratorData.timestamp = 0;
        setMigratorData.exists = false;
    }

    function transferBabyTokenOwnerShip(address newOwner_) external onlyAdmin { 
        masterChef.transferBabyTokenOwnerShip(newOwner_);
    }

    function transferSyrupOwnerShip(address newOwner_) external onlyAdmin { 
        masterChef.transferSyrupOwnerShip(newOwner_);
    }

    function transferOwnership(address newOwner) external onlyAdmin {
        if (transferOwnershipData.exists) {
            cancelTransaction(address(masterChef), 0, "", abi.encodeWithSignature("transferOwnership(address)", address(newOwner)), transferOwnershipData.timestamp);
        }
        queueTransaction(address(masterChef), 0, "", abi.encodeWithSignature("transferOwnership(address)", address(newOwner)), block.timestamp + delay);
        transferOwnershipData.newOwner = newOwner;
        transferOwnershipData.timestamp = block.timestamp + delay;
        transferOwnershipData.exists = true;
    }

    function executeTransferOwnership() external onlyAdmin {
        require(transferOwnershipData.exists, "Timelock::setMigrator not prepared");
        executeTransaction(address(masterChef), 0, "", abi.encodeWithSignature("transferOwnership(address)", address(transferOwnershipData.newOwner)), transferOwnershipData.timestamp);
        transferOwnershipData.newOwner = address(0);
        transferOwnershipData.timestamp = 0;
        transferOwnershipData.exists = false;
    }

}
