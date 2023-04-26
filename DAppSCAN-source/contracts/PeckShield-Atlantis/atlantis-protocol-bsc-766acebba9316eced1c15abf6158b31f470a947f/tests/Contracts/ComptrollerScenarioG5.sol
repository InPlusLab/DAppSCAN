pragma solidity ^0.5.16;

import "../../contracts/ComptrollerG5.sol";

contract ComptrollerScenarioG5 is ComptrollerG5 {
    uint public blockNumber;
    address public atlantisAddress;

    constructor() ComptrollerG5() public {}

    function setAtlantisAddress(address atlantisAddress_) public {
        atlantisAddress = atlantisAddress_;
    }

    function getAtlantisAddress() public view returns (address) {
        return atlantisAddress;
    }

    function membershipLength(AToken aToken) public view returns (uint) {
        return accountAssets[address(aToken)].length;
    }

    function fastForward(uint blocks) public returns (uint) {
        blockNumber += blocks;

        return blockNumber;
    }

    function setBlockNumber(uint number) public {
        blockNumber = number;
    }

    function getBlockNumber() public view returns (uint) {
        return blockNumber;
    }

    function getAtlantisMarkets() public view returns (address[] memory) {
        uint m = allMarkets.length;
        uint n = 0;
        for (uint i = 0; i < m; i++) {
            if (markets[address(allMarkets[i])].isAtled) {
                n++;
            }
        }

        address[] memory atlantisMarkets = new address[](n);
        uint k = 0;
        for (uint i = 0; i < m; i++) {
            if (markets[address(allMarkets[i])].isAtled) {
                atlantisMarkets[k++] = address(allMarkets[i]);
            }
        }
        return atlantisMarkets;
    }

    function unlist(AToken aToken) public {
        markets[address(aToken)].isListed = false;
    }
}
