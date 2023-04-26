// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface ICommunityIssuance { 
    
    // --- Events ---
    
    event ATIDTokenAddressSet(address _atidTokenAddress);
    event StabilityPoolAddressSet(address _stabilityPoolAddress, string _collateralName);
    event TotalATIDIssuedUpdated(uint _totalATIDIssued);

    // --- Functions ---

    function setATIDTokenAddress(address _atidTokenAddress) external;

    function setStabilityPoolAddress(address _stabilityPoolAddress, string memory _collateralName) external;

    function setRewardDistributionFractions
    (
        string[] memory _collateralNames,
        uint[] memory _fractions
    )
    external;

    function issueATID() external;

    function getAndClearAccumulatedATID(string memory _collateralName) external returns (uint accumulatedATID);

    function sendATID(address _account, uint _ATIDamount) external;
}
