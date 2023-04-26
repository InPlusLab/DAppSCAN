// SPDX-License-Identifier: AGPL-3.0-only

/*
    CoreEscrow.sol - SKALE SAFT Core
    Copyright (C) 2020-Present SKALE Labs
    @author Artem Payvin

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
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-ethereum-package/contracts/introspection/IERC1820Registry.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC777/IERC777Sender.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import "./interfaces/delegation/ILocker.sol";
import "./Core.sol";
import "./Permissions.sol";
import "./interfaces/delegation/IDelegationController.sol";
import "./interfaces/delegation/IDistributor.sol";
import "./interfaces/delegation/ITokenState.sol";
import "./interfaces/delegation/IValidatorService.sol";

/**
 * @title Core Escrow
 * @dev This contract manages Core escrow operations for the SKALE Employee
 * Token Open Plan.
 */
contract CoreEscrow is IERC777Recipient, IERC777Sender, Permissions {

    address private _holder;

    uint private _availableAmountAfterTermination;

    IERC1820Registry private _erc1820;

    modifier onlyHolder() {
        require(_msgSender() == _holder, "Message sender is not a holder");
        _;
    }

    modifier onlyHolderAndOwner() {
        Core core = Core(contractManager.getContract("Core"));
        require(
            _msgSender() == _holder && core.isActiveVestingTerm(_holder) || _msgSender() == core.vestingManager(),
            "Message sender is not authorized"
        );
        _;
    }   

    function initialize(address contractManagerAddress, address newHolder) external initializer {
        Permissions.initialize(contractManagerAddress);
        _holder = newHolder;
        _erc1820 = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
        _erc1820.setInterfaceImplementer(address(this), keccak256("ERC777TokensRecipient"), address(this));
        _erc1820.setInterfaceImplementer(address(this), keccak256("ERC777TokensSender"), address(this));
    } 

    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    )
        external override
        allow("SkaleToken")
        // solhint-disable-next-line no-empty-blocks
    {

    }

    function tokensToSend(
        address,
        address,
        address to,
        uint256,
        bytes calldata,
        bytes calldata
    )
        external override
        allow("SkaleToken")
    {
        require(to == _holder || hasRole(DEFAULT_ADMIN_ROLE, to), "Not authorized transfer");
    }

    /**
     * @dev Allows Holder to retrieve locked tokens from SKALE Token to the Core
     * Escrow contract.
     */
    function retrieve() external onlyHolder {
        Core core = Core(contractManager.getContract("Core"));
        ITokenState tokenState = ITokenState(contractManager.getContract("TokenState"));
        // require(core.isActiveVestingTerm(_holder), "Core term is not Active");
        uint vestedAmount = 0;
        if (core.isActiveVestingTerm(_holder)) {
            vestedAmount = core.calculateVestedAmount(_holder);
        } else {
            vestedAmount = _availableAmountAfterTermination;
        }
        uint escrowBalance = IERC20(contractManager.getContract("SkaleToken")).balanceOf(address(this));
        uint fullAmount = core.getFullAmount(_holder);
        uint forbiddenToSend = tokenState.getAndUpdateForbiddenForDelegationAmount(address(this));
        if (vestedAmount > fullAmount.sub(escrowBalance)) {
            if (vestedAmount.sub(fullAmount.sub(escrowBalance)) > forbiddenToSend)
            require(
                IERC20(contractManager.getContract("SkaleToken")).transfer(
                    _holder,
                    vestedAmount
                        .sub(
                            fullAmount
                                .sub(escrowBalance)
                            )
                        .sub(forbiddenToSend)
                ),
                "Error of token send"
            );
        }
    }

    /**
     * @dev Allows Core Owner to retrieve remaining transferrable escrow balance
     * after Core holder termination. Slashed tokens are non-transferable.
     *
     * Requirements:
     *
     * - Core must be active.
     */
    function retrieveAfterTermination() external onlyOwner {
        Core core = Core(contractManager.getContract("Core"));
        ITokenState tokenState = ITokenState(contractManager.getContract("TokenState"));

        require(!core.isActiveVestingTerm(_holder), "Core holder is not Active");
        uint escrowBalance = IERC20(contractManager.getContract("SkaleToken")).balanceOf(address(this));
        uint forbiddenToSend = tokenState.getAndUpdateLockedAmount(address(this));
        if (escrowBalance > forbiddenToSend) {
            require(
                IERC20(contractManager.getContract("SkaleToken")).transfer(
                    address(_getCoreContract()),
                    escrowBalance.sub(forbiddenToSend)
                ),
                "Error of token send"
            );
        }
    }

    /**
     * @dev Allows Core holder to propose a delegation to a validator.
     *
     * Requirements:
     *
     * - Core holder must be active.
     * - Holder has sufficient delegatable tokens.
     * - If trusted list is enabled, validator must be a member of this trusted
     * list.
     */
    function delegate(
        uint validatorId,
        uint amount,
        uint delegationPeriod,
        string calldata info
    )
        external
        onlyHolder
    {
        Core core = Core(contractManager.getContract("Core"));
        require(core.isActiveVestingTerm(_holder), "Core holder is not Active");        
        if (!core.isUnvestedDelegatableTerm(_holder)) {
            require(core.calculateVestedAmount(_holder) >= amount, "Incorrect amount to delegate");
        }
        
        IDelegationController delegationController = IDelegationController(
            contractManager.getContract("DelegationController")
        );
        delegationController.delegate(validatorId, amount, delegationPeriod, info);
    }

    /**
     * @dev Allows Holder and Owner to request undelegation. Only Owner can
     * request undelegation after Core holder is deactivated (upon holder
     * termination).
     *
     * Requirements:
     *
     * - Holder or Core Owner must be `msg.sender`.
     * - Core holder must be active when Holder is `msg.sender`.
     */
    function requestUndelegation(uint delegationId) external onlyHolderAndOwner {
        Core core = Core(contractManager.getContract("Core"));
        require(
            _msgSender() == _holder && core.isActiveVestingTerm(_holder) || _msgSender() == core.vestingManager(),
            "Message sender is not authorized"
        );
        if (_msgSender() == _holder) {
            require(core.isActiveVestingTerm(_holder), "Core holder is not Active");
        }
        IDelegationController delegationController = IDelegationController(
            contractManager.getContract("DelegationController")
        );
        delegationController.requestUndelegation(delegationId);
    }

    /**
     * @dev Allows Holder and Owner to withdraw earned bounty. Only Owner can
     * withdraw bounty to Core contract after Core holder is deactivated.
     *
     * Requirements:
     *
     * - Holder or Core Owner must be `msg.sender`.
     * - Core must be active when Holder is `msg.sender`.
     */
    function withdrawBounty(uint validatorId, address to) external onlyHolderAndOwner {        
        IDistributor distributor = IDistributor(contractManager.getContract("Distributor"));
        if (_msgSender() == _holder) {
            Core core = Core(contractManager.getContract("Core"));
            require(core.isActiveVestingTerm(_holder), "Core holder is not Active");            
            distributor.withdrawBounty(validatorId, to);
        } else {            
            distributor.withdrawBounty(validatorId, address(_getCoreContract()));
        }
    }

    /**
     * @dev Allows Core contract to cancel vesting of an Core holder. Cancel
     * vesting is performed upon termination.
     * TODO: missing moving Core holder to deactivated state?
     */
    function cancelVesting(uint vestedAmount) external allow("Core") {
        _availableAmountAfterTermination = vestedAmount;
    }

    // private

    function _getCoreContract() internal view returns (Core) {
        return Core(contractManager.getContract("Core"));
    }
}