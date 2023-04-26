// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MockNFT is ERC721("MCK","MCK") {
    function mint(address _recipient, uint256 _tokenId) external {
        _mint(_recipient, _tokenId);
    }
}
