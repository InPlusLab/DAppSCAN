pragma solidity ^0.5.0;

interface DSAuthority {
    function canCall(
        address src,
        address dst,
        bytes4 sig
    ) external view returns (bool);
}
