pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface ApproveAndCallFallBack {
    function receiveApproval(address _sender, uint256 _amount, address token, bytes memory _data) external;
}

contract mockMGH is ERC20 {

    function approveAndCall(ApproveAndCallFallBack _spender, uint256 _amount, bytes memory _extraData) public returns (bool success) {
        require(approve(address(_spender), _amount));

        _spender.receiveApproval(
            msg.sender,
            _amount,
            address(this),
            _extraData
        );

        return true;
    }

    function __mint(uint256 amount) public {
        _mint(msg.sender, amount * 10**18);
    }

    constructor(string memory name, string memory symbol, uint256 initialSupply) ERC20(name, symbol) {
        __mint(initialSupply);
    }
}