pragma solidity ^0.5.0;

/// @title SEKRETOOOO
contract IGeneScience {
    /// @dev simply a boolean to indicate this is the contract we expect to be
    function isGeneScience() public pure returns (bool);

    /// @dev given genes of kitten 1 & 2, return a genetic combination - may have a random factor
    /// @param _genes1 genes of mom
    /// @param _genes2 genes of sire
    /// @param _targetBlock target block
    /// @return the genes that are supposed to be passed down the child
    function mixGenes(
        int256 _id1,
        int256 _id2,
        uint256 _genes1,
        uint256 _genes2,
        uint256 _targetBlock
    ) public returns (uint256);

    function geneLpLabor(int256 _id, uint256 _genes)
        public
        pure
        returns (uint256);

    function isValid(int256 _id, uint256 _genes) public pure returns (bool);

    function totalQuality(int256 _id, uint256 _genes)
        public
        pure
        returns (uint256);

    function getAuctionGene(uint256 _id) public pure returns (uint256);
}
