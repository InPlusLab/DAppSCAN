/*
    TokenLaunchManager.sol - SKALE Manager
    Copyright (C) 2019-Present SKALE Labs
    @author Dmytro Stebaiev

    SKALE Manager is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as published
    by the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    SKALE Manager is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License
    along with SKALE Manager.  If not, see <https://www.gnu.org/licenses/>.
*/

pragma solidity 0.5.16;

import "@openzeppelin/contracts/token/ERC777/IERC777.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/introspection/IERC1820Registry.sol";

import "../Permissions.sol";
import "./TokenLaunchLocker.sol";


contract TokenLaunchManager is Permissions, IERC777Recipient {
    event Approved(
        address holder,
        uint amount
    );
    event TokensRetrieved(
        address holder,
        uint amount
    );
    event SellerWasRegistered(
        address seller
    );

    IERC1820Registry private _erc1820;

    address seller;

    mapping (address => uint) approved;
    uint totalApproved;

    /// @notice Allocates values for `walletAddresses`
    function approve(address[] calldata walletAddress, uint[] calldata value) external {
        require(isOwner() || _msgSender() == seller, "Not authorized");
        require(walletAddress.length == value.length, "Wrong input arrays length");
        for (uint i = 0; i < walletAddress.length; ++i) {
            approved[walletAddress[i]] = approved[walletAddress[i]].add(value[i]);
            totalApproved = totalApproved.add(value[i]);
            emit Approved(walletAddress[i], value[i]);
        }
        require(totalApproved <= getBalance(), "Balance is too low");
    }

    /// @notice Transfers the entire value to sender address. Tokens are locked.
    function retrieve() external {
        require(approved[_msgSender()] > 0, "Transfer is not approved");
        uint value = approved[_msgSender()];
        approved[_msgSender()] = 0;
        require(IERC20(contractManager.getContract("SkaleToken")).transfer(_msgSender(), value), "Error of token sending");
        TokenLaunchLocker(contractManager.getContract("TokenLaunchLocker")).lock(_msgSender(), value);
        emit TokensRetrieved(_msgSender(), value);
    }

    function registerSeller(address _seller) external onlyOwner {
        seller = _seller;
        emit SellerWasRegistered(_seller);
    }

    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    )
        external
        allow("SkaleToken")
    {

    }

    function initialize(address _contractManager) public initializer {
        Permissions.initialize(_contractManager);
        _erc1820 = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
        _erc1820.setInterfaceImplementer(address(this), keccak256("ERC777TokensRecipient"), address(this));
    }

    // internal

    function getBalance() internal view returns(uint balance) {
        return IERC20(contractManager.getContract("SkaleToken")).balanceOf(address(this));
    }
}