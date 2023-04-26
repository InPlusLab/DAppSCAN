import 'openzeppelin-solidity/contracts/token/ERC20/ERC20.sol';

pragma solidity ^0.5.10;

contract _MakerMedianizer {
    bool    has;
    bytes32 val;
    function peek() public view returns (bytes32, bool) {
        return (val,has);
    }
    function read() public view returns (bytes32) {
        (bytes32 wut, bool has_) = peek();
        assert(has_);
        return wut;
    }
    function poke(bytes32 wut) public {
        val = wut;
        has = true;
    }
    function void() public { // unset the value
        has = false;
    }

    function push(uint256 amt, ERC20 tok) public {
        tok.transferFrom(msg.sender, address(this), amt);
    }
}
