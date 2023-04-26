// SPDX-License-Identifier: agpl-3.0

pragma solidity 0.7.0;

/**
 * @dev Library for managing an enumerable variant of Solidity's
 * https://solidity.readthedocs.io/en/latest/types.html#mapping-types[`mapping`] type.
 *
 * Maps have the following properties:
 * - Entries are added, removed, and checked for existence in constant time. (O(1)).
 * - Entries are enumerated in O(n). No guarantees are made on the ordering.
 * ```
 * contract Example {
 *     using EnumerableMap for EnumerableMap.UintToNFTMap;  // Add the library methods
 *     EnumerableMap.UintToNFTMap private myMap;    // Declare a set state variable
 * }
 * ```
 * As of v3.0.0, only maps of type `uint256 -> address` (`UintToNFTMap`) are supported.
 */
library BoostersEnumerableMap {
    // To implement this library for multiple types with as little code
    // repetition as possible, we write it in terms of a generic Map type with bytes32 keys and values.
    // The Map implementation uses private functions, and user-facing
    // implementations (such as Uint256ToAddressMap) are just wrappers around the underlying Map.
    // This means that we can only create new EnumerableMaps for types that fit in bytes32.

    // boosterInfo contains the owner and the type information of a SIGH Finance's Booster NFT
    struct boosterInfo {
        address owner;
        string _type;
    }

    // key is the tokenID and _NFT_Value is the boosterInfo struct
    struct MapEntry {
        bytes32 _key;
        boosterInfo _NFT_Value;
    }

    struct Map {
        MapEntry[] _NFTs;                       // Storage of NFT's keys and boosterInfos        
        mapping (bytes32 => uint256) _indexes;  // Position of the entry defined by a key (tokenID) in the `_NFTs` array, plus 1 because index 0 means a key is not in the map.
    }

    /**
     * @dev Adds a key-value (tokenID - NFT Info) pair to a map, or updates the value for an existing key. O(1).
     * Returns true if the key was added to the map, that is if it was not already present.
     */
    function _set(Map storage map, bytes32 key, boosterInfo memory _NFTvalue) private returns (bool) {
        uint256 keyIndex = map._indexes[key];   // We read and store the key's index to prevent multiple reads from the same storage slot

        if (keyIndex == 0) { 
            map._NFTs.push( MapEntry({ _key: key, _NFT_Value: _NFTvalue }) );            
            map._indexes[key] = map._NFTs.length;        // The entry is stored at length-1, but we add 1 to all indexes and use 0 as a sentinel value
            return true;
        } 
        else {
            map._NFTs[keyIndex - 1]._NFT_Value = _NFTvalue;
            return false;
        }
    }

    /**
     * @dev Removes a key-value pair from a map. O(1). Returns true if the key was removed from the map, that is if it was present.
     */
    function _remove(Map storage map, bytes32 key) private returns (bool) {        
        uint256 keyIndex = map._indexes[key];   // We read and store the key's index to prevent multiple reads from the same storage slot

        if (keyIndex != 0) { 
            // To delete a key-value pair from the _NFTs array in O(1), we swap the entry to delete with the last one in the array, and then remove the last entry (sometimes called as 'swap and pop').
            // This modifies the order of the array, as noted in {at}.

            uint256 toDeleteIndex = keyIndex - 1;
            uint256 lastIndex = map._NFTs.length - 1;

            // When the entry to delete is the last one, the swap operation is unnecessary. However, since this occurs so rarely, we still do the swap anyway to avoid the gas cost of adding an 'if' statement.
            MapEntry storage lastEntry = map._NFTs[lastIndex];
            
            map._NFTs[toDeleteIndex] = lastEntry;            // Move the last entry to the index where the entry to delete is
            map._indexes[lastEntry._key] = toDeleteIndex + 1;   // Update the index for the moved entry. All indexes are 1-based
            
            map._NFTs.pop();                     // Delete the slot where the moved entry was stored            
            delete map._indexes[key];              // Delete the index for the deleted slot

            return true;
        } 
        else {
            return false;
        }
    }

    /**
     * @dev Returns true if the key is in the map. O(1).
     */
    function _contains(Map storage map, bytes32 key) private view returns (bool) {
        return map._indexes[key] != 0;
    }

    /**
     * @dev Returns the number of key-value pairs in the map. O(1).
     */
    function _length(Map storage map) private view returns (uint256) {
        return map._NFTs.length;
    }

   /**
    * @dev Returns the key-value pair stored at position `index` in the map. O(1).
    * Note that there are no guarantees on the ordering of entries inside the
    * array, and it may change when more entries are added or removed.
    * Requirements:
    * - `index` must be strictly less than {length}.
    */
    function _at(Map storage map, uint256 index) private view returns (bytes32, address, string memory) {
        require(map._NFTs.length > index, "EnumerableMap: index out of bounds");

        MapEntry storage entry = map._NFTs[index];
        return (entry._key, entry._NFT_Value.owner, entry._NFT_Value._type );
    }

    /**
     * @dev Returns the value associated with `key`.  O(1).
     * Requirements:
     * - `key` must be in the map.
     */
    function _get(Map storage map, bytes32 key) private view returns (address, string memory) {
        return _get(map, key, "EnumerableMap: nonexistent key");
    }

    /**
     * @dev Same as {_get}, with a custom error message when `key` is not in the map.
     */
    function _get(Map storage map, bytes32 key, string memory errorMessage) private view returns (address, string memory) {
        uint256 keyIndex = map._indexes[key];
        require(keyIndex != 0, errorMessage); // Equivalent to contains(map, key)
        return (map._NFTs[keyIndex - 1]._NFT_Value.owner, map._NFTs[keyIndex - 1]._NFT_Value._type); // All indexes are 1-based
    }

    //##############################
    //######  UintToNFTMap  ########
    //##############################

    struct UintToNFTMap {
        Map _inner;
    }

    /**
     * @dev Adds a key-value pair to a map, or updates the value for an existing key. O(1).
     * Returns true if the key was added to the map, that is if it was not already present.
     */
    function set(UintToNFTMap storage map, uint256 key, boosterInfo memory _NFT_value) internal returns (bool) {
        return _set(map._inner, bytes32(key), _NFT_value );
    }

    /**
     * @dev Removes a value from a set. O(1).
     * Returns true if the key was removed from the map, that is if it was present.
     */
    function remove(UintToNFTMap storage map, uint256 key) internal returns (bool) {
        return _remove(map._inner, bytes32(key));
    }

    /**
     * @dev Returns true if the key is in the map. O(1).
     */
    function contains(UintToNFTMap storage map, uint256 key) internal view returns (bool) {
        return _contains(map._inner, bytes32(key));
    }

    /**
     * @dev Returns the number of elements in the map. O(1).
     */
    function length(UintToNFTMap storage map) internal view returns (uint256) {
        return _length(map._inner);
    }

   /**
    * @dev Returns the element stored at position `index` in the set. O(1).
    * Note that there are no guarantees on the ordering of values inside the array, and it may change when more values are added or removed.
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function at(UintToNFTMap storage map, uint256 index) internal view returns (uint256, address, string memory) {
        (bytes32 key, address _owner, string memory _type) = _at(map._inner, index);
        return (uint256(key), _owner, _type );
    }

    /**
     * @dev Returns the value associated with `key`.  O(1).
     * Requirements:
     * - `key` must be in the map.
     */
    function get(UintToNFTMap storage map, uint256 key) internal view returns (address,string memory) {
        return _get(map._inner, bytes32(key));
    }

    /**
     * @dev Same as {get}, with a custom error message when `key` is not in the map.
     */
    function get(UintToNFTMap storage map, uint256 key, string memory errorMessage) internal view returns (address,string memory) {
        return _get(map._inner, bytes32(key), errorMessage);
    }
}
