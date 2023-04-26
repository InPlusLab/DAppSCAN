pragma solidity 0.5.16;


interface IDaiBackstopSyndicate {
  event AuctionEntered(uint256 auctionId, uint256 mkrAsk, uint256 daiBid);
  event AuctionFinalized(uint256 auctionId);

  enum Status {
    ACCEPTING_DEPOSITS,
    ACTIVATED,
    DEACTIVATED
  }

  // Anyone can deposit Dai up until the auctions have started at 1:1
  function enlist(uint256 daiAmount) external returns (uint256 backstopTokensMinted);

  // Anyone can withdraw at any point as long as Dai is not locked in auctions
  function defect(uint256 backstopTokenAmount) external returns (uint256 daiRedeemed, uint256 mkrRedeemed);

  // Anyone can enter an auction for the syndicate, bidding Dai in return for MKR
  function enterAuction(uint256 auctionId) external;

  // Anyone can finalize an auction, returning the Dai or MKR to the syndicate
  function finalizeAuction(uint256 auctionId) external;

  // An owner can halt all new deposits and auctions (but not withdrawals or ongoing auctions)
  function ceaseFire() external;

  function getStatus() external view returns (Status status);

  function getActiveAuctions() external view returns (uint256[] memory activeAuctions);
}