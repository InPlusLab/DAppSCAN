pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC721/IERC721Enumerable.sol";


abstract contract IRegistry is IERC721Enumerable
{
	function isRegistered(address _entry) external virtual view returns (bool);
}
