// Copyright (C) 2021 BITFISH LIMITED

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.8.4;

import "./interfaces/IERC721.sol";
import "./interfaces/IERC721Receiver.sol";
import "./interfaces/IStakefishServicesContract.sol";
import "./libraries/Address.sol";
import "./libraries/ReentrancyGuard.sol";

contract StakefishERC721Wrapper is IERC721, ReentrancyGuard {
    using Address for address;

    mapping(uint256 => address) private _servicesContracts;
    mapping(uint256 => uint256) private _deposits;
    mapping(uint256 => address) private _owners;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => bool)) private _operatorApprovals;
    uint256 private _totalMinted;

    event Mint(address indexed servicesContract, address indexed sender, address indexed to, uint256 amount, uint256 tokenId);
    event Redeem(address indexed servicesContract, address indexed sender, address indexed to, uint256 amount, uint256 tokenId);

    // ERC165
    
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return 
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }

    // Wrapper functions

    /// @dev It can be tricked into performing external calls to a malicious contract, 
    /// but the token system for each service servicesContract is entirely separate.
    // SWC-107-Reentrancy: L53-L71
    function mintTo(address servicesContract, address to, uint256 amount) public nonReentrant returns (uint256) {
        require(amount > 0, "Amount can't be 0");

        uint256 tokenId = _safeMint(to, "");

        _servicesContracts[tokenId] = servicesContract;
        _deposits[tokenId] = amount;

        bool success = IStakefishServicesContract(payable(servicesContract)).transferDepositFrom(
            msg.sender,
            address(this),
            amount
        );
        require(success, "Transfer deposit failed");

        emit Mint(servicesContract, msg.sender, to, amount, tokenId);
        
        return tokenId;
    }

    function mint(address servicesContract, uint256 amount) external returns (uint256) {
        return mintTo(servicesContract, msg.sender, amount);
    }

    /// @dev It can be tricked into performing external calls to a malicious contract, 
    /// but the token system for each service servicesContract is entirely separate.
    function redeemTo(uint256 tokenId, address to) public nonReentrant {
        require(msg.sender == _owners[tokenId], "Not token owner");
        
        _burn(tokenId);

        address servicesContract = _servicesContracts[tokenId];
        uint256 amount = _deposits[tokenId];
        bool success = IStakefishServicesContract(payable(servicesContract)).transferDeposit(
            to,
            amount
        );
        require(success, "Transfer deposit failed");

        emit Redeem(servicesContract, msg.sender, to, amount, tokenId);
    }

    function redeem(uint256 tokenId) external {
        redeemTo(tokenId, msg.sender);
    }

    function getTotalMinted() public view returns (uint256) {
        return _totalMinted;
    }

    function getDeposit(uint256 tokenId) public view returns (uint256) {
        require(_owners[tokenId] != address(0), "Token does not exist");

        return _deposits[tokenId];
    }

    function getServicesContract(uint256 tokenId) public view returns (address) {
        require(_owners[tokenId] != address(0), "Token does not exist");

        return _servicesContracts[tokenId];
    }

    // ERC721 functions

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override {
        require(_isApprovedOrOwner(msg.sender, tokenId), "Not owner nor approved");
            
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public override {
        require(_isApprovedOrOwner(msg.sender, tokenId), "Not owner nor approved");

        _safeTransfer(from, to, tokenId, data);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override {
        safeTransferFrom(from, to, tokenId, "");
    }

    function approve(address to, uint256 tokenId) public override {
        address owner = _owners[tokenId];
        require(to != owner, "Approval to current owner");

        require(
            msg.sender == owner || isApprovedForAll(owner, msg.sender),
            "Not owner nor approved for all"
        );

        _approve(to, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) public override {
        require(operator != msg.sender, "Approve to caller");

        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function balanceOf(address owner) public view override returns (uint256) {
        require(owner != address(0), "Balance query for the zero address");
        return _balances[owner];
    }

    function ownerOf(uint256 tokenId) public view override returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "Owner query for non-existent token");
        return owner;
    }

    function getApproved(uint256 tokenId) public view override returns (address) {
        require(_owners[tokenId] != address(0), "Approved query for non-existent token");

        return _tokenApprovals[tokenId];
    }
    
    function isApprovedForAll(address owner, address operator) public view override returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function _mint(address to) internal returns (uint256) {
        require(to != address(0), "Mint to the zero address");

        uint256 tokenId = _totalMinted;
        _totalMinted += 1;
        _balances[to] += 1;
        _owners[tokenId] = to; 

        emit Transfer(address(0), to, tokenId);

        return tokenId;
    }

    function _safeMint(address to, bytes memory data) internal returns (uint256 tokenId) {
        tokenId = _mint(to);

        require(
            _checkOnERC721Received(address(0), to, tokenId, data),
            "Transfer to non ERC721Receiver"
        );
    }

    function _burn(uint256 tokenId) internal {
        address owner = _owners[tokenId];

        _approve(address(0), tokenId);
        _balances[owner] -= 1;
        delete _owners[tokenId];

        emit Transfer(owner, address(0), tokenId);
    }

    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal {
        require(_owners[tokenId] == from, "From is not token owner");

        _approve(address(0), tokenId);

        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }

    function _safeTransfer(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) internal {
        _transfer(from, to, tokenId);
        require(_checkOnERC721Received(from, to, tokenId, data), "Transfer to non ERC721Receiver");
    }

    function _approve(address to, uint256 tokenId) internal {
        _tokenApprovals[tokenId] = to;
        
        emit Approval(_owners[tokenId], to, tokenId);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address owner = _owners[tokenId];
        require(owner != address(0), "Operator query for non-existent token");
        return (spender == owner || getApproved(tokenId) == spender || isApprovedForAll(owner, spender));
    }

    function _checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) internal returns (bool) {
        if (to.isContract()) {
            try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data) returns (bytes4 retval) {
                return retval == IERC721Receiver.onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert("Transfer to non ERC721Receiver");
                } else {
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        } else {
            return true;
        }
    }
}
