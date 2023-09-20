pragma solidity ^0.4.4;
//SWC-101-Integer Overflow and Underflow:L1-69
import "./Token.sol";

contract GNTAllocation {
    // Total number of allocations to distribute additional tokens among
    // developers and the Golem Factory. The Golem Factory has right to 20000
    // allocations, developers to 10000 allocations, divides among individual
    // developers by numbers specified in  `allocations` table.
    uint256 constant totalAllocations = 30000;

    // Addresses of developer and the Golem Factory to allocations mapping.
    mapping (address => uint256) allocations;

    GolemNetworkToken gnt;
    uint256 unlockedAt;

    uint256 tokensCreated = 0;

    function GNTAllocation(address _golemFactory) internal {
        gnt = GolemNetworkToken(msg.sender);
        unlockedAt = now + 6 * 30 days;
//SWC-116-Block values as a proxy for time:L22
        // For the Golem Factory:
        allocations[_golemFactory] = 20000; // 12/18 pp of 30000 allocations.

        // For developers:
        allocations[0xde00] = 2500; // 25.0% of developers' allocations (10000).
        allocations[0xde01] =  730; //  7.3% of developers' allocations.
        allocations[0xde02] =  730;
        allocations[0xde03] =  730;
        allocations[0xde04] =  730;
        allocations[0xde05] =  730;
        allocations[0xde06] =  630; //  6.3% of developers' allocations.
        allocations[0xde07] =  630;
        allocations[0xde08] =  630;
        allocations[0xde09] =  630;
        allocations[0xde10] =  310; //  3.1% of developers' allocations.
        allocations[0xde11] =  153; //  1.53% of developers' allocations.
        allocations[0xde12] =  150; //  1.5% of developers' allocations.
        allocations[0xde13] =  100; //  1.0% of developers' allocations.
        allocations[0xde14] =  100;
        allocations[0xde15] =  100;
        allocations[0xde16] =   70; //  0.7% of developers' allocations.
        allocations[0xde17] =   70;
        allocations[0xde18] =   70;
        allocations[0xde19] =   70;
        allocations[0xde20] =   70;
        allocations[0xde21] =   42; //  0.42% of developers' allocations.
        allocations[0xde22] =   25; //  0.25% of developers' allocations.
    }

    // Allows developer to unlock its allocated tokens by transferring them back
    // to developer's address.
    function unlock() external {
        if (now < unlockedAt) throw;

        // During first unlock attempt fetch total number of locked tokens.
        if (tokensCreated == 0)
            tokensCreated = gnt.balanceOf(this);

        var allocation = allocations[msg.sender];
        allocations[msg.sender] = 0;
        var toTransfer = tokensCreated * allocation / totalAllocations;

        // Will fail if allocation (and therefore toTransfer) is 0.
        if (!gnt.transfer(msg.sender, toTransfer)) throw;
    }
}
