// SPDX-License-Identifier: AGPL-3.0-only

/*
    SkaleManager.sol - SKALE Manager
    Copyright (C) 2018-Present SKALE Labs
    @author Artem Payvin

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
import "@openzeppelin/contracts/token/ERC777/IERC777.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";

import "@skalenetwork/skale-manager-interfaces/ISkaleManager.sol";
import "@skalenetwork/skale-manager-interfaces/IMintableToken.sol";
import "@skalenetwork/skale-manager-interfaces/delegation/IDistributor.sol";
import "@skalenetwork/skale-manager-interfaces/delegation/IValidatorService.sol";
import "@skalenetwork/skale-manager-interfaces/IBountyV2.sol";
import "@skalenetwork/skale-manager-interfaces/IConstantsHolder.sol";
import "@skalenetwork/skale-manager-interfaces/INodeRotation.sol";
import "@skalenetwork/skale-manager-interfaces/INodes.sol";
import "@skalenetwork/skale-manager-interfaces/ISchains.sol";
import "@skalenetwork/skale-manager-interfaces/ISchainsInternal.sol";
import "@skalenetwork/skale-manager-interfaces/IWallets.sol";

import "./Permissions.sol";

/**
 * @title SkaleManager
 * @dev Contract contains functions for node registration and exit, bounty
 * management, and monitoring verdicts.
 */
contract SkaleManager is IERC777Recipient, ISkaleManager, Permissions {

    IERC1820Registry private _erc1820;

    bytes32 constant private _TOKENS_RECIPIENT_INTERFACE_HASH =
        0xb281fc8c12954d22544db45de3159a39272895b169a852b314f9cc762e44c53b;

    bytes32 constant public ADMIN_ROLE = keccak256("ADMIN_ROLE");

    string public version;

    bytes32 public constant SCHAIN_REMOVAL_ROLE = keccak256("SCHAIN_REMOVAL_ROLE");

    function tokensReceived(
        address, // operator
        address from,
        address to,
        uint256 value,
        bytes calldata userData,
        bytes calldata // operator data
    )
        external
        override
        allow("SkaleToken")
    {
        require(to == address(this), "Receiver is incorrect");
        if (userData.length > 0) {
            ISchains schains = ISchains(
                contractManager.getContract("Schains"));
            schains.addSchain(from, value, userData);
        }
    }

    function createNode(
        uint16 port,
        uint16 nonce,
        bytes4 ip,
        bytes4 publicIp,
        bytes32[2] calldata publicKey,
        string calldata name,
        string calldata domainName
    )
        external
        override
    {
        INodes nodes = INodes(contractManager.getContract("Nodes"));
        // validators checks inside checkPossibilityCreatingNode
        nodes.checkPossibilityCreatingNode(msg.sender);

        INodes.NodeCreationParams memory params = INodes.NodeCreationParams({
            name: name,
            ip: ip,
            publicIp: publicIp,
            port: port,
            publicKey: publicKey,
            nonce: nonce,
            domainName: domainName
        });
        nodes.createNode(msg.sender, params);
    }

    function nodeExit(uint nodeIndex) external override {
        uint gasTotal = gasleft();
        IValidatorService validatorService = IValidatorService(contractManager.getContract("ValidatorService"));
        INodeRotation nodeRotation = INodeRotation(contractManager.getContract("NodeRotation"));
        INodes nodes = INodes(contractManager.getContract("Nodes"));
        uint validatorId = nodes.getValidatorId(nodeIndex);
        bool permitted = (_isOwner() || nodes.isNodeExist(msg.sender, nodeIndex));
        if (!permitted && validatorService.validatorAddressExists(msg.sender)) {
            permitted = validatorService.getValidatorId(msg.sender) == validatorId;
        }
        require(permitted, "Sender is not permitted to call this function");
        require(nodes.isNodeLeaving(nodeIndex), "Node should be Leaving");
        (bool completed, bool isSchains) = nodeRotation.exitFromSchain(nodeIndex);
        if (completed) {
            ISchainsInternal(
                contractManager.getContract("SchainsInternal")
            ).removeNodeFromAllExceptionSchains(nodeIndex);
            require(nodes.completeExit(nodeIndex), "Finishing of node exit is failed");
            nodes.changeNodeFinishTime(
                nodeIndex,
                block.timestamp + (
                    isSchains ?
                    IConstantsHolder(contractManager.getContract("ConstantsHolder")).rotationDelay() :
                    0
                )
            );
            nodes.deleteNodeForValidator(validatorId, nodeIndex);
        }
        _refundGasByValidator(validatorId, payable(msg.sender), gasTotal - gasleft());
    }

    function deleteSchain(string calldata name) external override {
        ISchains schains = ISchains(contractManager.getContract("Schains"));
        // schain owner checks inside deleteSchain
        schains.deleteSchain(msg.sender, name);
    }

    function deleteSchainByRoot(string calldata name) external override {
        require(hasRole(SCHAIN_REMOVAL_ROLE, msg.sender), "SCHAIN_REMOVAL_ROLE is required");
        ISchains schains = ISchains(contractManager.getContract("Schains"));
        schains.deleteSchainByRoot(name);
    }

    function getBounty(uint nodeIndex) external override {
        uint gasTotal = gasleft();
        INodes nodes = INodes(contractManager.getContract("Nodes"));
        require(nodes.isNodeExist(msg.sender, nodeIndex), "Node does not exist for Message sender");
        require(nodes.isTimeForReward(nodeIndex), "Not time for bounty");
        require(!nodes.isNodeLeft(nodeIndex), "The node must not be in Left state");
        require(!nodes.incompliant(nodeIndex), "The node is incompliant");
        IBountyV2 bountyContract = IBountyV2(contractManager.getContract("Bounty"));

        uint bounty = bountyContract.calculateBounty(nodeIndex);

        nodes.changeNodeLastRewardDate(nodeIndex);
        uint validatorId = nodes.getValidatorId(nodeIndex);
        if (bounty > 0) {
            _payBounty(bounty, validatorId);
        }

        emit BountyReceived(
            nodeIndex,
            msg.sender,
            0,
            0,
            bounty,
            type(uint).max);
        
        _refundGasByValidator(validatorId, payable(msg.sender), gasTotal - gasleft());
    }

    function setVersion(string calldata newVersion) external override onlyOwner {
        emit VersionUpdated(version, newVersion);
        version = newVersion;
    }

    function initialize(address newContractsAddress) public override initializer {
        Permissions.initialize(newContractsAddress);
        _erc1820 = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
        _erc1820.setInterfaceImplementer(address(this), _TOKENS_RECIPIENT_INTERFACE_HASH, address(this));
    }

    function _payBounty(uint bounty, uint validatorId) private {
        IERC777 skaleToken = IERC777(contractManager.getContract("SkaleToken"));
        IDistributor distributor = IDistributor(contractManager.getContract("Distributor"));
        
        require(
            IMintableToken(address(skaleToken)).mint(address(distributor), bounty, abi.encode(validatorId), ""),
            "Token was not minted"
        );
    }

    function _refundGasByValidator(uint validatorId, address payable spender, uint spentGas) private {
        uint gasCostOfRefundGasByValidator = 55723;
        IWallets(payable(contractManager.getContract("Wallets")))
        .refundGasByValidator(validatorId, spender, spentGas + gasCostOfRefundGasByValidator);
    }
}
