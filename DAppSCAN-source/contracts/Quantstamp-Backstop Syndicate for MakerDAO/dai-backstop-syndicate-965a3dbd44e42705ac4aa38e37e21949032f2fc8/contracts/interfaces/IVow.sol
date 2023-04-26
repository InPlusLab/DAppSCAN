pragma solidity 0.5.16;


interface IVow {
    // flop delay
    function wait() external view returns (uint256);
    // flop starting amount of MKR offered (18 decimal places)
    function dump() external view returns (uint256);
    // flop fixed debt quantity to be covered (45 decimal places)
    function sump() external view returns (uint256);
    // start flop auction
    function flop() external returns (uint256 id);
}