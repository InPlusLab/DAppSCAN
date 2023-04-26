// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./IRNG.sol";
import "./ISP20.sol";
import "./ISP721.sol";
import "./ISP1155.sol";
import "./IStaking.sol";
import "./IManagement.sol";

interface IRegistry {
  function rng() external view returns(IRNG);
  function sp20() external view returns(ISP20);
  function sp721() external view returns(ISP721);
  function sp1155() external view returns(ISP1155);
  function staking() external view returns(IStaking);
  function management() external view returns(IManagement);

  function core(address user) external view returns(bool); 
  function authorized(address contractAddress) external view returns(bool); 
}