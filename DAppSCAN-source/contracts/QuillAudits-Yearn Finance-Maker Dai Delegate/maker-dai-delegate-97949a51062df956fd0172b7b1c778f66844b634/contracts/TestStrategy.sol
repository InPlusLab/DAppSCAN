// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./Strategy.sol";

// The purpose of this wrapper contract is to expose internal functions
// that may contain application logic and therefore need to be unit tested.
contract TestStrategy is Strategy {
    constructor(
        address _vault,
        address _yVault,
        string memory _strategyName,
        bytes32 _ilk,
        address _gemJoin,
        address _wantToUSDOSMProxy,
        address _chainlinkWantToUSDPriceFeed,
        address _chainlinkWantToETHPriceFeed
    )
        public
        Strategy(
            _vault,
            _yVault,
            _strategyName,
            _ilk,
            _gemJoin,
            _wantToUSDOSMProxy,
            _chainlinkWantToUSDPriceFeed,
            _chainlinkWantToETHPriceFeed
        )
    {}

    function _liquidatePosition(uint256 _amountNeeded)
        public
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        (_liquidatedAmount, _loss) = liquidatePosition(_amountNeeded);
    }

    function _getPrice() public view returns (uint256) {
        return _getWantTokenPrice();
    }

    function _getCurrentMakerVaultRatio() public view returns (uint256) {
        return getCurrentMakerVaultRatio();
    }

    function freeCollateral(uint256 collateralAmount) public {
        return _freeCollateralAndRepayDai(collateralAmount, 0);
    }
}
