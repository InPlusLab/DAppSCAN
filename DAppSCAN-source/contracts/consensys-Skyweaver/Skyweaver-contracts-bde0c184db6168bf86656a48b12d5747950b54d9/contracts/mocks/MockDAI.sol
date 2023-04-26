pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "erc20-meta-wrapper/contracts/mocks/ERC20Mock.sol";
import "../utils/Ownable.sol";

contract MockDAI is ERC20Mock, Ownable {
    function mockMint(address _address, uint256 _amount) public onlyOwner {
        _mint(_address, _amount);
    }
}