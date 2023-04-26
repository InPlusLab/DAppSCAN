pragma solidity ^0.5.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @title SEKRETOOOO
contract IAliana is IERC721 {
    function createOfficialAliana(uint256 _genes, address _owner)
        public
        returns (uint256);

    function burn(uint256 _tokenID) external;

    function isAliana() public returns (bool);

    function geneLpLabor(int256 _id, uint256 _gene)
        public
        view
        returns (uint256);

    function geneLpLabors(int256[] memory _ids, uint256[] memory _genes)
        public
        view
        returns (uint256[] memory);

    function tokensOfOwner(address _owner)
        external
        view
        returns (uint256[] memory ownerTokens);

    function getAliana(uint256 _id)
        external
        view
        returns (
            uint256 birthTime,
            uint256 matronId,
            uint256 sireId,
            uint256 genes,
            uint256 lpLabor
        );
}
