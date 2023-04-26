// SPDX-License-Identifier: AGPL-3.0-only

/*
    SkaleTokenInternalTester.sol - SKALE SAFT Core
    Copyright (C) 2018-Present SKALE Labs
    @author Dmytro Stebaiev

    SKALE SAFT Core is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as published
    by the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    SKALE SAFT Core is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License
    along with SKALE SAFT Core.  If not, see <https://www.gnu.org/licenses/>.
*/

pragma solidity 0.6.10;

import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC777/ERC777.sol";

import "../Permissions.sol";
import "../interfaces/delegation/IDelegatableToken.sol";
import "../SAFT.sol";

contract SkaleTokenTester is ERC777UpgradeSafe, Permissions, IDelegatableToken {

    uint public constant CAP = 7 * 1e9 * (10 ** 18); // the maximum amount of tokens that can ever be created

    constructor(
        address contractManagerAddress,
        string memory name,
        string memory symbol,
        address[] memory defOp
    )
        public
    {
        ERC777UpgradeSafe.__ERC777_init(name, symbol, defOp);
        Permissions.initialize(contractManagerAddress);
    }

    function mint(
        address account,
        uint amount,
        bytes memory userData,
        bytes memory operatorData
    )
        external
        onlyOwner
        returns (bool)
    {
        require(amount <= CAP.sub(totalSupply()), "Amount is too big");
        _mint(
            account,
            amount,
            userData,
            operatorData
        );

        return true;
    }

    function getAndUpdateDelegatedAmount(address) external override returns (uint) {
        return 0;
    }

    function getAndUpdateSlashedAmount(address) external override returns (uint) {
        return 0;
    }

    function getAndUpdateLockedAmount(address wallet) public override returns (uint) {
        return SAFT(contractManager.getContract("TokenState")).getAndUpdateLockedAmount(wallet);
    }

    function _beforeTokenTransfer(
        address, // operator
        address from,
        address, // to
        uint256 tokenId)
        internal override
    {
        uint locked = getAndUpdateLockedAmount(from);
        if (locked > 0) {
            require(balanceOf(from) >= locked.add(tokenId), "Token should be unlocked for transferring");
        }
    }
}
