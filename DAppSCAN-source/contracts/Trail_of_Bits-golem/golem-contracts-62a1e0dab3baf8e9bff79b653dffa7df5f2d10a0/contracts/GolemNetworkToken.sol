// SWC-102-Outdated Compiler Version: L2
pragma solidity ^0.4.16;

contract MigrationAgent {
    function migrateFrom(address _from, uint256 _value);
}

contract GNTAllocation {
    function GNTAllocation(address _golemFactory) {}
}

/// @title Golem Network Token (GNT) - crowdfunding code for Golem Project
contract GolemNetworkToken {
    string public constant name = "Test Golem Network Token";
    string public constant symbol = "tGNT";
    uint8 public constant decimals = 18;  // 18 decimal places, the same as ETH.

    uint256 public constant tokenCreationRate = 10000000000;

    // The funding cap in weis.
    uint256 public constant tokenCreationCap = 82 finney * tokenCreationRate;
    uint256 public constant tokenCreationMin = 15 finney * tokenCreationRate;

    uint256 public fundingStartBlock;
    uint256 public fundingEndBlock;

    // The flag indicates if the GNT contract is in Funding state.
    bool public funding = true;

    // Receives ETH and its own GNT endowment.
    address public golemFactory;

    // Has control over token migration to next version of token.
    address public migrationMaster;

    GNTAllocation lockedAllocation;

    // The current total token supply.
    uint256 public totalTokens;

    mapping (address => uint256) balances;

    address public migrationAgent;
    uint256 public totalMigrated;

    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Migrate(address indexed _from, address indexed _to, uint256 _value);
    event Refund(address indexed _from, uint256 _value);

    function GolemNetworkToken(address _golemFactory,
                               address _migrationMaster,
                               uint256 _fundingStartBlock,
                               uint256 _fundingEndBlock) {

        if (_golemFactory == 0) revert();
        if (_migrationMaster == 0) revert();
        if (_fundingStartBlock <= block.number) revert();
        if (_fundingEndBlock   <= _fundingStartBlock) revert();

        lockedAllocation = new GNTAllocation(_golemFactory);
        migrationMaster = _migrationMaster;
        golemFactory = _golemFactory;
        fundingStartBlock = _fundingStartBlock;
        fundingEndBlock = _fundingEndBlock;
    }

    /// @notice Transfer `_value` GNT tokens from sender's account
    /// `msg.sender` to provided account address `_to`.
    /// @notice This function is disabled during the funding.
    /// @dev Required state: Operational
    /// @param _to The address of the tokens recipient
    /// @param _value The amount of token to be transferred
    /// @return Whether the transfer was successful or not
    function transfer(address _to, uint256 _value) returns (bool) {
        // Abort if not in Operational state.
        if (funding) revert();

        var senderBalance = balances[msg.sender];
        if (senderBalance >= _value && _value > 0) {
            senderBalance -= _value;
            balances[msg.sender] = senderBalance;
            balances[_to] += _value;
            Transfer(msg.sender, _to, _value);
            return true;
        }
        return false;
    }

    function totalSupply() external view returns (uint256) {
        return totalTokens;
    }

    function balanceOf(address _owner) external view returns (uint256) {
        return balances[_owner];
    }

    // Token migration support:

    /// @notice Migrate tokens to the new token contract.
    /// @dev Required state: Operational Migration
    /// @param _value The amount of token to be migrated
    function migrate(uint256 _value) external {
        // Abort if not in Operational Migration state.
        if (funding) revert();
        if (migrationAgent == 0) revert();

        // Validate input value.
        if (_value == 0) revert();
        if (_value > balances[msg.sender]) revert();

        balances[msg.sender] -= _value;
        totalTokens -= _value;
        totalMigrated += _value;
        MigrationAgent(migrationAgent).migrateFrom(msg.sender, _value);
        Migrate(msg.sender, migrationAgent, _value);
    }

    /// @notice Set address of migration target contract and enable migration
	/// process.
    /// @dev Required state: Operational Normal
    /// @dev State transition: -> Operational Migration
    /// @param _agent The address of the MigrationAgent contract
    function setMigrationAgent(address _agent) external {
        // Abort if not in Operational Normal state.
        if (funding) revert();
        if (migrationAgent != 0) revert();
        if (msg.sender != migrationMaster) revert();
        migrationAgent = _agent;
    }

    function setMigrationMaster(address _master) external {
        if (msg.sender != migrationMaster) revert();
        if (_master == 0) revert();
        migrationMaster = _master;
    }

    // Crowdfunding:

    /// @notice Create tokens when funding is active.
    /// @dev Required state: Funding Active
    /// @dev State transition: -> Funding Success (only if cap reached)
    function create() payable external {
        // Abort if not in Funding Active state.
        // The checks are split (instead of using or operator) because it is
        // cheaper this way.
        if (!funding) revert();
        if (block.number < fundingStartBlock) revert();
        if (block.number > fundingEndBlock) revert();

        // Do not allow creating 0 or more than the cap tokens.
        if (msg.value == 0) revert();
        if (msg.value > (tokenCreationCap - totalTokens) / tokenCreationRate)
            revert();

        var numTokens = msg.value * tokenCreationRate;
        totalTokens += numTokens;

        // Assign new tokens to the sender
        balances[msg.sender] += numTokens;

        // Log token creation event
        Transfer(0, msg.sender, numTokens);
    }

    /// @notice Finalize crowdfunding
    /// @dev If cap was reached or crowdfunding has ended then:
    /// create GNT for the Golem Factory and developer,
    /// transfer ETH to the Golem Factory address.
    /// @dev Required state: Funding Success
    /// @dev State transition: -> Operational Normal
    function finalize() external {
        // Abort if not in Funding Success state.
        if (!funding) revert();
        if ((block.number <= fundingEndBlock ||
             totalTokens < tokenCreationMin) &&
            totalTokens < tokenCreationCap) revert();

        // Switch to Operational state. This is the only place this can happen.
        funding = false;

        // Create additional GNT for the Golem Factory and developers as
        // the 18% of total number of tokens.
        // All additional tokens are transfered to the account controller by
        // GNTAllocation contract which will not allow using them for 6 months.
        uint256 percentOfTotal = 18;
        uint256 additionalTokens =
            totalTokens * percentOfTotal / (100 - percentOfTotal);
        totalTokens += additionalTokens;
        balances[lockedAllocation] += additionalTokens;
        Transfer(0, lockedAllocation, additionalTokens);

        // Transfer ETH to the Golem Factory address.
        if (!golemFactory.send(this.balance)) revert();
    }

    /// @notice Get back the ether sent during the funding in case the funding
    /// has not reached the minimum level.
    /// @dev Required state: Funding Failure
    function refund() external {
        // Abort if not in Funding Failure state.
        if (!funding) revert();
        if (block.number <= fundingEndBlock) revert();
        if (totalTokens >= tokenCreationMin) revert();

        var gntValue = balances[msg.sender];
        if (gntValue == 0) revert();
        balances[msg.sender] = 0;
        totalTokens -= gntValue;

        var ethValue = gntValue / tokenCreationRate;
        Refund(msg.sender, ethValue);
        if (!msg.sender.send(ethValue)) revert();
    }
}
