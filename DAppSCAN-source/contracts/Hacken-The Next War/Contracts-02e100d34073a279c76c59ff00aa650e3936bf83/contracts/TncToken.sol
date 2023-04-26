// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TncToken is ERC20, Ownable {
    mapping (address => bool) internal authorizations;

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply,
        address _wallet
    ) ERC20 (_name, _symbol) {
        authorizations[_msgSender()] = true;
        _mint(_wallet, _totalSupply * (10 ** decimals()));
    }

    function mint(address _to, uint256 _amount) external {
        require(isAuthorized(msg.sender), "TncToken : UNAUTHORIZED");
        _mint(_to, _amount);
    }

    function authorize(address _adr, bool _authorize) external {
        require(isAuthorized(msg.sender), "TncToken : UNAUTHORIZED");
        authorizations[_adr] = _authorize;
    }

    function isAuthorized(address _adr) public view returns (bool) {
        return authorizations[_adr];
    }

}