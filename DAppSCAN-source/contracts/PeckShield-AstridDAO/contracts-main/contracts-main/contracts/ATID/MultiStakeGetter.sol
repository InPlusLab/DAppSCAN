// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import './ATIDStaking.sol';

contract MultiStakeGetter {

    ATIDStaking public ATIDstakes;

    // --- Functions ---
    constructor(ATIDStaking _ATIDstakes) {
        ATIDstakes = _ATIDstakes;
    }

    // --- lockState helper functions ---

    
    // Traverse the locked stake linked list for the specificed user (_account)
    // and returns an array of all of the active locked stake IDs until the 
    // designated page limit (_pageSize) is reached.
    //
    // If the number of IDs is less than the page limit, the rest of the IDs will 
    // be returned as 0's, which is an invalid ID
    //
    // _startingID provides the starting point of where to enter the linked list
    function getLockedStakesIDsFromHead(address _account, uint _startingID, uint _pageSize) 
        public view returns (uint[] memory)
    {
        require(_pageSize > 0, "Must have a positive pagesize greater than 0");
        
        uint currID;
        uint numIDs = 1;
        uint[] memory IDs = new uint[](_pageSize);

        for (currID = _startingID; numIDs <= _pageSize; numIDs++) {
            if (currID == 0) {
                return IDs;
            }
            IDs[numIDs - 1] = currID;
            (,,,currID,,,) = ATIDstakes.lockedStakeMap(_account, currID);
        }

        return IDs;
    }

    // Traverse the locked stake linked list for the specificed user (_account)
    // and returns an array of all of the active locked stake IDs until the 
    // designated page limit (_pageSize) is reached.
    //
    // If the number of IDs is less than the page limit, the rest of the IDs will 
    // be returned as 0's, which is an invalid ID
    //
    // _startingID provides the starting point of where to enter the linked list
    //
    // This version of the function traverse up the linked list rather than down
    function getLockedStakesIDsFromTail(address _account, uint _startingID, uint _pageSize)
        public view returns (uint[] memory)
    {
        require(_pageSize > 0, "Must have a positive pagesize greater than 0");
        
        uint currID;
        uint numIDs = 1;
        uint[] memory IDs = new uint[](_pageSize);

        for (currID = _startingID; numIDs <= _pageSize; numIDs++) {
            if (currID == 0) {
                return IDs;
            }
            IDs[numIDs - 1] = currID;
            (,,currID,,,,) = ATIDstakes.lockedStakeMap(_account, currID);        
        }

        return IDs;
    }
}