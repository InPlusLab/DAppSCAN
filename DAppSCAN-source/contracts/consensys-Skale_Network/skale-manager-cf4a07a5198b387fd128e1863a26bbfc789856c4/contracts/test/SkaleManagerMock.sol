// SPDX-License-Identifier: AGPL-3.0-only

/*
    SkaleManagerMock.sol - SKALE Manager
    Copyright (C) 2018-Present SKALE Labs
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

pragma solidity 0.6.10;

import "@openzeppelin/contracts-ethereum-package/contracts/introspection/IERC1820Registry.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC777/IERC777.sol";

import "../interfaces/IMintableToken.sol";
import "../Permissions.sol";


contract SkaleManagerMock is Permissions, IERC777Recipient {

    IERC1820Registry private _erc1820 = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);

    bytes32 constant public ADMIN_ROLE = keccak256("ADMIN_ROLE");

    constructor (address contractManagerAddress) public {
        Permissions.initialize(contractManagerAddress);
        _erc1820.setInterfaceImplementer(address(this), keccak256("ERC777TokensRecipient"), address(this));
    }

    function payBounty(uint validatorId, uint amount) external {
        IERC777 skaleToken = IERC777(contractManager.getContract("SkaleToken"));
        require(IMintableToken(address(skaleToken)).mint(address(this), amount, "", ""), "Token was not minted");
        require(
            IMintableToken(address(skaleToken))
                .mint(contractManager.getContract("Distributor"), amount, abi.encode(validatorId), ""),
            "Token was not minted"
        );
    }

    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    )
        external override allow("SkaleToken")
        // solhint-disable-next-line no-empty-blocks
    {
        
    }
}
