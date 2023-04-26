// SPDX-License-Identifier: AGPL-3.0-only

/*
    ReentrancyTester.sol - SKALE Manager
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

pragma solidity 0.8.11;

import "@openzeppelin/contracts/utils/introspection/IERC1820Registry.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Sender.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777.sol";

import "../Permissions.sol";
import "../delegation/DelegationController.sol";

interface IReentrancyTester {
    function prepareToReentrancyCheck() external;
    function prepareToBurningAttack() external;
    function burningAttack() external;
}


contract ReentrancyTester is Permissions, IERC777Recipient, IERC777Sender, IReentrancyTester {

    IERC1820Registry private _erc1820 = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
    bool private _reentrancyCheck = false;
    bool private _burningAttack = false;
    uint private _amount = 0;

    constructor (address contractManagerAddress) {
        Permissions.initialize(contractManagerAddress);
        _erc1820.setInterfaceImplementer(address(this), keccak256("ERC777TokensRecipient"), address(this));
        _erc1820.setInterfaceImplementer(address(this), keccak256("ERC777TokensSender"), address(this));
    }

    function tokensReceived(
        address /* operator */,
        address /* from */,
        address /* to */,
        uint256 amount,
        bytes calldata /* userData */,
        bytes calldata /* operatorData */
    )
        external override
    {
        if (_reentrancyCheck) {
            IERC20 skaleToken = IERC20(contractManager.getContract("SkaleToken"));

            require(
                skaleToken.transfer(contractManager.getContract("SkaleToken"), amount),
                "Transfer is not successful");
        }
    }

    function tokensToSend(
        address, // operator
        address, // from
        address, // to
        uint256, // amount
        bytes calldata, // userData
        bytes calldata // operatorData
    ) external override
    {
        if (_burningAttack) {
            DelegationController delegationController = DelegationController(
                contractManager.getContract("DelegationController"));
            delegationController.delegate(
                1,
                _amount,
                2,
                "D2 is even");
        }
    }

    function prepareToReentrancyCheck() external override {
        _reentrancyCheck = true;
    }

    function prepareToBurningAttack() external override {
        _burningAttack = true;
    }

    function burningAttack() external override {
        IERC777 skaleToken = IERC777(contractManager.getContract("SkaleToken"));

        _amount = skaleToken.balanceOf(address(this));

        skaleToken.burn(_amount, "");
    }
}
