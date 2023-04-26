/*
    SkaleBalances.sol - SKALE Manager
    Copyright (C) 2018-Present SKALE Labs
    @author Vadim Yavorsky
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

pragma solidity ^0.5.3;

import "@openzeppelin/contracts/introspection/IERC1820Registry.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";

import "../Permissions.sol";
import "../SkaleToken.sol";
import "../interfaces/ISkaleToken.sol";


contract SkaleBalances is Permissions, IERC777Recipient {
    IERC1820Registry private _erc1820 = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
    mapping (address => uint) private _bountyBalances;
    //        wallet => timestamp
    mapping (address => uint) private _timeLimit;
    bool private _lockBounty = true;

    constructor(address newContractsAddress) Permissions(newContractsAddress) public {
        _erc1820.setInterfaceImplementer(address(this), keccak256("ERC777TokensRecipient"), address(this));
    }

    function withdrawBalance(address from, address to, uint amountOfTokens) external allow("DelegationService") {
        if (_timeLimit[from] != 0) {
            require(_timeLimit[from] <= now, "Bounty is locked");
            _timeLimit[from] = 0;
        }

        require(_bountyBalances[from] >= amountOfTokens, "Now enough tokens on balance for withdrawing");
        _bountyBalances[from] -= amountOfTokens;

        SkaleToken skaleToken = SkaleToken(contractManager.getContract("SkaleToken"));
        require(skaleToken.transfer(to, amountOfTokens), "Failed to transfer tokens");
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
        address recipient = abi.decode(userData, (address));
        stashBalance(recipient, amount);
    }

    function getBalance(address wallet) external view allow("DelegationService") returns (uint) {
        return _bountyBalances[wallet];
    }

    function setLockBounty(bool lock) external onlyOwner() {
        _lockBounty = lock;
    }

    function lockBounty(address wallet, uint timeLimit) external allow("DelegationService") {
        if (_lockBounty) {
            if (_timeLimit[wallet] == 0 || _timeLimit[wallet] > timeLimit) {
                _timeLimit[wallet] = timeLimit;
            }
        }
    }

    // private

    function stashBalance(address recipient, uint amount) internal {
        _bountyBalances[recipient] += amount;
    }
}
