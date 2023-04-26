pragma solidity ^0.5.16;


contract AbstractERC1155MintBurn {
    function _mint(address, uint256, uint256, bytes memory) internal;
    function _batchMint(address, uint256[] memory, uint256[] memory, bytes memory) internal;
    function _burn(address, uint256, uint256) internal;
    function _batchBurn(address, uint256[] memory, uint256[] memory) internal;
}
