// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.0;

interface ISIGHHarvester {

    function accureSIGHForLiquidityStream(address user) external;
    function accureSIGHForBorrowingStream(address user) external;

    function claimSIGH(address[] calldata users) external;
    function claimMySIGH(address user) external;

    function getSighAccured(address account) external view returns (uint);

  function updatePlatformFee(address user, uint platformFeeIncrease, uint platformFeeDecrease) external  ;
  function updateReserveFee(address user, uint reserveFeeIncrease, uint reserveFeeDecrease) external  ;

  function getPlatformFee(address user) external view returns (uint) ;
  function getReserveFee(address user)  external view returns (uint) ;

}
