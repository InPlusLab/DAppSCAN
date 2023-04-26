// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "./Vesting/IvestingMinimal.sol";
import "./IFO/IFixPriceMinimal.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract DACFactory is Ownable {

  address public vestingImp;
  address public saleImp;
  address[] public vestingClones;
  address[] public saleClones;

  event VestingCreated(address indexed vesting, address indexed token);
  event SaleCreated(address indexed _address, address indexed offeringToken);

  constructor(address vesting, address sale) {
    vestingImp = vesting;
    saleImp = sale;
  }

  function createVestingClone
    (
    address token,
    address admin,
    uint256 startInDays,
    uint256 durationInDays,
    uint256 cliff,
    uint256 cliffDelayInDays,
    uint256 exp
    )
    external returns(address clone)
    {
    clone = Clones.clone(vestingImp);
    IvestingMinimal(clone).initialize(
      token,
      admin,
      startInDays,
      durationInDays,
      cliff,
      cliffDelayInDays,
      exp
    );
    vestingClones.push(clone);
    emit VestingCreated(clone, token);
  }

  function createSaleClone
    (
    address lpToken,
    address offeringToken,
    address priceFeed,
    address admin,
    uint256 offeringAmount,
    uint256 price,
    uint256 startBlock,
    uint256 endBlock,
    uint256 harvestBlock
    )
    external returns(address clone)
    {
    clone = Clones.clone(saleImp);
    IMGHPublicOffering(clone).initialize(
      lpToken,
      offeringToken,
      priceFeed,
      admin,
      offeringAmount,
      price,
      startBlock,
      endBlock,
      harvestBlock
    );
    saleClones.push(clone);
    emit SaleCreated(clone, offeringToken);
  }

  function customClone(address implementation) public returns(address clone) {
    clone = Clones.clone(implementation);
  }

  function updateImplementation(address _saleImp, address _vestImp) external onlyOwner {
    saleImp = _saleImp;
    vestingImp = _vestImp;
  }
}