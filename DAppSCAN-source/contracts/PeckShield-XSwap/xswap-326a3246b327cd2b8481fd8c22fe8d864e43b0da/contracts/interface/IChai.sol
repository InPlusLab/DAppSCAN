pragma solidity ^0.5.4;

interface IChai {
	function join(address dst, uint wad) external;
	function exit(address dst, uint wad) external;
	function draw(address src, uint wad) external;
}