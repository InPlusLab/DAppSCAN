pragma solidity ^0.5.16;

import "../../contracts/Comptroller.sol";

contract ComptrollerScenario is Comptroller {
    uint public blockNumber;
    address public atlantisAddress;

    constructor() Comptroller() public {}

    function fastForward(uint blocks) public returns (uint) {
        blockNumber += blocks;
        return blockNumber;
    }

    function setAtlantisAddress(address atlantisAddress_) public {
        atlantisAddress = atlantisAddress_;
    }

    function getAtlantisAddress() public view returns (address) {
        return atlantisAddress;
    }

    function setBlockNumber(uint number) public {
        blockNumber = number;
    }

    function getBlockNumber() public view returns (uint) {
        return blockNumber;
    }

    function membershipLength(AToken aToken) public view returns (uint) {
        return accountAssets[address(aToken)].length;
    }

    function unlist(AToken aToken) public {
        markets[address(aToken)].isListed = false;
    }

    /**
     * @notice Recalculate and update Atlantis speeds for all Atlantis markets
     */
    function refreshAtlantisSpeeds() public {
        AToken[] memory allMarkets_ = allMarkets;

        for (uint i = 0; i < allMarkets_.length; i++) {
            AToken aToken = allMarkets_[i];
            Exp memory borrowIndex = Exp({mantissa: aToken.borrowIndex()});
            updateAtlantisSupplyIndex(address(aToken));
            updateAtlantisBorrowIndex(address(aToken), borrowIndex);
        }

        Exp memory totalUtility = Exp({mantissa: 0});
        Exp[] memory utilities = new Exp[](allMarkets_.length);
        for (uint i = 0; i < allMarkets_.length; i++) {
            AToken aToken = allMarkets_[i];
            if (atlantisSpeeds[address(aToken)] > 0) {
                Exp memory assetPrice = Exp({mantissa: oracle.getUnderlyingPrice(aToken)});
                Exp memory utility = mul_(assetPrice, aToken.totalBorrows());
                utilities[i] = utility;
                totalUtility = add_(totalUtility, utility);
            }
        }

        for (uint i = 0; i < allMarkets_.length; i++) {
            AToken aToken = allMarkets[i];
            uint newSpeed = totalUtility.mantissa > 0 ? mul_(atlantisRate, div_(utilities[i], totalUtility)) : 0;
            setAtlantisSpeedInternal(aToken, newSpeed);
        }
    }
}
