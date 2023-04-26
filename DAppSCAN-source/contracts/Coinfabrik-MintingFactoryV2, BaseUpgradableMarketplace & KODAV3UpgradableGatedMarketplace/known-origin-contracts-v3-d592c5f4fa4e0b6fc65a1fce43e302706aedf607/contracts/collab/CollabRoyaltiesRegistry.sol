// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {ERC165Storage} from "@openzeppelin/contracts/utils/introspection/ERC165Storage.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IKODAV3} from "../core/IKODAV3.sol";
import {Konstants} from "../core/Konstants.sol";
import {IERC2981} from "../core/IERC2981.sol";
import {IKOAccessControlsLookup} from "../access/IKOAccessControlsLookup.sol";
import {ICollabRoyaltiesRegistry} from "./ICollabRoyaltiesRegistry.sol";
import {ICollabFundsHandler} from "./handlers/ICollabFundsHandler.sol";

contract CollabRoyaltiesRegistry is Pausable, Konstants, ERC165Storage, IERC2981, ICollabRoyaltiesRegistry {

    // Admin Events
    event KODASet(address koda);
    event AccessControlsSet(address accessControls);
    event RoyaltyAmountSet(uint256 royaltyAmount);
    event EmergencyClearRoyalty(uint256 editionId);
    event HandlerAdded(address handler);
    event HandlerRemoved(address handler);

    // Normal Events
    event RoyaltyRecipientCreated(address creator, address handler, address deployedHandler, address[] recipients, uint256[] splits);
    event RoyaltiesHandlerSetup(uint256 editionId, address deployedHandler);
    event FutureRoyaltiesHandlerSetup(uint256 editionId, address deployedHandler);

    IKODAV3 public koda;

    IKOAccessControlsLookup public accessControls;

    // @notice A controlled list of proxies which can be used byt eh KO protocol
    mapping(address => bool) public isHandlerWhitelisted;

    // @notice A list of initialised/deployed royalties recipients
    mapping(address => bool) public deployedRoyaltiesHandlers;

    /// @notice Funds handler to edition ID mapping - once set all funds are sent here on every sale, including EIP-2981 invocations
    mapping(uint256 => address) public editionRoyaltiesHandlers;

    /// @notice KO secondary sale royalty amount
    uint256 public royaltyAmount = 12_50000; // 12.5% as represented in eip-2981

    /// @notice precision 100.00000%
    uint256 public modulo = 100_00000;

    modifier onlyContractOrCreator(uint256 _editionId) {
        require(
            koda.getCreatorOfEdition(_editionId) == _msgSender() || accessControls.hasContractRole(_msgSender()),
            "Caller not creator or contract"
        );
        _;
    }

    modifier onlyContractOrAdmin() {
        require(
            accessControls.hasAdminRole(_msgSender()) || accessControls.hasContractRole(_msgSender()),
            "Caller not admin or contract"
        );
        _;
    }

    modifier onlyAdmin() {
        require(accessControls.hasAdminRole(_msgSender()), "Caller not admin");
        _;
    }

    constructor(IKOAccessControlsLookup _accessControls) {
        accessControls = _accessControls;

        // _INTERFACE_ID_ERC2981
        _registerInterface(0x2a55205a);
    }

    /// @notice Set the IKODAV3 dependency - can't be passed to constructor due to circular dependency
    function setKoda(IKODAV3 _koda)
    external
    onlyAdmin {
        koda = _koda;
        emit KODASet(address(koda));
    }

    /// @notice Set the IKOAccessControlsLookup dependency.
    function setAccessControls(IKOAccessControlsLookup _accessControls)
    external
    onlyAdmin {
        accessControls = _accessControls;
        emit AccessControlsSet(address(accessControls));
    }

    /// @notice Admin setter for changing the default royalty amount
    function setRoyaltyAmount(uint256 _amount)
    external
    onlyAdmin() {
        require(_amount > 1, "Amount to low");
        royaltyAmount = _amount;
        emit RoyaltyAmountSet(royaltyAmount);
    }

    /// @notice Add a new cloneable funds handler
    function addHandler(address _handler)
    external
    onlyAdmin() {

        // Revert if handler already whitelisted
        require(isHandlerWhitelisted[_handler] == false, "Handler already registered");

        // whitelist handler
        isHandlerWhitelisted[_handler] = true;

        // Emit event
        emit HandlerAdded(_handler);
    }

    /// @notice Remove a cloneable funds handler
    function removeHandler(address _handler)
    external
    onlyAdmin() {
        // remove handler from whitelist
        isHandlerWhitelisted[_handler] = false;

        // Emit event
        emit HandlerRemoved(_handler);
    }

    ////////////////////////////
    /// Royalties setup logic //
    ////////////////////////////

    /// @notice Sets up a royalties funds handler
    /// @dev Can only be called once with the same args as this creates a new contract and we dont want to
    ///      override any currently deployed instance
    /// @dev Can only be called by an approved artist
    function createRoyaltiesRecipient(
        address _handler,
        address[] calldata _recipients,
        uint256[] calldata _splits
    )
    external
    override
    whenNotPaused
    returns (address deployedHandler) {
        validateHandlerArgs(_handler, _recipients, _splits);

        // Clone funds handler as Minimal deployedHandler with a deterministic address
        deployedHandler = deployCloneableHandler(_handler, _recipients, _splits);

        // Emit event
        emit RoyaltyRecipientCreated(_msgSender(), _handler, deployedHandler, _recipients, _splits);
    }

    /// @notice Allows a deployed handler to be set against an edition
    /// @dev Can be called by edition creator or another approved contract
    /// @dev Can only be called once per edition
    /// @dev Provided handler account must already be deployed
    function useRoyaltiesRecipient(uint256 _editionId, address _deployedHandler)
    external
    override
    whenNotPaused
    onlyContractOrCreator(_editionId) {
        // Ensure not already defined i.e. dont overwrite deployed contact
        require(editionRoyaltiesHandlers[_editionId] == address(0), "Funds handler already registered");

        // Ensure there actually was a registration
        require(deployedRoyaltiesHandlers[_deployedHandler], "No deployed handler found");

        // Register the deployed handler for the edition ID
        editionRoyaltiesHandlers[_editionId] = _deployedHandler;

        // Emit event
        emit RoyaltiesHandlerSetup(_editionId, _deployedHandler);
    }

    /// @notice Allows an admin set a predetermined royalties recipient against an edition
    /// @dev assumes the called has provided the correct args and a valid edition
    function usePredeterminedRoyaltiesRecipient(
        uint256 _editionId,
        address _handler,
        address[] calldata _recipients,
        uint256[] calldata _splits
    )
    external
    override
    whenNotPaused
    onlyContractOrAdmin {
        // Ensure not already defined i.e. dont overwrite deployed contact
        require(editionRoyaltiesHandlers[_editionId] == address(0), "Funds handler already registered");

        // Determine salt
        bytes32 salt = keccak256(abi.encode(_recipients, _splits));
        address futureDeployedHandler = Clones.predictDeterministicAddress(_handler, salt);

        // Register the same proxy for the new edition id
        editionRoyaltiesHandlers[_editionId] = futureDeployedHandler;

        // Emit event
        emit FutureRoyaltiesHandlerSetup(_editionId, futureDeployedHandler);
    }

    function createAndUseRoyaltiesRecipient(
        uint256 _editionId,
        address _handler,
        address[] calldata _recipients,
        uint256[] calldata _splits
    )
    external
    override
    whenNotPaused
    onlyContractOrAdmin
    returns (address deployedHandler) {
        validateHandlerArgs(_handler, _recipients, _splits);

        // Confirm the handler has not already been created
        address expectedAddress = Clones.predictDeterministicAddress(_handler, keccak256(abi.encode(_recipients, _splits)));
        require(!deployedRoyaltiesHandlers[expectedAddress], "Already deployed the royalties handler");

        // Clone funds handler as Minimal deployedHandler with a deterministic address
        deployedHandler = deployCloneableHandler(_handler, _recipients, _splits);

        // Emit event
        emit RoyaltyRecipientCreated(_msgSender(), _handler, deployedHandler, _recipients, _splits);

        // Register the deployed handler for the edition ID
        editionRoyaltiesHandlers[_editionId] = deployedHandler;

        // Emit event
        emit RoyaltiesHandlerSetup(_editionId, deployedHandler);
    }

    function deployCloneableHandler(address _handler, address[] calldata _recipients, uint256[] calldata _splits)
    internal
    returns (address deployedHandler) {
        // Confirm the handler has not already been created
        address expectedAddress = Clones.predictDeterministicAddress(_handler, keccak256(abi.encode(_recipients, _splits)));
        require(!deployedRoyaltiesHandlers[expectedAddress], "Already deployed the royalties handler");

        // Clone funds handler as Minimal deployedHandler with a deterministic address
        deployedHandler = Clones.cloneDeterministic(
            _handler,
            keccak256(abi.encode(_recipients, _splits))
        );

        // Initialize handler
        ICollabFundsHandler(deployedHandler).init(_recipients, _splits);

        // Verify that it was initialized properly
        require(
            ICollabFundsHandler(deployedHandler).totalRecipients() == _recipients.length,
            "Funds handler created incorrectly"
        );

        // Record the deployed handler
        deployedRoyaltiesHandlers[deployedHandler] = true;
    }

    function validateHandlerArgs(address _handler, address[] calldata _recipients, uint256[] calldata _splits)
    internal view {
        // Require more than 1 recipient
        require(_recipients.length > 1, "Collab must have more than one funds recipient");

        // Recipient and splits array lengths must match
        require(_recipients.length == _splits.length, "Recipients and splits lengths must match");

        // Ensure the handler is know and approved
        require(isHandlerWhitelisted[_handler], "Handler is not whitelisted");
    }

    /// @notice Allows for the royalty creator to predetermine the recipient address for the funds to be sent to
    /// @dev It does not deploy it, only allows to predetermine the address
    function predictedRoyaltiesHandler(address _handler, address[] calldata _recipients, uint256[] calldata _splits)
    public
    override
    view
    returns (address) {
        bytes32 salt = keccak256(abi.encode(_recipients, _splits));
        return Clones.predictDeterministicAddress(_handler, salt);
    }

    /// @notice ability to clear royalty in an emergency situation - this would then default all royalties to the original creator
    /// @dev Only callable from admin
    function emergencyResetRoyaltiesHandler(uint256 _editionId) public onlyAdmin {
        editionRoyaltiesHandlers[_editionId] = address(0);
        emit EmergencyClearRoyalty(_editionId);
    }

    ////////////////////
    /// Query Methods //
    ////////////////////

    /// @notice Is the given token part of an edition that has a collab royalties contract setup?
    function hasRoyalties(uint256 _tokenId)
    external
    override
    view returns (bool) {

        // Get the associated edition id for the given token id
        uint256 editionId = _editionFromTokenId(_tokenId);

        // Get the proxy registered to the previous edition id
        address proxy = editionRoyaltiesHandlers[editionId];

        // Ensure there actually was a registration
        return proxy != address(0);
    }

    /// @notice Get the proxy for a given edition's funds handler
    function getRoyaltiesReceiver(uint256 _editionId)
    external
    override
    view returns (address _receiver) {
        _receiver = editionRoyaltiesHandlers[_editionId];
        require(_receiver != address(0), "Edition not setup");
    }

    /// @notice Gets the funds handler proxy address and royalty amount for given edition id
    function royaltyInfo(uint256 _editionId, uint256 _value)
    external
    override
    view returns (address _receiver, uint256 _royaltyAmount) {
        _receiver = editionRoyaltiesHandlers[_editionId];
        require(_receiver != address(0), "Edition not setup");
        _royaltyAmount = (_value / modulo) * royaltyAmount;
    }

}
