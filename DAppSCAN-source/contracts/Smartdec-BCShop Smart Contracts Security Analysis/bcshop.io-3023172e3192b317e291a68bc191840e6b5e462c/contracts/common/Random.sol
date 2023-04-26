pragma solidity ^0.4.18;

/**@dev Based on Random Number Generator from Winem project */
contract Random {    
    uint32 state;
    uint32 MAX = 0xffffffff;
    uint32 current;

    function Random(uint32 seed) {
        state = seed;
    }
    
    /**@dev Returns random integer number from the range [min, max], including borders */
    function getInt(uint32 min, uint32 max) public returns (uint32) {
        getNextNumber();        
        current = uint32(min + (uint256(state) * (max + 1 - min) / MAX));
        return current;
    }

    function getNextNumber() internal {
        state = (69069 * state) + 362437;
    }
}
