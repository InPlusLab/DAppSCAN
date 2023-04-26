pragma solidity ^0.5.10;

contract _DSValue {
    // TODO: View or constant? It's clearly a view...
    function peek() public view returns (bytes32, bool);

    function read() public view returns (bytes32);
}
