pragma solidity ^0.5.0;

/// @title SEKRETOOOO
contract IAlianaMint {
    function depositedTokens(address _owner)
        public
        view
        returns (uint256[] memory ownerTokens);
}
