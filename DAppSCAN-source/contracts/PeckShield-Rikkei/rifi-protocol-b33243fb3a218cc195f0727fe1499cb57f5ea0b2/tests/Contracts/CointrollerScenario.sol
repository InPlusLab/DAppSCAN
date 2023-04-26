pragma solidity ^0.5.16;

import "../../contracts/Cointroller.sol";

contract CointrollerScenario is Cointroller {
    uint public blockNumber;
    address public rifiAddress;

    constructor() Cointroller() public {}

    function fastForward(uint blocks) public returns (uint) {
        blockNumber += blocks;
        return blockNumber;
    }

    function setRifiAddress(address rifiAddress_) public {
        rifiAddress = rifiAddress_;
    }

    function getRifiAddress() public view returns (address) {
        return rifiAddress;
    }

    function setBlockNumber(uint number) public {
        blockNumber = number;
    }

    function getBlockNumber() public view returns (uint) {
        return blockNumber;
    }

    function membershipLength(RToken rToken) public view returns (uint) {
        return accountAssets[address(rToken)].length;
    }

    function unlist(RToken rToken) public {
        markets[address(rToken)].isListed = false;
    }

    /**
     * @notice Recalculate and update RIFI speeds for all RIFI markets
     */
    function refreshRifiSpeeds() public {
        RToken[] memory allMarkets_ = allMarkets;

        for (uint i = 0; i < allMarkets_.length; i++) {
            RToken rToken = allMarkets_[i];
            Exp memory borrowIndex = Exp({mantissa: rToken.borrowIndex()});
            updateRifiSupplyIndex(address(rToken));
            updateRifiBorrowIndex(address(rToken), borrowIndex);
        }

        Exp memory totalUtility = Exp({mantissa: 0});
        Exp[] memory utilities = new Exp[](allMarkets_.length);
        for (uint i = 0; i < allMarkets_.length; i++) {
            RToken rToken = allMarkets_[i];
            if (rifiSpeeds[address(rToken)] > 0) {
                Exp memory assetPrice = Exp({mantissa: oracle.getUnderlyingPrice(rToken)});
                Exp memory utility = mul_(assetPrice, rToken.totalBorrows());
                utilities[i] = utility;
                totalUtility = add_(totalUtility, utility);
            }
        }

        for (uint i = 0; i < allMarkets_.length; i++) {
            RToken rToken = allMarkets[i];
            uint newSpeed = totalUtility.mantissa > 0 ? mul_(rifiRate, div_(utilities[i], totalUtility)) : 0;
            setRifiSpeedInternal(rToken, newSpeed);
        }
    }
}
