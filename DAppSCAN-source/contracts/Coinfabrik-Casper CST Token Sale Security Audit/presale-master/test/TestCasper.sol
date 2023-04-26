pragma solidity ^0.4.19;

import "truffle/Assert.sol";
import "truffle/DeployedAddresses.sol";
import "../contracts/CasperToken.sol";

contract TestCasper {
    function dollarsToMicroCSP(uint _dollars) public pure returns (uint) {
        return (uint(10) ** 18) * _dollars * 100 / 12;
    }

    // mainly to avoid typos in main contract if anything will change
    function testConstants() public {
        CasperToken meta = new CasperToken();

        uint total = meta.preICOSupply() + meta.presaleSupply() + meta.crowdsaleSupply() + meta.communitySupply();
        total += meta.systemSupply() + meta.investorSupply() + meta.teamSupply();
        total += meta.adviserSupply() + meta.bountySupply() + meta.referralSupply();
        Assert.equal(meta._totalSupply(), total, "Total supply must be equal to the sum of all supplies");
    }

    function testDealines() public {
        CasperToken meta = new CasperToken();

        Assert.isBelow(meta.presaleStartTime(), meta.crowdsaleStartTime(), "Presale must end after it starts.");
        Assert.isBelow(meta.crowdsaleStartTime(), meta.crowdsaleEndTime(), "Crowd-sale must end after it starts.");
        Assert.isBelow(meta.crowdsaleEndTime(), meta.crowdsaleHardEndTime(), "Crowd-sale hard-end time must happen after soft-end");
    }
}