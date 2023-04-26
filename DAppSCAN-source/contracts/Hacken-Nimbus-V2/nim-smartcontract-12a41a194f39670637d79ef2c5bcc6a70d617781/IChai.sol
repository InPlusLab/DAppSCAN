pragma solidity >=0.5.0 <0.6.0;
//SWC-Contracts are unused:L1-45
import "./IERC20.sol";


interface IPot {
    function dsr()
        external
        view
        returns (uint256);

    function chi()
        external
        view
        returns (uint256);

    function rho()
        external
        view
        returns (uint256);
}

contract IChai is IERC20 {
    function move(
        address src,
        address dst,
        uint256 wad)
        external
        returns (bool);

    function join(
        address dst,
        uint256 wad)
        external;

    function draw(
        address src,
        uint256 wad)
        external;

    function exit(
        address src,
        uint wad)
        external;
}
