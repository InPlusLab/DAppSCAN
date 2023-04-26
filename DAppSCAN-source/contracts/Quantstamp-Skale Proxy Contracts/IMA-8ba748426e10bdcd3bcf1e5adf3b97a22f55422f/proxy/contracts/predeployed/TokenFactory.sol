// SPDX-License-Identifier: AGPL-3.0-only

/**
 *   TokenFactory.sol - SKALE Interchain Messaging Agent
 *   Copyright (C) 2019-Present SKALE Labs
 *   @author Artem Payvin
 *
 *   SKALE IMA is free software: you can redistribute it and/or modify
 *   it under the terms of the GNU Affero General Public License as published
 *   by the Free Software Foundation, either version 3 of the License, or
 *   (at your option) any later version.
 *
 *   SKALE IMA is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *   GNU Affero General Public License for more details.
 *
 *   You should have received a copy of the GNU Affero General Public License
 *   along with SKALE IMA.  If not, see <https://www.gnu.org/licenses/>.
 */

pragma solidity 0.6.12;

import "./PermissionsForSchain.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20Burnable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC721/ERC721Burnable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/access/AccessControl.sol";


contract ERC20OnChain is AccessControlUpgradeSafe, ERC20BurnableUpgradeSafe {

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    uint256 private _totalSupplyOnMainnet;
    address private _addressOfErc20Module;

    constructor(
        string memory contractName,
        string memory contractSymbol,
        uint256 newTotalSupply,
        address erc20Module
        )
        public
    {
        __ERC20_init(contractName, contractSymbol);
        _totalSupplyOnMainnet = newTotalSupply;
        _addressOfErc20Module = erc20Module;
        _setRoleAdmin(MINTER_ROLE, MINTER_ROLE);
        _setupRole(MINTER_ROLE, _msgSender());
    }

    function setTotalSupplyOnMainnet(uint256 newTotalSupply) external {
        require(_addressOfErc20Module == _msgSender(), "Caller is not ERC20Module");
        _totalSupplyOnMainnet = newTotalSupply;
    }

    function totalSupplyOnMainnet() external view returns (uint256) {
        return _totalSupplyOnMainnet;
    }

    function mint(address account, uint256 value) public {
        require(totalSupply().add(value) <= _totalSupplyOnMainnet, "Total supply exceeded");
        require(hasRole(MINTER_ROLE, _msgSender()), "Sender is not a Minter");
        _mint(account, value);
    }
}


contract ERC721OnChain is AccessControlUpgradeSafe, ERC721BurnableUpgradeSafe {

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor(
        string memory contractName,
        string memory contractSymbol
    )
        public
    {
        __ERC721_init(contractName, contractSymbol);
        _setRoleAdmin(MINTER_ROLE, MINTER_ROLE);
        _setupRole(MINTER_ROLE, _msgSender());
    }

    function mint(address to, uint256 tokenId)
        external
        returns (bool)
    {
        require(hasRole(MINTER_ROLE, _msgSender()), "Sender is not a Minter");
        _mint(to, tokenId);
        return true;
    }

    function setTokenURI(uint256 tokenId, string calldata tokenUri)
        external
        returns (bool)
    {
        require(_exists(tokenId), "Token does not exists");
        require(_isApprovedOrOwner(msg.sender, tokenId), "Sender can not set token URI");
        _setTokenURI(tokenId, tokenUri);
        return true;
    }
}


contract TokenFactory is PermissionsForSchain {

    constructor(address _lockAndDataAddress) public PermissionsForSchain(_lockAndDataAddress) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function createERC20(string memory name, string memory symbol, uint256 totalSupply)
        external
        allow("ERC20Module")
        returns (address)
    {
        address erc20ModuleAddress = IContractManagerForSchain(
            getLockAndDataAddress()
        ).permitted(keccak256(abi.encodePacked("ERC20Module")));
        ERC20OnChain newERC20 = new ERC20OnChain(
            name,
            symbol,
            totalSupply,
            erc20ModuleAddress
        );
        address lockAndDataERC20 = IContractManagerForSchain(
            getLockAndDataAddress()
        ).permitted(keccak256(abi.encodePacked("LockAndDataERC20")));
        newERC20.grantRole(newERC20.MINTER_ROLE(), lockAndDataERC20);
        newERC20.revokeRole(newERC20.MINTER_ROLE(), address(this));
        return address(newERC20);
    }

    function createERC721(string memory name, string memory symbol)
        external
        allow("ERC721Module")
        returns (address)
    {
        ERC721OnChain newERC721 = new ERC721OnChain(name, symbol);
        address lockAndDataERC721 = IContractManagerForSchain(getLockAndDataAddress()).
            permitted(keccak256(abi.encodePacked("LockAndDataERC721")));
        newERC721.grantRole(newERC721.MINTER_ROLE(), lockAndDataERC721);
        newERC721.revokeRole(newERC721.MINTER_ROLE(), address(this));
        return address(newERC721);
    }
}