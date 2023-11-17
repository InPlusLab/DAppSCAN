// SPDX-License-Identifier: MIT

pragma solidity 0.6.9;
// SWC-102-Outdated Compiler Version: L3
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./erc1820/ERC1820Client.sol";
import "./erc1820/ERC1820Implementer.sol";

import "./extensions/IAmpTokensSender.sol";
import "./extensions/IAmpTokensRecipient.sol";

import "./partitions/IAmpPartitionStrategyValidator.sol";
import "./partitions/PartitionsBase.sol";

import "./codes/ErrorCodes.sol";


interface ISwapToken {
    function allowance(address owner, address spender)
        external
        view
        returns (uint256 remaining);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool success);
}


/**
 * @title Amp
 * @notice Amp is an ERC20 compatible collateral token designed to support
 * multiple classes of collateralization systems.
 * @dev The Amp token contract includes the following features:
 *
 * Partitions
 *   Tokens can be segmented within a given address by "partition", which in
 *   pracice is a 32 byte identifier. These partitions can have unique
 *   permissions globally, through the using of partition strategies, and
 *   locally, on a per address basis. The ability to create the sub-segments
 *   of tokens and assign special behavior gives collateral managers
 *   flexibility in how they are implemented.
 *
 * Operators
 *   Inspired by ERC777, Amp allows token holders to assign "operators" on
 *   all (or any number of partitions) of their tokens. Operators are allowed
 *   to execute transfers on behalf of token owners without the need to use the
 *   ERC20 "allowance" semantics.
 *
 * Transfers with Data
 *   Inspired by ERC777, Amp transfers can include arbitrary data, as well as
 *   operator data. This data can be used to change the partition of tokens,
 *   be used by collateral manager hooks to validate a transfer, be propagated
 *   via event to an off chain system, etc.
 *
 * Token Transfer Hooks on Send and Receive
 *   Inspired by ERC777, Amp uses the ERC1820 Registry to allow collateral
 *   manager implementations to register hooks to be called upon sending to
 *   or transferring from the collateral manager's address or, using partition
 *   strategies, owned partition space. The hook implementations can be used
 *   to validate transfer properties, gate transfers, emit custom events,
 *   update local state, etc.
 *
 * Collateral Management Partition Strategies
 *   Amp is able to define certain sets of partitions, identified by a 4 byte
 *   prefix, that will allow special, custom logic to be executed when transfers
 *   are made to or from those partitions. This opens up the possibility of
 *   entire classes of collateral management systems that would not be possible
 *   without it.
 *
 * These features give collateral manager implementers flexibility while
 * providing a consistent, "collateral-in-place", interface for interacting
 * with collateral systems directly through the Amp contract.
 */
contract Amp is
    IERC20,
    ERC1820Client,
    ERC1820Implementer,
    PartitionsBase,
    ErrorCodes,
    Ownable
{
    using SafeMath for uint256;

    /**************************************************************************/
    /********************** ERC1820 Interface Constants ***********************/

    /**
     * @dev AmpToken interface label.
     */
    string internal constant AMP_INTERFACE_NAME = "AmpToken";

    /**
     * @dev ERC20Token interface label.
     */
    string internal constant ERC20_INTERFACE_NAME = "ERC20Token";

    /**
     * @dev ERC777Token interface label.
     */
    string internal constant ERC777_INTERFACE_NAME = "ERC777Token";

    /**
     * @dev AmpTokensSender interface label.
     */
    string internal constant AMP_TOKENS_SENDER = "AmpTokensSender";

    /**
     * @dev AmpTokensRecipient interface label.
     */
    string internal constant AMP_TOKENS_RECIPIENT = "AmpTokensRecipient";

    /**
     * @dev AmpTokensChecker interface label.
     */
    string internal constant AMP_TOKENS_CHECKER = "AmpTokensChecker";

    /**************************************************************************/
    /*************************** Token properties *****************************/

    /**
     * @dev Token name (Amp).
     */
    string internal _name;

    /**
     * @dev Token symbol (AMP).
     */
    string internal _symbol;

    /**
     * @dev Total minted supply of token. This will increase comensurately with
     * successful swaps of the swap token.
     */
    uint256 internal _totalSupply;

    /**
     * @dev The granularity of the token. Hard coded to 1.
     */
    uint256 internal constant _granularity = 1;

    /**************************************************************************/
    /***************************** Token mappings *****************************/

    /**
     * @dev Mapping from tokenHolder to balance.
     */
    mapping(address => uint256) internal _balances;

    /**
     * @dev Mapping from (tokenHolder, spender) to allowed value.
     */
    mapping(address => mapping(address => uint256)) internal _allowed;

    /**************************************************************************/
    /************************** Partition mappings ****************************/

    /**
     * @dev List of active partitions. This list reflects all partitions that
     * have tokens assigned to them.
     */
    bytes32[] internal _totalPartitions;

    /**
     * @dev Mapping from partition to their index.
     */
    mapping(bytes32 => uint256) internal _indexOfTotalPartitions;

    /**
     * @dev Mapping from partition to global balance of corresponding partition.
     */
    mapping(bytes32 => uint256) public totalSupplyByPartition;

    /**
     * @dev Mapping from tokenHolder to their partitions.
     */
    mapping(address => bytes32[]) internal _partitionsOf;

    /**
     * @dev Mapping from (tokenHolder, partition) to their index.
     */
    mapping(address => mapping(bytes32 => uint256)) internal _indexOfPartitionsOf;

    /**
     * @dev Mapping from (tokenHolder, partition) to balance of corresponding
     * partition.
     */
    mapping(address => mapping(bytes32 => uint256)) internal _balanceOfByPartition;

    /**
     * @notice Default partition of the token.
     * @dev All ERC20 operations operate solely on this partition.
     */
    bytes32 public constant defaultPartition = 0x0000000000000000000000000000000000000000000000000000000000000000;

    /**
     * @dev Zero partition prefix. Parititions with this prefix can not have a strategy assigned,
     * and partitions with a different prefix must have one.
     */
    bytes4 internal constant ZERO_PREFIX = 0x00000000;

    /**************************************************************************/
    /***************************** Operator mappings **************************/

    /**
     * @dev Mapping from (tokenHolder, operator) to authorized status. This is
     * specific to the token holder.
     */
    mapping(address => mapping(address => bool)) internal _authorizedOperator;

    /**************************************************************************/
    /********************** Partition operator mappings ***********************/

    /**
     * @dev Mapping from (partition, tokenHolder, spender) to allowed value.
     * This is specific to the token holder.
     */
    mapping(bytes32 => mapping(address => mapping(address => uint256))) internal _allowedByPartition;

    /**
     * @dev Mapping from (tokenHolder, partition, operator) to 'approved for
     * partition' status. This is specific to the token holder.
     */
    mapping(address => mapping(bytes32 => mapping(address => bool))) internal _authorizedOperatorByPartition;

    /**************************************************************************/
    /********************** Collateral Manager mappings ***********************/
    /**
     * @notice Collection of registered collateral managers.
     */
    address[] public collateralManagers;
    /**
     * @dev Mapping of collateral manager addresses to registration status.
     */
    mapping(address => bool) internal _isCollateralManager;

    /**************************************************************************/
    /********************* Partition Strategy mappings ************************/

    /**
     * @notice Collection of reserved partition strategies.
     */
    bytes4[] public partitionStrategies;

    /**
     * @dev Mapping of partition strategy flag to registration status.
     */
    mapping(bytes4 => bool) internal _isPartitionStrategy;

    /**************************************************************************/
    /***************************** Swap storage *******************************/

    /**
     * @notice Swap token address.
     */
    ISwapToken public swapToken;

    /**
     * @notice Swap token graveyard address.
     * @dev This is the address that the incoming swapped tokens will be
     * forwarded to upon successfully minting Amp.
     */
    address public constant swapTokenGraveyard = 0x000000000000000000000000000000000000dEaD;

    /**************************************************************************/
    /** EVENTS ****************************************************************/
    /**************************************************************************/

    /**************************************************************************/
    /**************************** Transfer Events *****************************/

    /**
     * @notice Emitted when a transfer has been successfully completed.
     * @param fromPartition The partition the tokens were transfered from.
     * @param operator The address that initiated the transfer.
     * @param from The address the tokens were transferred from.
     * @param to The address the tokens were transferred to.
     * @param value The amount of tokens transferred.
     * @param data Additional metadata included with the transfer. Can include
     * the partition the tokens were transferred to (if different than
     * `fromPartition`).
     * @param operatorData Additional metadata included with the transfer on
     * behalf of the operator.
     */
    event TransferByPartition(
        bytes32 indexed fromPartition,
        address operator,
        address indexed from,
        address indexed to,
        uint256 value,
        bytes data,
        bytes operatorData
    );

    /**
     * @notice Emitted when a transfer has been successfully completed and the
     * tokens that were transferred have changed partitions.
     * @param fromPartition The partition the tokens were transfered from.
     * @param toPartition The partition the tokens were transfered to.
     * @param value The amount of tokens transferred.
     */
    event ChangedPartition(
        bytes32 indexed fromPartition,
        bytes32 indexed toPartition,
        uint256 value
    );

    /**************************************************************************/
    /**************************** Operator Events *****************************/

    /**
     * @notice Emitted when a token holder specifies an amount of tokens in a
     * a partition that an operator can transfer.
     * @param partition The partition of the tokens the holder has authorized the
     * operator to transfer from.
     * @param owner The token holder.
     * @param spender The operator the `owner` has authorized the allowance for.
     */
    event ApprovalByPartition(
        bytes32 indexed partition,
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    /**
     * @notice Emitted when a token holder has authorized an operator for their
     * tokens.
     * @dev This event applies to the token holder address across all partitions.
     * @param operator The address that was authorized to transfer tokens on
     * behalf of the `tokenHolder`.
     * @param tokenHolder The address that authorized the `operator` to transfer
     * their tokens.
     */
    event AuthorizedOperator(address indexed operator, address indexed tokenHolder);

    /**
     * @notice Emitted when a token holder has de-authorized an operator from
     * transferring their tokens.
     * @dev This event applies to the token holder address across all partitions.
     * @param operator The address that was de-authorized from transferring tokens
     * on behalf of the `tokenHolder`.
     * @param tokenHolder The address that revoked the `operator`'s permission
     * to transfer their tokens.
     */
    event RevokedOperator(address indexed operator, address indexed tokenHolder);

    /**
     * @notice Emitted when a token holder has authorized an operator to transfer
     * their tokens of one partition.
     * @param partition The partition the `operator` is allowed to transfer
     * tokens from.
     * @param operator The address that was authorized to transfer tokens on
     * behalf of the `tokenHolder`.
     * @param tokenHolder The address that authorized the `operator` to transfer
     * their tokens in `partition`.
     */
    event AuthorizedOperatorByPartition(
        bytes32 indexed partition,
        address indexed operator,
        address indexed tokenHolder
    );

    /**
     * @notice Emitted when a token holder has de-authorized an operator from
     * transferring their tokens from a specific partition.
     * @param partition The partition the `operator` is no longer allowed to
     * transfer tokens from on behalf of the `tokenHolder`.
     * @param operator The address that was de-authorized from transferring
     * tokens on behalf of the `tokenHolder`.
     * @param tokenHolder The address that revoked the `operator`'s permission
     * to transfer their tokens from `partition`.
     */
    event RevokedOperatorByPartition(
        bytes32 indexed partition,
        address indexed operator,
        address indexed tokenHolder
    );

    /**************************************************************************/
    /********************** Collateral Manager Events *************************/

    /**
     * @notice Emitted when a collateral manager has been registered.
     * @param collateralManager The address of the collateral manager.
     */
    event CollateralManagerRegistered(address collateralManager);

    /**************************************************************************/
    /*********************** Partition Strategy Events ************************/

    /**
     * @notice Emitted when a new partition strategy validator is set.
     * @param flag The 4 byte prefix of the partitions that the stratgy affects.
     * @param name The name of the partition strategy.
     * @param implementation The address of the partition strategy hook
     * implementation.
     */
    event PartitionStrategySet(bytes4 flag, string name, address indexed implementation);

    // ************** Mint & Swap **************

    /**
     * @notice Emitted when tokens are minted as a result of a token swap
     * @param operator Address that executed the swap that resulted in tokens being minted
     * @param to Address that received the newly minted tokens.
     * @param value Amount of tokens minted
     * @param data Empty bytes, required for interface compatibility
     */
    event Minted(address indexed operator, address indexed to, uint256 value, bytes data);

    /**
     * @notice Indicates tokens swapped for Amp.
     * @dev The tokens that are swapped for Amp will be transferred to a
     * graveyard address that is for all practical purposes inaccessible.
     * @param operator Address that executed the swap.
     * @param from Address that the tokens were swapped from, and Amp minted for.
     * @param value Amount of tokens swapped into Amp.
     */
    event Swap(address indexed operator, address indexed from, uint256 value);

    /**************************************************************************/
    /** CONSTRUCTOR ***********************************************************/
    /**************************************************************************/

    /**
     * @notice Initialize Amp, initialize the default partition, and register the
     * contract implementation in the global ERC1820Registry.
     * @param _swapTokenAddress_ The address of the ERC20 token that is set to be
     * swappable for Amp.
     * @param _name_ Name of the token.
     * @param _symbol_ Symbol of the token.
     */
    constructor(
        address _swapTokenAddress_,
        string memory _name_,
        string memory _symbol_
    ) public {
        // "Swap token cannot be 0 address"
        require(_swapTokenAddress_ != address(0), EC_5A_INVALID_SWAP_TOKEN_ADDRESS);
        swapToken = ISwapToken(_swapTokenAddress_);

        _name = _name_;
        _symbol = _symbol_;
        _totalSupply = 0;

        // Add the default partition to the total partitions on deploy
        _addPartitionToTotalPartitions(defaultPartition);

        // Register contract in ERC1820 registry
        ERC1820Client.setInterfaceImplementation(AMP_INTERFACE_NAME, address(this));
        ERC1820Client.setInterfaceImplementation(ERC20_INTERFACE_NAME, address(this));

        // Indicate token verifies Amp, ERC777 and ERC20 interfaces
        ERC1820Implementer._setInterface(AMP_INTERFACE_NAME);
        ERC1820Implementer._setInterface(ERC20_INTERFACE_NAME);
        // ERC1820Implementer._setInterface(ERC777_INTERFACE_NAME);
    }

    /**************************************************************************/
    /** EXTERNAL FUNCTIONS (ERC20) ********************************************/
    /**************************************************************************/

    /**
     * @notice Get the total number of issued tokens.
     * @return Total supply of tokens currently in circulation.
     */
    function totalSupply() external override view returns (uint256) {
        return _totalSupply;
    }

    /**
     * @notice Get the balance of the account with address `_tokenHolder`.
     * @dev This returns the balance of the holder by the default partition, in
     * order to be compatible with ERC20, as the default partition is the only
     * on where the tokens are guaranteed to be unlocked.
     * @param _tokenHolder Address for which the balance is returned.
     * @return Amount of token held by `_tokenHolder` in the default partition.
     */
    function balanceOf(address _tokenHolder) external override view returns (uint256) {
        return _balanceOfByPartition[_tokenHolder][defaultPartition];
    }

    /**
     * @notice Transfer token for a specified address.
     * @param _to The address to transfer to.
     * @param _value The value to be transferred.
     * @return A boolean that indicates if the operation was successful.
     */
    function transfer(address _to, uint256 _value) external override returns (bool) {
        _transferByDefaultPartition(msg.sender, msg.sender, _to, _value, "");
        return true;
    }

    /**
     * @notice Check the value of tokens that an owner allowed to a spender.
     * @param _owner address The address which owns the funds.
     * @param _spender address The address which will spend the funds.
     * @return A uint256 specifying the value of tokens still available for the
     * spender.
     */
    function allowance(address _owner, address _spender)
        external
        override
        view
        returns (uint256)
    {
        return _allowed[_owner][_spender];
    }

    /**
     * @notice Approve the passed address to spend the specified amount of
     * tokens on behalf of 'msg.sender'.
     * @param _spender The address which will spend the funds.
     * @param _value The amount of tokens to be spent.
     * @return A boolean that indicates if the operation was successful.
     */
    function approve(address _spender, uint256 _value) external override returns (bool) {
        _approve(msg.sender, _spender, _value);
        return true;
    }

    /**
     * @notice Atomically increases the allowance granted to `_spender` by the
     * for caller.
     * @dev This is an alternative to {approve} that can be used as a mitigation
     * problems described in {IERC20-approve}.
     * Emits an {Approval} event indicating the updated allowance.
     * Requirements:
     * - `_spender` cannot be the zero address.
     * @param _spender Operator allowed to transfer the tokens
     * @param _addedValue Additional amount of the `msg.sender`s tokens `_spender`
     * is allowed to transfer
     * @return 'true' is successful, 'false' otherwise
     */
    function increaseAllowance(address _spender, uint256 _addedValue)
        external
        returns (bool)
    {
        _approve(msg.sender, _spender, _allowed[msg.sender][_spender].add(_addedValue));
        return true;
    }

    /**
     * @notice Atomically decreases the allowance granted to `_spender` by the
     * caller.
     * @dev This is an alternative to {approve} that can be used as a mitigation
     * for bugs caused by reentrancy.
     * Emits an {Approval} event indicating the updated allowance.
     * Requirements:
     * - `_spender` cannot be the zero address.
     * - `_spender` must have allowance for the caller of at least
     * `_subtractedValue`.
     * @param _spender Operator allowed to transfer the tokens
     * @param _subtractedValue Amount of the `msg.sender`s tokens `_spender`
     * is no longer allowed to transfer
     * @return 'true' is successful, 'false' otherwise
     */
    function decreaseAllowance(address _spender, uint256 _subtractedValue)
        external
        returns (bool)
    {
        _approve(
            msg.sender,
            _spender,
            _allowed[msg.sender][_spender].sub(_subtractedValue)
        );
        return true;
    }

    /**
     * @notice Transfer tokens from one address to another.
     * @param _from The address which you want to transfer tokens from.
     * @param _to The address which you want to transfer to.
     * @param _value The amount of tokens to be transferred.
     * @return A boolean that indicates if the operation was successful.
     */
    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    ) external override returns (bool) {
        require(
            _isOperator(msg.sender, _from) || (_value <= _allowed[_from][msg.sender]),
            EC_53_INSUFFICIENT_ALLOWANCE
        );

        if (_allowed[_from][msg.sender] >= _value) {
            _allowed[_from][msg.sender] = _allowed[_from][msg.sender].sub(_value);
        } else {
            _allowed[_from][msg.sender] = 0;
        }

        _transferByDefaultPartition(msg.sender, _from, _to, _value, "");
        return true;
    }

    /**************************************************************************/
    /** EXTERNAL FUNCTIONS (AMP) **********************************************/
    /**************************************************************************/

    /******************************** Swap  ***********************************/

    /**
     * @notice Swap tokens to mint AMP.
     * @dev Requires `_from` to have given allowance of swap token to contract.
     * Otherwise will throw error code 53 (Insuffient Allowance).
     * @param _from Token holder to execute the swap for.
     */
    function swap(address _from) public {
        uint256 amount = swapToken.allowance(_from, address(this));
        require(amount > 0, EC_53_INSUFFICIENT_ALLOWANCE);
        // SWC-104-Unchecked Call Return Value: L619
        swapToken.transferFrom(_from, swapTokenGraveyard, amount);

        _mint(msg.sender, _from, amount, "");

        emit Swap(msg.sender, _from, amount);
    }

    /**************************************************************************/
    /************************** Holder information ****************************/

    /**
     * @notice Get the balance of the account with address `_tokenHolder` across all
     * partitions.
     * @param _tokenHolder Address for which the balance is returned.
     * @return Amount of tokens held by `_tokenHolder` in the token contract.
     */
    function totalBalanceOf(address _tokenHolder) external view returns (uint256) {
        return _balances[_tokenHolder];
    }

    /**
     * @notice Get balance of a tokenholder for a specific partition.
     * @param _partition Name of the partition.
     * @param _tokenHolder Address for which the balance is returned.
     * @return Amount of token of partition `_partition` held by `_tokenHolder` in the token contract.
     */
    function balanceOfByPartition(bytes32 _partition, address _tokenHolder)
        external
        view
        returns (uint256)
    {
        return _balanceOfByPartition[_tokenHolder][_partition];
    }

    /**
     * @notice Get partitions index of a token holder.
     * @param _tokenHolder Address for which the partitions index are returned.
     * @return Array of partitions index of '_tokenHolder'.
     */
    function partitionsOf(address _tokenHolder) external view returns (bytes32[] memory) {
        return _partitionsOf[_tokenHolder];
    }

    /**************************************************************************/
    /****************************** Transfers *********************************/

    /**
     * @notice Transfer tokens from the sender to another address, optionally
     * including arbitirary data.
     * @dev Transfer the amount of tokens from the address 'msg.sender' to the
     * address `_to`.
     * @param _to Token recipient.
     * @param _value Number of tokens to transfer.
     * @param _data Information attached to the transfer, by the token holder.
     */
    function transferWithData(
        address _to,
        uint256 _value,
        bytes calldata _data
    ) external {
        _transferByDefaultPartition(msg.sender, msg.sender, _to, _value, _data);
    }

    /**
     * @notice Transfer tokens on behalf of a token holder to another address,
     * optionally including arbitirary data.
     * @dev Transfer the amount of tokens on behalf of the address '_from' to
     * the address 'to'. The `msg.sender` must be an operator for `_from`.
     * @param _from Token holder (or 'address(0)' to set from to 'msg.sender').
     * @param _to Token recipient.
     * @param _value Number of tokens to transfer.
     * @param _data Information attached to the transfer, and intended for the
     * token holder (`_from`).
     */
    function transferFromWithData(
        address _from,
        address _to,
        uint256 _value,
        bytes calldata _data
    ) external {
        require(_isOperator(msg.sender, _from), EC_58_INVALID_OPERATOR);

        _transferByDefaultPartition(msg.sender, _from, _to, _value, _data);
    }

    /**************************************************************************/
    /********************* Partition Token Transfers **************************/

    /**
     * @notice Transfer tokens from a specific partition.
     * @param _partition Name of the partition.
     * @param _to Token recipient.
     * @param _value Number of tokens to transfer.
     * @param _data Information attached to the transfer, by the token holder.
     * @return Destination partition.
     */
    function transferByPartition(
        bytes32 _partition,
        address _to,
        uint256 _value,
        bytes calldata _data
    ) external returns (bytes32) {
        return
            _transferByPartition(
                _partition,
                msg.sender,
                msg.sender,
                _to,
                _value,
                _data,
                ""
            );
    }

    /**
     * @notice Transfer tokens from a specific partition on behalf of a token
     * holder, optionally changing the parittion and optionally including
     * arbitrary data with the transfer.
     * @dev Transfer tokens from a specific partition through an operator.
     * @param _partition Name of the partition.
     * @param _from Token holder.
     * @param _to Token recipient.
     * @param _value Number of tokens to transfer.
     * @param _data Information attached to the transfer. Will contain the
     * destination partition (if changing partitions).
     * @param _operatorData Information attached to the transfer, by the operator.
     * @return Destination partition.
     */
    function operatorTransferByPartition(
        bytes32 _partition,
        address _from,
        address _to,
        uint256 _value,
        bytes calldata _data,
        bytes calldata _operatorData
    ) external returns (bytes32) {
        require(
            _isOperatorForPartition(_partition, msg.sender, _from) ||
                (_value <= _allowedByPartition[_partition][_from][msg.sender]),
            EC_53_INSUFFICIENT_ALLOWANCE
        );

        if (_allowedByPartition[_partition][_from][msg.sender] >= _value) {
            _allowedByPartition[_partition][_from][msg
                .sender] = _allowedByPartition[_partition][_from][msg.sender].sub(_value);
        } else {
            _allowedByPartition[_partition][_from][msg.sender] = 0;
        }

        return
            _transferByPartition(
                _partition,
                msg.sender,
                _from,
                _to,
                _value,
                _data,
                _operatorData
            );
    }

    /**************************************************************************/
    /************************** Operator Management ***************************/

    /**
     * @notice Set a third party operator address as an operator of 'msg.sender'
     * to transfer and redeem tokens on its behalf.
     * @param _operator Address to set as an operator for 'msg.sender'.
     */
    function authorizeOperator(address _operator) external {
        require(_operator != msg.sender);
        _authorizedOperator[msg.sender][_operator] = true;
        emit AuthorizedOperator(_operator, msg.sender);
    }

    /**
     * @notice Remove the right of the operator address to be an operator for
     * 'msg.sender' and to transfer and redeem tokens on its behalf.
     * @param _operator Address to rescind as an operator for 'msg.sender'.
     */
    function revokeOperator(address _operator) external {
        require(_operator != msg.sender);
        _authorizedOperator[msg.sender][_operator] = false;
        emit RevokedOperator(_operator, msg.sender);
    }

    /**
     * @dev Set `_operator` as an operator for 'msg.sender' for a given partition.
     * @param _partition Name of the partition.
     * @param _operator Address to set as an operator for 'msg.sender'.
     */
    function authorizeOperatorByPartition(bytes32 _partition, address _operator)
        external
    {
        _authorizedOperatorByPartition[msg.sender][_partition][_operator] = true;
        emit AuthorizedOperatorByPartition(_partition, _operator, msg.sender);
    }

    /**
     * @notice Remove the right of the operator address to be an operator on a
     * given partition for 'msg.sender' and to transfer and redeem tokens on its
     * behalf.
     * @param _partition Name of the partition.
     * @param _operator Address to rescind as an operator on given partition for
     * 'msg.sender'.
     */
    function revokeOperatorByPartition(bytes32 _partition, address _operator) external {
        _authorizedOperatorByPartition[msg.sender][_partition][_operator] = false;
        emit RevokedOperatorByPartition(_partition, _operator, msg.sender);
    }

    /**************************************************************************/
    /************************** Operator Information **************************/
    /**
     * @notice Indicate whether the `_operator` address is an operator of the
     * `_tokenHolder` address.
     * @param _operator Address which may be an operator of `_tokenHolder`.
     * @param _tokenHolder Address of a token holder which may have the
     * `_operator` address as an operator.
     * @return 'true' if operator is an operator of 'tokenHolder' and 'false'
     * otherwise.
     */
    function isOperator(address _operator, address _tokenHolder)
        external
        view
        returns (bool)
    {
        return _isOperator(_operator, _tokenHolder);
    }

    /**
     * @notice Indicate whether the operator address is an operator of the
     * `_tokenHolder` address for the given partition.
     * @param _partition Name of the partition.
     * @param _operator Address which may be an operator of tokenHolder for the
     * given partition.
     * @param _tokenHolder Address of a token holder which may have the
     * `_operator` address as an operator for the given partition.
     * @return 'true' if 'operator' is an operator of `_tokenHolder` for
     * partition '_partition' and 'false' otherwise.
     */
    function isOperatorForPartition(
        bytes32 _partition,
        address _operator,
        address _tokenHolder
    ) external view returns (bool) {
        return _isOperatorForPartition(_partition, _operator, _tokenHolder);
    }

    /**
     * @notice Indicate when the `_operator` address is an operator of the
     * `_collateralManager` address for the given partition.
     * @dev This method is the same as `isOperatorForPartition`, except that it
     * also requires the address that `_operator` is being checked for MUST be
     * a registered collateral manager, and this method will not execute
     * partition strategy operator check hooks.
     * @param _partition Name of the partition.
     * @param _operator Address which may be an operator of `_collateralManager`
     * for the given partition.
     * @param _collateralManager Address of a collateral manager which may have
     * the `_operator` address as an operator for the given partition.
     */
    function isOperatorForCollateralManager(
        bytes32 _partition,
        address _operator,
        address _collateralManager
    ) external view returns (bool) {
        return
            _isCollateralManager[_collateralManager] &&
            (_isOperator(_operator, _collateralManager) ||
                _authorizedOperatorByPartition[_collateralManager][_partition][_operator]);
    }

    /**************************************************************************/
    /***************************** Token metadata *****************************/
    /**
     * @notice Get the name of the token (Amp).
     * @return Name of the token.
     */
    function name() external view returns (string memory) {
        return _name;
    }

    /**
     * @notice Get the symbol of the token (AMP).
     * @return Symbol of the token.
     */
    function symbol() external view returns (string memory) {
        return _symbol;
    }

    /**
     * @notice Get the number of decimals of the token.
     * @dev Hard coded to 18.
     * @return The number of decimals of the token (18).
     */
    function decimals() external pure returns (uint8) {
        return uint8(18);
    }

    /**
     * @notice Get the smallest part of the token that’s not divisible.
     * @dev Hard coded to 1.
     * @return The smallest non-divisible part of the token.
     */
    function granularity() external pure returns (uint256) {
        return _granularity;
    }

    /**
     * @notice Get list of existing partitions.
     * @return Array of all exisiting partitions.
     */
    function totalPartitions() external view returns (bytes32[] memory) {
        return _totalPartitions;
    }

    /************************************************************************************************/
    /********************************* Token default partitions *************************************/
    /**
     * @notice Get default partition to transfer from.
     * @return The default partition.
     */
    function getDefaultPartition() external pure returns (bytes32) {
        return defaultPartition;
    }

    /************************************************************************************************/
    /******************************** Partition Token Allowances ************************************/
    /**
     * @notice Check the value of tokens that an owner allowed to a spender.
     * @param _partition Name of the partition.
     * @param _owner The address which owns the tokens.
     * @param _spender The address which will spend the tokens.
     * @return The value of tokens still for the spender to transfer.
     */
    function allowanceByPartition(
        bytes32 _partition,
        address _owner,
        address _spender
    ) external view returns (uint256) {
        return _allowedByPartition[_partition][_owner][_spender];
    }

    /**
     * @notice Approve the `_spender` address to spend the specified amount of
     * tokens in `_partition` on behalf of 'msg.sender'.
     * @param _partition Name of the partition.
     * @param _spender The address which will spend the tokens.
     * @param _value The amount of tokens to be tokens.
     * @return A boolean that indicates if the operation was successful.
     */
    function approveByPartition(
        bytes32 _partition,
        address _spender,
        uint256 _value
    ) external returns (bool) {
        _approveByPartition(_partition, msg.sender, _spender, _value);
        return true;
    }

    /**
     * @notice Atomically increases the allowance granted to `_spender` by the
     * caller.
     * @dev This is an alternative to {approveByPartition} that can be used as
     * a mitigation for bugs caused by reentrancy.
     * Emits an {ApprovalByPartition} event indicating the updated allowance.
     * Requirements:
     * - `_spender` cannot be the zero address.
     * @param _partition Name of the partition.
     * @param _spender Operator allowed to transfer the tokens
     * @param _addedValue Additional amount of the `msg.sender`s tokens `_spender`
     * is allowed to transfer
     * @return 'true' is successful, 'false' otherwise
     */
    function increaseAllowanceByPartition(
        bytes32 _partition,
        address _spender,
        uint256 _addedValue
    ) external returns (bool) {
        _approveByPartition(
            _partition,
            msg.sender,
            _spender,
            _allowedByPartition[_partition][msg.sender][_spender].add(_addedValue)
        );
        return true;
    }

    /**
     * @notice Atomically decreases the allowance granted to `_spender` by the
     * caller.
     * @dev This is an alternative to {approveByPartition} that can be used as
     * a mitigation for bugs caused by reentrancy.
     * Emits an {ApprovalByPartition} event indicating the updated allowance.
     * Requirements:
     * - `_spender` cannot be the zero address.
     * - `_spender` must have allowance for the caller of at least
     * `_subtractedValue`.
     * @param _spender Operator allowed to transfer the tokens
     * @param _subtractedValue Amount of the `msg.sender`s tokens `_spender` is
     * no longer allowed to transfer
     * @return 'true' is successful, 'false' otherwise
     */
    function decreaseAllowanceByPartition(
        bytes32 _partition,
        address _spender,
        uint256 _subtractedValue
    ) external returns (bool) {
        // TOOD: Figure out if safe math will panic below 0
        _approveByPartition(
            _partition,
            msg.sender,
            _spender,
            _allowedByPartition[_partition][msg.sender][_spender].sub(_subtractedValue)
        );
        return true;
    }

    /**************************************************************************/
    /************************ Collateral Manager Admin ************************/

    /**
     * @notice Allow a collateral manager to self-register.
     * @dev Error 0x5c.
     */
    function registerCollateralManager() external {
        // Short circuit a double registry
        require(!_isCollateralManager[msg.sender], EC_5C_ADDRESS_CONFLICT);

        collateralManagers.push(msg.sender);
        _isCollateralManager[msg.sender] = true;

        emit CollateralManagerRegistered(msg.sender);
    }

    /**
     * @notice Get the status of a collateral manager.
     * @param _collateralManager The address of the collateral mananger in question.
     * @return 'true' if `_collateralManager` has self registered, 'false'
     * otherwise.
     */
    function isCollateralManager(address _collateralManager)
        external
        view
        returns (bool)
    {
        return _isCollateralManager[_collateralManager];
    }

    /**************************************************************************/
    /************************ Partition Strategy Admin ************************/
    /**
     * @notice Sets an implementation for a partition strategy identified by prefix.
     * @dev This is an administration method, callable only by the owner of the
     * Amp contract.
     * @param _prefix The 4 byte partition prefix the strategy applies to.
     * @param _implementation The address of the implementation of the strategy hooks.
     */
    function setPartitionStrategy(bytes4 _prefix, address _implementation)
        external
        onlyOwner
    {
        require(!_isPartitionStrategy[_prefix], EC_5E_PARTITION_PREFIX_CONFLICT);
        require(_prefix != ZERO_PREFIX, EC_5F_INVALID_PARTITION_PREFIX_0);

        string memory iname = _getPartitionStrategyValidatorIName(_prefix);

        ERC1820Client.setInterfaceImplementation(iname, _implementation);
        partitionStrategies.push(_prefix);
        _isPartitionStrategy[_prefix] = true;

        emit PartitionStrategySet(_prefix, iname, _implementation);
    }

    /**
     * @notice Return if a partition strategy has been reserved and has an
     * implementation registered.
     * @param _prefix The partition strategy identifier.
     * @return 'true' if the strategy has been registered, 'false' if not.
     */
    function isPartitionStrategy(bytes4 _prefix) external view returns (bool) {
        return _isPartitionStrategy[_prefix];
    }

    /**************************************************************************/
    /*************************** INTERNAL FUNCTIONS ***************************/
    /**************************************************************************/

    /**************************************************************************/
    /**************************** Token Transfers *****************************/
    /**
     * @notice Perform the transfer of tokens.
     * @param _from Token holder.
     * @param _to Token recipient.
     * @param _value Number of tokens to transfer.
     */
    function _transfer(
        address _from,
        address _to,
        uint256 _value
    ) internal {
        require(_to != address(0), EC_57_INVALID_RECEIVER);
        require(_balances[_from] >= _value, EC_52_INSUFFICIENT_BALANCE);

        _balances[_from] = _balances[_from].sub(_value);
        _balances[_to] = _balances[_to].add(_value);

        emit Transfer(_from, _to, _value);
    }
    // SWC-107-Reentrancy: L1131-L1201
    /**
     * @dev Transfer tokens from a specific partition.
     * @param _fromPartition Partition of the tokens to transfer.
     * @param _operator The address performing the transfer.
     * @param _from Token holder.
     * @param _to Token recipient.
     * @param _value Number of tokens to transfer.
     * @param _data Information attached to the transfer. Contains the destination
     * partition if a partition change is requested.
     * @param _operatorData Information attached to the transfer, by the operator
     * (if any).
     * @return Destination partition.
     */
    function _transferByPartition(
        bytes32 _fromPartition,
        address _operator,
        address _from,
        address _to,
        uint256 _value,
        bytes memory _data,
        bytes memory _operatorData
    ) internal returns (bytes32) {
        require(
            _balanceOfByPartition[_from][_fromPartition] >= _value,
            EC_52_INSUFFICIENT_BALANCE
        );

        bytes32 toPartition = _fromPartition;
        if (_data.length >= 64) {
            toPartition = _getDestinationPartition(_fromPartition, _data);
        }
        
        _callPreTransferHooks(
            _fromPartition,
            _operator,
            _from,
            _to,
            _value,
            _data,
            _operatorData
        );

        _removeTokenFromPartition(_from, _fromPartition, _value);
        _transfer(_from, _to, _value);
        _addTokenToPartition(_to, toPartition, _value);

        _callPostTransferHooks(
            toPartition,
            _operator,
            _from,
            _to,
            _value,
            _data,
            _operatorData
        );

        emit TransferByPartition(
            _fromPartition,
            _operator,
            _from,
            _to,
            _value,
            _data,
            _operatorData
        );

        if (toPartition != _fromPartition) {
            emit ChangedPartition(_fromPartition, toPartition, _value);
        }

        return toPartition;
    }

    /**
     * @notice Transfer tokens from default partitions.
     * @dev Used as a helper method for ERC20 compatibility.
     * @param _operator The address performing the transfer.
     * @param _from Token holder.
     * @param _to Token recipient.
     * @param _value Number of tokens to transfer.
     * @param _data Information attached to the transfer, and intended for the
     * token holder (`_from`). Should contain the destination partition if
     * changing partitions.
     */
    function _transferByDefaultPartition(
        address _operator,
        address _from,
        address _to,
        uint256 _value,
        bytes memory _data
    ) internal {
        _transferByPartition(defaultPartition, _operator, _from, _to, _value, _data, "");
    }

    /**
     * @dev Remove a token from a specific partition.
     * @param _from Token holder.
     * @param _partition Name of the partition.
     * @param _value Number of tokens to transfer.
     */
    function _removeTokenFromPartition(
        address _from,
        bytes32 _partition,
        uint256 _value
    ) internal {
        _balanceOfByPartition[_from][_partition] = _balanceOfByPartition[_from][_partition]
            .sub(_value);
        totalSupplyByPartition[_partition] = totalSupplyByPartition[_partition].sub(
            _value
        );

        // If the total supply is zero, finds and deletes the partition.
        // Do not delete the _defaultPartition from totalPartitions.
        if (totalSupplyByPartition[_partition] == 0 && _partition != defaultPartition) {
            _removePartitionFromTotalPartitions(_partition);
        }

        // If the balance of the TokenHolder's partition is zero, finds and
        // deletes the partition.
        if (_balanceOfByPartition[_from][_partition] == 0) {
            uint256 index = _indexOfPartitionsOf[_from][_partition];

            if (index == 0) {
                return;
            }

            // move the last item into the index being vacated
            bytes32 lastValue = _partitionsOf[_from][_partitionsOf[_from].length - 1];
            _partitionsOf[_from][index - 1] = lastValue; // adjust for 1-based indexing
            _indexOfPartitionsOf[_from][lastValue] = index;

            _partitionsOf[_from].pop();
            _indexOfPartitionsOf[_from][_partition] = 0;
        }
    }

    /**
     * @dev Add a token to a specific partition.
     * @param _to Token recipient.
     * @param _partition Name of the partition.
     * @param _value Number of tokens to transfer.
     */
    function _addTokenToPartition(
        address _to,
        bytes32 _partition,
        uint256 _value
    ) internal {
        if (_value != 0) {
            if (_indexOfPartitionsOf[_to][_partition] == 0) {
                _partitionsOf[_to].push(_partition);
                _indexOfPartitionsOf[_to][_partition] = _partitionsOf[_to].length;
            }
            _balanceOfByPartition[_to][_partition] = _balanceOfByPartition[_to][_partition]
                .add(_value);

            if (_indexOfTotalPartitions[_partition] == 0) {
                _addPartitionToTotalPartitions(_partition);
            }
            totalSupplyByPartition[_partition] = totalSupplyByPartition[_partition].add(
                _value
            );
        }
    }

    /**
     * @dev Add a partition to the total partitions collection.
     * @param _partition Name of the partition.
     */
    function _addPartitionToTotalPartitions(bytes32 _partition) internal {
        _totalPartitions.push(_partition);
        _indexOfTotalPartitions[_partition] = _totalPartitions.length;
    }

    /**
     * @dev Remove a partition to the total partitions collection.
     * @param _partition Name of the partition.
     */
    function _removePartitionFromTotalPartitions(bytes32 _partition) internal {
        uint256 index = _indexOfTotalPartitions[_partition];

        if (index == 0) {
            return;
        }

        // move the last item into the index being vacated
        bytes32 lastValue = _totalPartitions[_totalPartitions.length - 1];
        _totalPartitions[index - 1] = lastValue; // adjust for 1-based indexing
        _indexOfTotalPartitions[lastValue] = index;

        _totalPartitions.pop();
        _indexOfTotalPartitions[_partition] = 0;
    }

    /**************************************************************************/
    /********************************* Hooks **********************************/
    /**
     * @notice Check for and call the 'AmpTokensSender' hook on the sender address
     * (`_from`), and, if `_fromPartition` is within the scope of a strategy,
     * check for and call the 'AmpPartitionStrategy.tokensFromPartitionToTransfer'
     * hook for the strategy.
     * @param _fromPartition Name of the partition to transfer tokens from.
     * @param _operator Address which triggered the balance decrease (through
     * transfer).
     * @param _from Token holder.
     * @param _to Token recipient for a transfer.
     * @param _value Number of tokens the token holder balance is decreased by.
     * @param _data Extra information, pertaining to the `_from` address.
     * @param _operatorData Extra information, attached by the operator (if any).
     */
    function _callPreTransferHooks(
        bytes32 _fromPartition,
        address _operator,
        address _from,
        address _to,
        uint256 _value,
        bytes memory _data,
        bytes memory _operatorData
    ) internal {
        address senderImplementation;
        senderImplementation = interfaceAddr(_from, AMP_TOKENS_SENDER);
        if (senderImplementation != address(0)) {
            IAmpTokensSender(senderImplementation).tokensToTransfer(
                msg.sig,
                _fromPartition,
                _operator,
                _from,
                _to,
                _value,
                _data,
                _operatorData
            );
        }

        // Used to ensure that hooks implemented by a collateral manager to validate
        // transfers from it's owned partitions are called
        bytes4 fromPartitionPrefix = _getPartitionPrefix(_fromPartition);
        if (_isPartitionStrategy[fromPartitionPrefix]) {
            address fromPartitionValidatorImplementation;
            fromPartitionValidatorImplementation = interfaceAddr(
                address(this),
                _getPartitionStrategyValidatorIName(fromPartitionPrefix)
            );
            if (fromPartitionValidatorImplementation != address(0)) {
                IAmpPartitionStrategyValidator(fromPartitionValidatorImplementation)
                    .tokensFromPartitionToValidate(
                    msg.sig,
                    _fromPartition,
                    _operator,
                    _from,
                    _to,
                    _value,
                    _data,
                    _operatorData
                );
            }
        }
    }

    /**
     * @dev Check for 'AmpTokensRecipient' hook on the recipient and call it.
     * @param _toPartition Name of the partition the tokens were transferred to.
     * @param _operator Address which triggered the balance increase (through
     * transfer or mint).
     * @param _from Token holder for a transfer (0x when mint).
     * @param _to Token recipient.
     * @param _value Number of tokens the recipient balance is increased by.
     * @param _data Extra information related to the token holder (`_from`).
     * @param _operatorData Extra information attached by the operator (if any).
     */
    function _callPostTransferHooks(
        bytes32 _toPartition,
        address _operator,
        address _from,
        address _to,
        uint256 _value,
        bytes memory _data,
        bytes memory _operatorData
    ) internal {
        bytes4 toPartitionPrefix = _getPartitionPrefix(_toPartition);
        if (_isPartitionStrategy[toPartitionPrefix]) {
            address partitionManagerImplementation;
            partitionManagerImplementation = interfaceAddr(
                address(this),
                _getPartitionStrategyValidatorIName(toPartitionPrefix)
            );
            if (partitionManagerImplementation != address(0)) {
                IAmpPartitionStrategyValidator(partitionManagerImplementation)
                    .tokensToPartitionToValidate(
                    msg.sig,
                    _toPartition,
                    _operator,
                    _from,
                    _to,
                    _value,
                    _data,
                    _operatorData
                );
            }
        } else {
            require(toPartitionPrefix == ZERO_PREFIX, EC_5D_PARTITION_RESERVED);
        }

        address recipientImplementation;
        recipientImplementation = interfaceAddr(_to, AMP_TOKENS_RECIPIENT);

        if (recipientImplementation != address(0)) {
            IAmpTokensRecipient(recipientImplementation).tokensReceived(
                msg.sig,
                _toPartition,
                _operator,
                _from,
                _to,
                _value,
                _data,
                _operatorData
            );
        }
    }

    /**************************************************************************/
    /******************************* Allowance ********************************/
    /**
     * @notice Sets `_amount` as the allowance of `_spender` over the
     * `_tokenHolder`s tokens.
     * @dev This is internal function is equivalent to `approve`, and can be used
     * to e.g. set automatic allowances for certain subsystems, etc.
     * Emits an {Approval} event.
     * Requirements:
     * - `_tokenHolder` cannot be the zero address.
     * - `_spender` cannot be the zero address.
     * @param _tokenHolder Owner of the tokens
     * @param _spender Operator allowed to transfer the tokens
     * @param _amount Amount of `_tokenHolder`s tokens `_spender` is allowed to
     * transfer
     */
    function _approve(
        address _tokenHolder,
        address _spender,
        uint256 _amount
    ) internal {
        require(_tokenHolder != address(0), EC_56_INVALID_SENDER);
        require(_spender != address(0), EC_58_INVALID_OPERATOR);

        _allowed[_tokenHolder][_spender] = _amount;
        emit Approval(_tokenHolder, _spender, _amount);
    }

    /**
     * @notice Approve the `_spender` address to spend the specified amount of
     * tokens in `_partition` on behalf of 'msg.sender'.
     * @param _partition Name of the partition.
     * @param _tokenHolder Owner of the tokens.
     * @param _spender The address which will spend the tokens.
     * @param _amount The amount of tokens to be tokens.
     */
    function _approveByPartition(
        bytes32 _partition,
        address _tokenHolder,
        address _spender,
        uint256 _amount
    ) internal {
        require(_tokenHolder != address(0), EC_56_INVALID_SENDER);
        require(_spender != address(0), EC_58_INVALID_OPERATOR);
        _allowedByPartition[_partition][_tokenHolder][_spender] = _amount;
        emit ApprovalByPartition(_partition, _tokenHolder, _spender, _amount);
    }

    /**************************************************************************/
    /************************** Operator Information **************************/
    /**
     * @dev Indicate whether the operator address is an operator of the
     * tokenHolder address.
     * @param _operator Address which may be an operator of '_tokenHolder'.
     * @param _tokenHolder Address of a token holder which may have the '_operator'
     * address as an operator.
     * @return 'true' if `_operator` is an operator of `_tokenHolder` and 'false'
     * otherwise.
     */
    function _isOperator(address _operator, address _tokenHolder)
        internal
        view
        returns (bool)
    {
        return (_operator == _tokenHolder ||
            _authorizedOperator[_tokenHolder][_operator]);
    }

    /**
     * @dev Indicate whether the operator address is an operator of the tokenHolder
     * address for the given partition.
     * @param _partition Name of the partition.
     * @param _operator Address which may be an operator of tokenHolder for the
     * given partition.
     * @param _tokenHolder Address of a token holder which may have the operator
     * address as an operator for the given partition.
     * @return 'true' if 'operator' is an operator of 'tokenHolder' for partition
     * `_partition` and 'false' otherwise.
     */
    function _isOperatorForPartition(
        bytes32 _partition,
        address _operator,
        address _tokenHolder
    ) internal view returns (bool) {
        return (_isOperator(_operator, _tokenHolder) ||
            _authorizedOperatorByPartition[_tokenHolder][_partition][_operator] ||
            _callPartitionStrategyOperatorHook(_partition, _operator, _tokenHolder));
    }

    /**
     * @notice Check if the `_partition` is within the scope of a strategy, and
     * call it's isOperatorForPartitionScope hook if so.
     * @dev This allows implicit granting of operatorByPartition permissions
     * based on the partition being used being of a strategy.
     * @param _partition The partition to check.
     * @param _operator The address to check if is an operator for `_tokenHolder`.
     * @param _tokenHolder The address to validate that `_operator` is an
     * operator for.
     */
    function _callPartitionStrategyOperatorHook(
        bytes32 _partition,
        address _operator,
        address _tokenHolder
    ) internal view returns (bool) {
        bytes4 prefix = _getPartitionPrefix(_partition);

        if (!_isPartitionStrategy[prefix]) {
            return false;
        }

        address strategyValidatorImplementation;
        strategyValidatorImplementation = interfaceAddr(
            address(this),
            _getPartitionStrategyValidatorIName(prefix)
        );
        if (strategyValidatorImplementation != address(0)) {
            return
                IAmpPartitionStrategyValidator(strategyValidatorImplementation)
                    .isOperatorForPartitionScope(_partition, _operator, _tokenHolder);
        }

        // Not a partition format that imbues special operator rules
        return false;
    }

    /**************************************************************************/
    /******************************** Minting *********************************/
    /**
     * @notice Perform the minting of tokens.
     * @dev The tokens will be minted on behalf of the `_to` address, and will be
     * minted to the address's default partition.
     * @param _operator Address which triggered the issuance.
     * @param _to Token recipient.
     * @param _value Number of tokens issued.
     * @param _data Information attached to the minting, and intended for the
     * recipient (`_to`).
     */
    function _mint(
        address _operator,
        address _to,
        uint256 _value,
        bytes memory _data
    ) internal {
        require(_to != address(0), EC_57_INVALID_RECEIVER);

        _totalSupply = _totalSupply.add(_value);
        _balances[_to] = _balances[_to].add(_value);

        _addTokenToPartition(_to, defaultPartition, _value);
        _callPostTransferHooks(
            defaultPartition,
            _operator,
            address(0),
            _to,
            _value,
            _data,
            ""
        );

        emit Minted(_operator, _to, _value, _data);
        emit Transfer(address(0), _to, _value);
    }
}
