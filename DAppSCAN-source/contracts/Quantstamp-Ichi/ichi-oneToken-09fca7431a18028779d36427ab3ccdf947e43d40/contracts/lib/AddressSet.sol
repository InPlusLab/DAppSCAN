// SPDX-License-Identifier: Unlicensed

pragma solidity 0.7.6;

/**
 * @notice Key sets with enumeration and delete. Uses mappings for random access
 * and existence checks and dynamic arrays for enumeration. Key uniqueness is enforced. 
 * @dev Sets are unordered. Delete operations reorder keys. All operations have a 
 * fixed gas cost at any scale, O(1). 
 */

library AddressSet {
    
    struct Set {
        mapping(address => uint) keyPointers;
        address[] keyList;
    }

    /**
     @notice insert a key. 
     @dev duplicate keys are not permitted.
     @param self storage pointer to a Set. 
     @param key value to insert.
     */    
    function insert(Set storage self, address key, string memory errorMessage) internal {
        require(!exists(self, key), errorMessage);
        self.keyList.push(key);
        self.keyPointers[key] = self.keyList.length-1;
    }

    /**
     @notice remove a key.
     @dev key to remove must exist. 
     @param self storage pointer to a Set.
     @param key value to remove.
     */    
    function remove(Set storage self, address key, string memory errorMessage) internal {
        require(exists(self, key), errorMessage);
        uint last = count(self) - 1;
        uint rowToReplace = self.keyPointers[key];
        address keyToMove = self.keyList[last];
        self.keyPointers[keyToMove] = rowToReplace;
        self.keyList[rowToReplace] = keyToMove;
        delete self.keyPointers[key];
        self.keyList.pop();
    }

    /**
     @notice count the keys.
     @param self storage pointer to a Set. 
     */       
    function count(Set storage self) internal view returns(uint) {
        return(self.keyList.length);
    }

    /**
     @notice check if a key is in the Set.
     @param self storage pointer to a Set.
     @param key value to check. Version
     @return bool true: Set member, false: not a Set member.
     */  
    function exists(Set storage self, address key) internal view returns(bool) {
        if(self.keyList.length == 0) return false;
        return self.keyList[self.keyPointers[key]] == key;
    }

    /**
     @notice fetch a key by row (enumerate).
     @param self storage pointer to a Set.
     @param index row to enumerate. Must be < count() - 1.
     */      
    function keyAtIndex(Set storage self, uint index) internal view returns(address) {
        return self.keyList[index];
    }
}
