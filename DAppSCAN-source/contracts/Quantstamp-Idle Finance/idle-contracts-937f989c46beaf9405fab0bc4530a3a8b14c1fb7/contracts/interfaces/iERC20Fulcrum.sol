pragma solidity 0.5.11;

interface iERC20Fulcrum {
  function mint(
    address receiver,
    uint256 depositAmount)
    external
    returns (uint256 mintAmount);

  function burn(
    address receiver,
    uint256 burnAmount)
    external
    returns (uint256 loanAmountPaid);

  function tokenPrice()
    external
    view
    returns (uint256 price);

  function supplyInterestRate()
    external
    view
    returns (uint256);

  function rateMultiplier()
    external
    view
    returns (uint256);
  function baseRate()
    external
    view
    returns (uint256);

  function borrowInterestRate()
    external
    view
    returns (uint256);

  function avgBorrowInterestRate()
    external
    view
    returns (uint256);

  function spreadMultiplier()
    external
    view
    returns (uint256);

  function totalAssetBorrow()
    external
    view
    returns (uint256);

  function totalAssetSupply()
    external
    view
    returns (uint256);

  function nextSupplyInterestRate(uint256)
    external
    view
    returns (uint256);

  function nextBorrowInterestRate(uint256)
    external
    view
    returns (uint256);
  function nextLoanInterestRate(uint256)
    external
    view
    returns (uint256);

  function claimLoanToken()
    external
    returns (uint256 claimedAmount);

  /* function burnToEther(
    address receiver,
    uint256 burnAmount)
    external
    returns (uint256 loanAmountPaid);


  function supplyInterestRate()
    external
    view
    returns (uint256);

  function assetBalanceOf(
    address _owner)
    external
    view
    returns (uint256);

  function claimLoanToken()
    external
    returns (uint256 claimedAmount); */
}
