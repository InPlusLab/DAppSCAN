pragma solidity 0.4.24;


contract IAragonFundraisingController {
    function openTrading() external;
    function collateralsToBeClaimed(address _collateral) public view returns (uint256);
    function balanceOf(address _who, address _token) public view returns (uint256);
}
