// SPDX-License-Identifier: MIT

pragma solidity 0.6.9;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";

import "./amp/IAmp.sol";
import "./amp/IAmpTokensRecipient.sol";
import "./amp/IAmpTokensSender.sol";

import "./erc1820/ERC1820Client.sol";


/**
 * @title FlexaCollateralManager is an implementation of IAmpTokensSender and IAmpTokensRecipient
 * which serves as the Amp collateral manager for the Flexa Network.
 */
contract FlexaCollateralManager is IAmpTokensSender, IAmpTokensRecipient, ERC1820Client {
    /**
     * @dev AmpTokensSender interface label.
     */
    string internal constant AMP_TOKENS_SENDER = "AmpTokensSender";

    /**
     * @dev AmpTokensRecipient interface label.
     */
    string internal constant AMP_TOKENS_RECIPIENT = "AmpTokensRecipient";

    /**
     * @dev Change Partition Flag used in transfer data parameters to signal which partition
     * will receive the tokens.
     */
    bytes32 internal constant CHANGE_PARTITION_FLAG = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    /**
     * @dev Required prefix for all registered partitions. Used to ensure the Collateral Pool
     * Partition Validator is used within Amp.
     */
    bytes4 internal constant PARTITION_PREFIX = 0xCCCCCCCC;

    /**********************************************************************************************
     * Operator Data Flags
     *********************************************************************************************/

    /**
     * @dev Flag used in operator data parameters to indicate the transfer is a withdrawal
     */
    bytes32 internal constant WITHDRAWAL_FLAG = 0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa;

    /**
     * @dev Flag used in operator data parameters to indicate the transfer is a fallback
     * withdrawal
     */
    bytes32 internal constant FALLBACK_WITHDRAWAL_FLAG = 0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb;

    /**
     * @dev Flag used in operator data parameters to indicate the transfer is a supply refund
     */
    bytes32 internal constant REFUND_FLAG = 0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc;

    /**
     * @dev Flag used in operator data parameters to indicate the transfer is a consumption
     */
    bytes32 internal constant CONSUMPTION_FLAG = 0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd;

    /**********************************************************************************************
     * Configuration
     *********************************************************************************************/

    /**
     * @notice Address of the Amp contract
     */
    address public amp;

    /**
     * @notice Permitted partitions
     */
    mapping(bytes32 => bool) public partitions;

    /**********************************************************************************************
     * Roles
     *********************************************************************************************/

    /**
     * @notice Address authorized to manage other roles and perform all administrative functions
     */
    address public owner;

    /**
     * @notice Address used to hold the address of a new owner as part of a two-step transfer
     */
    address public authorizedNewOwner;

    /**
     * @notice Address authorized to publish withdrawal roots
     */
    address public withdrawalPublisher;

    /**
     * @notice Address authorized to publish fallback withdrawal roots
     */
    address public fallbackPublisher;

    /**
     * @notice Address authorized to adjust the withdrawal limit
     */
    address public withdrawalLimitPublisher;

    /**
     * @notice Address authorized to consume tokens
     */
    address public consumer;

    /**
     * @notice Address authorized to manage permitted partition
     */
    address public partitionManager;

    /**
     * @notice Struct used to record received tokens that can be recovered during the fallback
     * withdrawal period
     * @param supplier Token supplier
     * @param partition Partition which received the tokens
     * @param amount Number of tokens received
     */
    struct Supply {
        address supplier;
        bytes32 partition;
        uint256 amount;
    }

    /**********************************************************************************************
     * Supply State
     *********************************************************************************************/

    /**
     * @notice Supply nonce used to track incoming token transfers
     */
    uint256 public supplyNonce = 0;

    /**
     * @notice Mapping of all incoming token transfers
     */
    mapping(uint256 => Supply) public nonceToSupply;

    /**********************************************************************************************
     * Withdrawal State
     *********************************************************************************************/

    /**
     * @notice Remaining withdrawal limit. Initially set to 100,000 Amp.
     */
    uint256 public withdrawalLimit = 100 * 1000 * (10**18);

    /**
     * @notice Withdrawal maximum root nonce
     */
    uint256 public maxWithdrawalRootNonce = 0;

    /**
     * @notice Active set of withdrawal roots
     */
    mapping(bytes32 => uint256) public withdrawalRootToNonce;

    /**
     * @notice Last invoked withdrawal root for each account, per partition
     */
    mapping(bytes32 => mapping(address => uint256)) public addressToWithdrawalNonce;

    /**
     * @notice Total amount withdrawn for each account, per partition
     */
    mapping(bytes32 => mapping(address => uint256)) public addressToCumulativeAmountWithdrawn;

    /**********************************************************************************************
     * Fallback Withdrawal State
     *********************************************************************************************/

    /**
     * @notice Withdrawal fallback delay. Initially set to one week.
     */
    uint256 public fallbackWithdrawalDelaySeconds = 1 weeks;

    /**
     * @notice Current fallback withdrawal root
     */
    bytes32 public fallbackRoot;

    /**
     * @notice Timestamp of when the last fallback root was published
     */
    uint256 public fallbackSetDate = 2**200; // very far in the future

    /**
     * @notice Latest supply reflected in the fallback withdrawal authorization tree
     */
    uint256 public fallbackMaxIncludedSupplyNonce = 0;

    /**********************************************************************************************
     * Supplier Events
     *********************************************************************************************/

    /**
     * @notice Indicates a token supply has been received
     * @param supplier Token supplier
     * @param amount Number of tokens transferred
     * @param nonce Nonce of the supply
     */
    event SupplyReceipt(
        address indexed supplier,
        bytes32 indexed partition,
        uint256 amount,
        uint256 indexed nonce
    );

    /**
     * @notice Indicates that a withdrawal authorization has been renounced
     * @param supplier Address whose withdrawal authorizations were invalidated
     * @param partition Partition for which the withdrawal authorizations were invalidated
     * @param nonce Nonce of the latest withdrawal root at the time of renouncement
     */
    event RenounceWithdrawalAuthorization(
        address indexed supplier,
        bytes32 indexed partition,
        uint256 indexed nonce
    );

    /**
     * @notice Indicates that a withdrawal was executed
     * @param supplier Address whose withdrawal authorization was executed
     * @param partition Partition from which the tokens were transferred
     * @param amount Amount of tokens transferred
     * @param rootNonce Nonce of the withdrawal root used for authorization
     * @param authorizedAccountNonce Maximum previous nonce used by the account
     */
    event Withdrawal(
        address indexed supplier,
        bytes32 indexed partition,
        uint256 amount,
        uint256 indexed rootNonce,
        uint256 authorizedAccountNonce
    );

    /**
     * @notice Indicates a fallback withdrawal was executed
     * @param supplier Address whose fallback withdrawal authorization was executed
     * @param partition Partition from which the tokens were transferred
     * @param amount Amount of tokens transferred
     */
    event FallbackWithdrawal(
        address indexed supplier,
        bytes32 indexed partition,
        uint256 indexed amount
    );

    /**
     * @notice Indicates a release of supply is requested
     * @param supplier Token supplier
     * @param partition Parition from which the tokens should be released
     * @param amount Number of tokens requested to be released
     */
    event ReleaseRequest(
        address indexed supplier,
        bytes32 indexed partition,
        uint256 indexed amount
    );

    /**
     * @notice Indicates a supply refund was executed
     * @param supplier Address whose refund authorization was executed
     * @param partition Partition from which the tokens were transferred
     * @param amount Amount of tokens transferred
     */
    event SupplyRefund(
        address indexed supplier,
        bytes32 indexed partition,
        uint256 amount,
        uint256 indexed nonce
    );

    /**********************************************************************************************
     * Consumption Events
     *********************************************************************************************/

    /**
     * @notice Emitted when tokens are consumed
     * @param operator Address that executed the consumption
     * @param partition Partition from which the tokens were transferred
     * @param value Amount of tokens transferred
     */
    event Consumption(address indexed operator, bytes32 indexed partition, uint256 indexed value);

    /**********************************************************************************************
     * Admin Configuration Events
     *********************************************************************************************/

    /**
     * @notice Emitted when a partition is permitted for supply
     * @param partition Partition added to the permitted set
     */
    event PartitionAdded(bytes32 indexed partition);

    /**
     * @notice Emitted when a partition is removed from the set permitted for supply
     * @param partition Partition removed from the permitted set
     */
    event PartitionRemoved(bytes32 indexed partition);

    /**********************************************************************************************
     * Admin Withdrawal Management Events
     *********************************************************************************************/

    /**
     * @notice Emitted when a new withdrawal root hash is added to the active set
     * @param rootHash Merkle root hash.
     * @param nonce Nonce of the Merkle root hash.
     */
    event WithdrawalRootHashAddition(bytes32 indexed rootHash, uint256 indexed nonce);

    /**
     * @notice Emitted when a withdrawal root hash is removed from the active set
     * @param rootHash Merkle root hash.
     * @param nonce Nonce of the Merkle root hash.
     */
    event WithdrawalRootHashRemoval(bytes32 indexed rootHash, uint256 indexed nonce);

    /**
     * @notice Emitted when the withdrawal limit is updated
     * @param oldValue Old limit.
     * @param newValue New limit.
     */
    event WithdrawalLimitUpdate(uint256 indexed oldValue, uint256 indexed newValue);

    /**********************************************************************************************
     * Admin Fallback Management Events
     *********************************************************************************************/

    /**
     * @notice Emitted when a new fallback withdrawal root hash is set
     * @param rootHash Merkle root hash
     * @param maxSupplyNonceIncluded Nonce of the last supply reflected in the tree data
     * @param setDate Timestamp of when the root hash was set
     */
    event FallbackRootHashSet(
        bytes32 indexed rootHash,
        uint256 indexed maxSupplyNonceIncluded,
        uint256 setDate
    );

    /**
     * @notice Emitted when the fallback root hash set date is reset
     * @param newDate Timestamp of when the fallback reset date was set
     */
    event FallbackMechanismDateReset(uint256 indexed newDate);

    /**
     * @notice Emitted when the fallback delay is updated
     * @param oldValue Old delay
     * @param newValue New delay
     */
    event FallbackWithdrawalDelayUpdate(uint256 indexed oldValue, uint256 indexed newValue);

    /**********************************************************************************************
     * Role Management Events
     *********************************************************************************************/

    /**
     * @notice Emitted when the owner authorizes ownership transfer to a new address
     * @param authorizedAddress New owner address
     */
    event OwnershipTransferAuthorization(address indexed authorizedAddress);

    /**
     * @notice Emitted when the authorized address assumed ownership
     * @param oldValue Old owner
     * @param newValue New owner
     */
    event OwnerUpdate(address indexed oldValue, address indexed newValue);

    /**
     * @notice Emitted when the Withdrawal Publisher is updated
     * @param oldValue Old publisher
     * @param newValue New publisher
     */
    event WithdrawalPublisherUpdate(address indexed oldValue, address indexed newValue);

    /**
     * @notice Emitted when the Fallback Publisher is updated
     * @param oldValue Old publisher
     * @param newValue New publisher
     */
    event FallbackPublisherUpdate(address indexed oldValue, address indexed newValue);

    /**
     * @notice Emitted when Withdrawal Limit Publisher is updated
     * @param oldValue Old publisher
     * @param newValue New publisher
     */
    event WithdrawalLimitPublisherUpdate(address indexed oldValue, address indexed newValue);

    /**
     * @notice Emitted when the Consumer address is updated
     * @param oldValue Old Consumer address
     * @param newValue New Consumer address
     */
    event ConsumerUpdate(address indexed oldValue, address indexed newValue);

    /**
     * @notice Emitted when the Partition Manager address is updated
     * @param oldValue Old Partition Manager address
     * @param newValue New Partition Manager address
     */
    event PartitionManagerUpdate(address indexed oldValue, address indexed newValue);

    /**********************************************************************************************
     * Constructor
     *********************************************************************************************/

    /**
     * @notice FlexaCollateralManager constructor
     * @param _amp Address of the Amp token contract
     */
    constructor(address _amp) public {
        owner = msg.sender;
        amp = _amp;

        ERC1820Client.setInterfaceImplementation(AMP_TOKENS_RECIPIENT, address(this));
        ERC1820Client.setInterfaceImplementation(AMP_TOKENS_SENDER, address(this));

        IAmp(amp).registerCollateralManager();
    }

    /**********************************************************************************************
     * IAmpTokensRecipient Hooks
     *********************************************************************************************/

    /**
     * @notice Validates where the supplied parameters are valid for a transfer of tokens to this
     * contract
     * @dev Implements IAmpTokensRecipient
     * @param _partition Partition from which the tokens were transferred
     * @param _to The destination address of the tokens. Must be this.
     * @param _data Optional data sent with the transfer. Used to set the destination partition.
     * @return true if the tokens can be received, otherwise false
     */
    function canReceive(
        bytes4, /* functionSig */
        bytes32 _partition,
        address, /* operator */
        address, /* from */
        address _to,
        uint256, /* value */
        bytes calldata _data,
        bytes calldata /* operatorData */
    ) external override view returns (bool) {
        bytes32 _destinationPartition = _getDestinationPartition(_partition, _data);

        return _canReceive(_to, _destinationPartition);
    }

    /**
     * @notice Validates where the supplied parameters are valid for a transfer of tokens to this
     * contract
     * @param _to The destination address of the tokens. Must be this.
     * @param _destinationPartition Partition to which the tokens are to be transferred
     * @return true if the tokens can be received, otherwise false
     */
    function _canReceive(address _to, bytes32 _destinationPartition) internal view returns (bool) {
        return _to == address(this) && partitions[_destinationPartition];
    }

    /**
     * @notice Function called by the token contract after executing a transfer.
     * @dev Implements IAmpTokensRecipient
     * @param _partition Partition from which the tokens were transferred
     * @param _operator Address which triggered the transfer. This address will be credited with
     * the supply.
     * @param _to The destination address of the tokens. Must be this.
     * @param _value Number of tokens the token holder balance is decreased by.
     * @param _data Optional data sent with the transfer. Used to set the destination partition.
     */
    function tokensReceived(
        bytes4, /* functionSig */
        bytes32 _partition,
        address _operator,
        address, /* from */
        address _to,
        uint256 _value,
        bytes calldata _data,
        bytes calldata /* operatorData */
    ) external override {
        require(msg.sender == amp, "Invalid sender");

        bytes32 _destinationPartition = _getDestinationPartition(_partition, _data);

        require(_canReceive(_to, _destinationPartition), "Receipt unauthorized");

        supplyNonce = SafeMath.add(supplyNonce, 1);
        nonceToSupply[supplyNonce].supplier = _operator;
        nonceToSupply[supplyNonce].partition = _destinationPartition;
        nonceToSupply[supplyNonce].amount = _value;

        emit SupplyReceipt(_operator, _destinationPartition, _value, supplyNonce);
    }

    /**********************************************************************************************
     * IAmpTokensSender Hooks
     *********************************************************************************************/

    /**
     * @notice Validates where the supplied parameters are valid for a transfer of tokens from this
     * contract
     * @dev Implements IAmpTokensSender
     * @param _partition Source partition of the tokens
     * @param _operator Address which triggered the transfer
     * @param _from The source address of the tokens. Must be this.
     * @param _value Amount of tokens to be transferred
     * @param _operatorData Extra information attached by the operator. Must include the transfer
     * operation flag and additional authorization data custom for each transfer operation type.
     * @return true if the token transfer would succeed, otherwise false
     */
    function canTransfer(
        bytes4, /*functionSig*/
        bytes32 _partition,
        address _operator,
        address _from,
        address, /* to */
        uint256 _value,
        bytes calldata, /* data */
        bytes calldata _operatorData
    ) external override view returns (bool) {
        if (msg.sender != amp || _from != address(this)) {
            return false;
        }

        bytes32 flag = _decodeOperatorDataFlag(_operatorData);

        if (flag == WITHDRAWAL_FLAG) {
            return _validateWithdrawal(_partition, _operator, _value, _operatorData);
        }
        if (flag == FALLBACK_WITHDRAWAL_FLAG) {
            return _validateFallbackWithdrawal(_partition, _operator, _value, _operatorData);
        }
        if (flag == REFUND_FLAG) {
            return _validateRefund(_partition, _operator, _value, _operatorData);
        }
        if (flag == CONSUMPTION_FLAG) {
            return _validateConsumption(_operator, _value);
        }

        return false;
    }

    /**
     * @notice Function called by the token contract when executing a transfer
     * @dev Implements IAmpTokensSender
     * @param _partition Source partition of the tokens
     * @param _operator Address which triggered the transfer
     * @param _from The source address of the tokens. Must be this.
     * @param _value Amount of tokens to be transferred
     * @param _operatorData Extra information attached by the operator. Must include the transfer
     * operation flag and additional authorization data custom for each transfer operation type.
     */
    function tokensToTransfer(
        bytes4, /* functionSig */
        bytes32 _partition,
        address _operator,
        address _from,
        address, /* to */
        uint256 _value,
        bytes calldata, /* data */
        bytes calldata _operatorData
    ) external override {
        require(msg.sender == amp, "Invalid sender");
        require(_from == address(this), "Invalid from address");

        bytes32 flag = _decodeOperatorDataFlag(_operatorData);

        if (flag == WITHDRAWAL_FLAG) {
            _executeWithdrawal(_partition, _operator, _value, _operatorData);
        } else if (flag == FALLBACK_WITHDRAWAL_FLAG) {
            _executeFallbackWithdrawal(_partition, _operator, _value, _operatorData);
        } else if (flag == REFUND_FLAG) {
            _executeRefund(_partition, _operator, _value, _operatorData);
        } else if (flag == CONSUMPTION_FLAG) {
            _executeConsumption(_partition, _operator, _value);
        } else {
            revert("invalid flag");
        }
    }

    /**********************************************************************************************
     * Withdrawals
     *********************************************************************************************/

    /**
     * @notice Validates withdrawal data
     * @param _partition Source partition of the withdrawal
     * @param _operator Address that is invoking the transfer
     * @param _value Number of tokens to be transferred
     * @param _operatorData Contains the withdrawal authorization data
     * @return true if the withdrawal data is valid, otherwise false
     */
    function _validateWithdrawal(
        bytes32 _partition,
        address _operator,
        uint256 _value,
        bytes memory _operatorData
    ) internal view returns (bool) {
        (
            address supplier,
            uint256 maxAuthorizedAccountNonce,
            uint256 withdrawalRootNonce
        ) = _getWithdrawalData(_partition, _value, _operatorData);

        return
            _validateWithdrawalData(
                _partition,
                _operator,
                _value,
                supplier,
                maxAuthorizedAccountNonce,
                withdrawalRootNonce
            );
    }

    /**
     * @notice Validates the withdrawal data and updates state to reflect the transfer
     * @param _partition Source partition of the withdrawal
     * @param _operator Address that is invoking the transfer
     * @param _value Number of tokens to be transferred
     * @param _operatorData Contains the withdrawal authorization data
     */
    function _executeWithdrawal(
        bytes32 _partition,
        address _operator,
        uint256 _value,
        bytes memory _operatorData
    ) internal {
        (
            address supplier,
            uint256 maxAuthorizedAccountNonce,
            uint256 withdrawalRootNonce
        ) = _getWithdrawalData(_partition, _value, _operatorData);

        require(
            _validateWithdrawalData(
                _partition,
                _operator,
                _value,
                supplier,
                maxAuthorizedAccountNonce,
                withdrawalRootNonce
            ),
            "Transfer unauthorized"
        );

        addressToCumulativeAmountWithdrawn[_partition][supplier] = SafeMath.add(
            _value,
            addressToCumulativeAmountWithdrawn[_partition][supplier]
        );

        addressToWithdrawalNonce[_partition][supplier] = withdrawalRootNonce;

        withdrawalLimit = SafeMath.sub(withdrawalLimit, _value);

        emit Withdrawal(
            supplier,
            _partition,
            _value,
            withdrawalRootNonce,
            maxAuthorizedAccountNonce
        );
    }

    /**
     * @notice Extracts withdrawal data from the supplied parameters
     * @param _partition Source partition of the withdrawal
     * @param _value Number of tokens to be transferred
     * @param _operatorData Contains the withdrawal authorization data, including the withdrawal
     * operation flag, supplier, maximum authorized account nonce, and Merkle proof.
     * @return supplier, the address whose account is authorized
     * @return maxAuthorizedAccountNonce, the maximum existing used withdrawal nonce for the
     * supplier and partition
     * @return withdrawalRootNonce, the active withdrawal root nonce found based on the supplied
     * data and Merkle proof
     */
    function _getWithdrawalData(
        bytes32 _partition,
        uint256 _value,
        bytes memory _operatorData
    )
        internal
        view
        returns (
            address, /* supplier */
            uint256, /* maxAuthorizedAccountNonce */
            uint256 /* withdrawalRootNonce */
        )
    {
        (
            address supplier,
            uint256 maxAuthorizedAccountNonce,
            bytes32[] memory merkleProof
        ) = _decodeWithdrawalOperatorData(_operatorData);

        bytes32 leafDataHash = _calculateWithdrawalLeaf(
            supplier,
            _partition,
            _value,
            maxAuthorizedAccountNonce
        );

        bytes32 calculatedRoot = _calculateMerkleRoot(merkleProof, leafDataHash);
        uint256 withdrawalRootNonce = withdrawalRootToNonce[calculatedRoot];

        return (supplier, maxAuthorizedAccountNonce, withdrawalRootNonce);
    }

    /**
     * @notice Validates that the parameters are valid for the requested withdrawal
     * @param _partition Source partition of the tokens
     * @param _operator Address that is executing the withdrawal
     * @param _value Number of tokens to be transferred
     * @param _supplier The address whose account is authorized
     * @param _maxAuthorizedAccountNonce The maximum existing used withdrawal nonce for the
     * supplier and partition
     * @param _withdrawalRootNonce The active withdrawal root nonce found based on the supplied
     * data and Merkle proof
     * @return true if the withdrawal data is valid, otherwise false
     */
    function _validateWithdrawalData(
        bytes32 _partition,
        address _operator,
        uint256 _value,
        address _supplier,
        uint256 _maxAuthorizedAccountNonce,
        uint256 _withdrawalRootNonce
    ) internal view returns (bool) {
        return
            // Only owner, withdrawal publisher or supplier can invoke withdrawals
            (_operator == owner || _operator == withdrawalPublisher || _operator == _supplier) &&
            // Ensure maxAuthorizedAccountNonce has not been exceeded
            (addressToWithdrawalNonce[_partition][_supplier] <= _maxAuthorizedAccountNonce) &&
            // Ensure we are within the global withdrawal limit
            (_value <= withdrawalLimit) &&
            // Merkle tree proof is valid
            (_withdrawalRootNonce > 0) &&
            // Ensure the withdrawal root is more recent than the maxAuthorizedAccountNonce
            (_withdrawalRootNonce > _maxAuthorizedAccountNonce);
    }

    /**
     * @notice Indicates that this address and partition would not like its withdrawable funds to
     * be available for withdrawal. This will prevent withdrawal for this address until the next
     * withdrawal root is published.
     * @dev The caller does not need to know or prove the details of the current withdrawal
     * authorization in order to renounce it.
     * @param _supplier The address whose account is authorized for withdrawal
     * @param _partition Source partition of the tokens
     */
    function renounceWithdrawalAuthorization(address _supplier, bytes32 _partition) external {
        require(
            msg.sender == owner || msg.sender == withdrawalPublisher || msg.sender == _supplier,
            "Invalid sender"
        );
        require(
            addressToWithdrawalNonce[_partition][_supplier] < maxWithdrawalRootNonce,
            "Authorization expired"
        );

        addressToWithdrawalNonce[_partition][_supplier] = maxWithdrawalRootNonce;

        emit RenounceWithdrawalAuthorization(_supplier, _partition, maxWithdrawalRootNonce);
    }

    /**********************************************************************************************
     * Fallback Withdrawals
     *********************************************************************************************/

    /**
     * @notice Validates fallback withdrawal data
     * @param _partition Source partition of the withdrawal
     * @param _operator Address that is invoking the transfer
     * @param _value Number of tokens to be transferred
     * @param _operatorData Contains the fallback withdrawal authorization data
     * @return true if the fallback withdrawal data is valid, otherwise false
     */
    function _validateFallbackWithdrawal(
        bytes32 _partition,
        address _operator,
        uint256 _value,
        bytes memory _operatorData
    ) internal view returns (bool) {
        (
            address supplier,
            uint256 maxCumulativeWithdrawalAmount,
            uint256 newCumulativeWithdrawalAmount,
            bytes32 calculatedRoot
        ) = _getFallbackWithdrawalData(_partition, _value, _operatorData);

        return
            _validateFallbackWithdrawalData(
                _operator,
                maxCumulativeWithdrawalAmount,
                newCumulativeWithdrawalAmount,
                supplier,
                calculatedRoot
            );
    }

    /**
     * @notice Validates the fallback withdrawal data and updates state to reflect the transfer
     * @param _partition Source partition of the withdrawal
     * @param _operator Address that is invoking the transfer
     * @param _value Number of tokens to be transferred
     * @param _operatorData Contains the fallback withdrawal authorization data
     */
    function _executeFallbackWithdrawal(
        bytes32 _partition,
        address _operator,
        uint256 _value,
        bytes memory _operatorData
    ) internal {
        (
            address supplier,
            uint256 maxCumulativeWithdrawalAmount,
            uint256 newCumulativeWithdrawalAmount,
            bytes32 calculatedRoot
        ) = _getFallbackWithdrawalData(_partition, _value, _operatorData);

        require(
            _validateFallbackWithdrawalData(
                _operator,
                maxCumulativeWithdrawalAmount,
                newCumulativeWithdrawalAmount,
                supplier,
                calculatedRoot
            ),
            "Transfer unauthorized"
        );

        addressToCumulativeAmountWithdrawn[_partition][supplier] = newCumulativeWithdrawalAmount;

        addressToWithdrawalNonce[_partition][supplier] = maxWithdrawalRootNonce;

        emit FallbackWithdrawal(supplier, _partition, _value);
    }

    /**
     * @notice Extracts withdrawal data from the supplied parameters
     * @param _partition Source partition of the withdrawal
     * @param _value Number of tokens to be transferred
     * @param _operatorData Contains the fallback withdrawal authorization data, including the
     * fallback withdrawal operation flag, supplier, max cumulative withdrawal amount, and Merkle
     * proof.
     * @return supplier, the address whose account is authorized
     * @return maxCumulativeWithdrawalAmount, the maximum amount of tokens that can be withdrawn
     * for the supplier's account, including both withdrawals and fallback withdrawals
     * @return newCumulativeWithdrawalAmount, the new total of all withdrawals include the
     * current request
     * @return calculatedRoot, the Merkle tree root calculated based on the supplied data and proof
     */
    function _getFallbackWithdrawalData(
        bytes32 _partition,
        uint256 _value,
        bytes memory _operatorData
    )
        internal
        view
        returns (
            address, /* supplier */
            uint256, /* maxCumulativeWithdrawalAmount */
            uint256, /* newCumulativeWithdrawalAmount */
            bytes32 /* calculatedRoot */
        )
    {
        (
            address supplier,
            uint256 maxCumulativeWithdrawalAmount,
            bytes32[] memory merkleProof
        ) = _decodeWithdrawalOperatorData(_operatorData);

        uint256 newCumulativeWithdrawalAmount = SafeMath.add(
            _value,
            addressToCumulativeAmountWithdrawn[_partition][supplier]
        );

        bytes32 leafDataHash = _calculateFallbackLeaf(
            supplier,
            _partition,
            maxCumulativeWithdrawalAmount
        );
        bytes32 calculatedRoot = _calculateMerkleRoot(merkleProof, leafDataHash);

        return (
            supplier,
            maxCumulativeWithdrawalAmount,
            newCumulativeWithdrawalAmount,
            calculatedRoot
        );
    }

    /**
     * @notice Validates that the parameters are valid for the requested fallback withdrawal
     * @param _operator Address that is executing the withdrawal
     * @param _maxCumulativeWithdrawalAmount, the maximum amount of tokens that can be withdrawn
     * for the supplier's account, including both withdrawals and fallback withdrawals
     * @param _newCumulativeWithdrawalAmount, the new total of all withdrawals include the
     * current request
     * @param _supplier The address whose account is authorized
     * @param _calculatedRoot The Merkle tree root calculated based on the supplied data and proof
     * @return true if the fallback withdrawal data is valid, otherwise false
     */
    function _validateFallbackWithdrawalData(
        address _operator,
        uint256 _maxCumulativeWithdrawalAmount,
        uint256 _newCumulativeWithdrawalAmount,
        address _supplier,
        bytes32 _calculatedRoot
    ) internal view returns (bool) {
        return
            // Only owner or supplier can invoke the fallback withdrawal
            (_operator == owner || _operator == _supplier) &&
            // Ensure we have entered fallback mode
            (SafeMath.add(fallbackSetDate, fallbackWithdrawalDelaySeconds) <= block.timestamp) &&
            // Check that the maximum allowable withdrawal for the supplier has not been exceeded
            (_newCumulativeWithdrawalAmount <= _maxCumulativeWithdrawalAmount) &&
            // Merkle tree proof is valid
            (fallbackRoot == _calculatedRoot);
    }

    /**********************************************************************************************
     * Supply Refunds
     *********************************************************************************************/

    /**
     * @notice Validates refund data
     * @param _partition Source partition of the refund
     * @param _operator Address that is invoking the transfer
     * @param _value Number of tokens to be transferred
     * @param _operatorData Contains the refund authorization data
     * @return true if the refund data is valid, otherwise false
     */
    function _validateRefund(
        bytes32 _partition,
        address _operator,
        uint256 _value,
        bytes memory _operatorData
    ) internal view returns (bool) {
        (uint256 _supplyNonce, Supply memory supply) = _getRefundData(_operatorData);

        return _verifyRefundData(_partition, _operator, _value, _supplyNonce, supply);
    }

    /**
     * @notice Validates the refund data and updates state to reflect the transfer
     * @param _partition Source partition of the refund
     * @param _operator Address that is invoking the transfer
     * @param _value Number of tokens to be transferred
     * @param _operatorData Contains the refund authorization data
     */
    function _executeRefund(
        bytes32 _partition,
        address _operator,
        uint256 _value,
        bytes memory _operatorData
    ) internal {
        (uint256 nonce, Supply memory supply) = _getRefundData(_operatorData);

        require(
            _verifyRefundData(_partition, _operator, _value, nonce, supply),
            "Transfer unauthorized"
        );

        delete nonceToSupply[nonce];

        emit SupplyRefund(supply.supplier, _partition, supply.amount, nonce);
    }

    /**
     * @notice Extracts refund data from the supplied parameters
     * @param _operatorData Contains the refund authorization data, including the refund
     * operation flag and supply nonce.
     * @return supplyNonce, nonce of the recorded supply
     * @return supply, The supplier, partition and amount of tokens in the original supply
     */
    function _getRefundData(bytes memory _operatorData)
        internal
        view
        returns (uint256, Supply memory)
    {
        uint256 _supplyNonce = _decodeRefundOperatorData(_operatorData);
        Supply memory supply = nonceToSupply[_supplyNonce];

        return (_supplyNonce, supply);
    }

    /**
     * @notice Validates that the parameters are valid for the requested refund
     * @param _partition Source partition of the tokens
     * @param _operator Address that is executing the refund
     * @param _value Number of tokens to be transferred
     * @param _supplyNonce nonce of the recorded supply
     * @param _supply The supplier, partition and amount of tokens in the original supply
     * @return true if the refund data is valid, otherwise false
     */
    function _verifyRefundData(
        bytes32 _partition,
        address _operator,
        uint256 _value,
        uint256 _supplyNonce,
        Supply memory _supply
    ) internal view returns (bool) {
        return
            // Supply record exists
            (_supply.amount > 0) &&
            // Only owner or supplier can invoke the refund
            (_operator == owner || _operator == _supply.supplier) &&
            // Requested partition matches the Supply record
            (_partition == _supply.partition) &&
            // Requested value matches the Supply record
            (_value == _supply.amount) &&
            // Ensure we have entered fallback mode
            (SafeMath.add(fallbackSetDate, fallbackWithdrawalDelaySeconds) <= block.timestamp) &&
            // Supply has not already been included in the fallback withdrawal data
            (_supplyNonce > fallbackMaxIncludedSupplyNonce);
    }

    /**********************************************************************************************
     * Consumption
     *********************************************************************************************/

    /**
     * @notice Validates consumption data
     * @param _operator Address that is invoking the transfer
     * @param _value Number of tokens to be transferred
     * @return true if the consumption data is valid, otherwise false
     */
    function _validateConsumption(address _operator, uint256 _value) internal view returns (bool) {
        return
            // Only owner and consumer can invoke withdrawals
            (_operator == owner || _operator == consumer) &&
            // Ensure we are within the global withdrawal limit
            (_value <= withdrawalLimit);
    }

    /**
     * @notice Validates the consumption data and updates state to reflect the transfer
     * @param _partition Source partition of the consumption
     * @param _operator Address that is invoking the transfer
     * @param _value Number of tokens to be transferred
     */
    function _executeConsumption(
        bytes32 _partition,
        address _operator,
        uint256 _value
    ) internal {
        require(_validateConsumption(_operator, _value), "Transfer unauthorized");

        withdrawalLimit = SafeMath.sub(withdrawalLimit, _value);

        emit Consumption(_operator, _partition, _value);
    }

    /**********************************************************************************************
     * Release Request
     *********************************************************************************************/

    /**
     * @notice Emits a release request event that can be used to trigger the release of tokens
     * @param _partition Parition from which the tokens should be released
     * @param _amount  Number of tokens requested to be released
     */
    function requestRelease(bytes32 _partition, uint256 _amount) external {
        emit ReleaseRequest(msg.sender, _partition, _amount);
    }

    /**********************************************************************************************
     * Partition Management
     *********************************************************************************************/

    /**
     * @notice Adds a partition to the set allowed to receive tokens
     * @param _partition Parition to be permitted for incoming transfers
     */
    function addPartition(bytes32 _partition) external {
        require(msg.sender == owner || msg.sender == partitionManager, "Invalid sender");
        require(partitions[_partition] == false, "Partition already permitted");

        (bytes4 prefix, address partitionOwner) = _splitPartition(_partition);

        require(prefix == PARTITION_PREFIX, "Invalid partition prefix");
        require(partitionOwner == address(this), "Invalid partition owner");

        partitions[_partition] = true;

        emit PartitionAdded(_partition);
    }

    /**
     * @notice Removes a partition from the set allowed to receive tokens
     * @param _partition Parition to be disallowed from incoming transfers
     */
    function removePartition(bytes32 _partition) external {
        require(msg.sender == owner || msg.sender == partitionManager, "Invalid sender");
        require(partitions[_partition], "Partition not permitted");

        delete partitions[_partition];

        emit PartitionRemoved(_partition);
    }

    /**********************************************************************************************
     * Withdrawal Management
     *********************************************************************************************/

    /**
     * @notice Modifies the withdrawal limit by the provided amount.
     * @param _amount Limit delta
     */
    function modifyWithdrawalLimit(int256 _amount) external {
        require(msg.sender == owner || msg.sender == withdrawalLimitPublisher, "Invalid sender");
        uint256 oldLimit = withdrawalLimit;
        if (_amount < 0) {
            uint256 unsignedAmount = uint256(-_amount);
            withdrawalLimit = SafeMath.sub(withdrawalLimit, unsignedAmount);
        } else {
            uint256 unsignedAmount = uint256(_amount);
            withdrawalLimit = SafeMath.add(withdrawalLimit, unsignedAmount);
        }
        emit WithdrawalLimitUpdate(oldLimit, withdrawalLimit);
    }

    /**
     * @notice Adds the root hash of a Merkle tree containing authorized token withdrawals to the
     * active set
     * @param _root The root hash to be added to the active set
     * @param _nonce The nonce of the new root hash. Must be exactly one higher than the existing
     * max nonce.
     * @param _replacedRoots The root hashes to be removed from the repository.
     */
    function addWithdrawalRoot(
        bytes32 _root,
        uint256 _nonce,
        bytes32[] calldata _replacedRoots
    ) external {
        require(msg.sender == owner || msg.sender == withdrawalPublisher, "Invalid sender");

        require(_root != 0, "Invalid root");
        require(maxWithdrawalRootNonce + 1 == _nonce, "Nonce not current max plus one");
        require(withdrawalRootToNonce[_root] == 0, "Nonce already used");

        withdrawalRootToNonce[_root] = _nonce;
        maxWithdrawalRootNonce = _nonce;

        emit WithdrawalRootHashAddition(_root, _nonce);

        for (uint256 i = 0; i < _replacedRoots.length; i++) {
            deleteWithdrawalRoot(_replacedRoots[i]);
        }
    }

    /**
     * @notice Removes withdrawal root hashes from active set
     * @param _roots The root hashes to be removed from the active set
     */
    function removeWithdrawalRoots(bytes32[] calldata _roots) external {
        require(msg.sender == owner || msg.sender == withdrawalPublisher, "Invalid sender");

        for (uint256 i = 0; i < _roots.length; i++) {
            deleteWithdrawalRoot(_roots[i]);
        }
    }

    /**
     * @notice Removes a withdrawal root hash from active set
     * @param _root The root hash to be removed from the active set
     */
    function deleteWithdrawalRoot(bytes32 _root) private {
        uint256 nonce = withdrawalRootToNonce[_root];

        require(nonce > 0, "Root not found");

        delete withdrawalRootToNonce[_root];

        emit WithdrawalRootHashRemoval(_root, nonce);
    }

    /**********************************************************************************************
     * Fallback Management
     *********************************************************************************************/

    /**
     * @notice Sets the root hash of the Merkle tree containing fallback
     * withdrawal authorizations.
     * @param _root The root hash of a Merkle tree containing the fallback withdrawal
     * authorizations
     * @param _maxSupplyNonce The nonce of the latest supply whose value is reflected in the
     * fallback withdrawal authorizations.
     */
    function setFallbackRoot(bytes32 _root, uint256 _maxSupplyNonce) external {
        require(msg.sender == owner || msg.sender == fallbackPublisher, "Invalid sender");
        require(_root != 0, "Invalid root");
        require(
            SafeMath.add(fallbackSetDate, fallbackWithdrawalDelaySeconds) > block.timestamp,
            "Fallback is active"
        );
        require(
            _maxSupplyNonce >= fallbackMaxIncludedSupplyNonce,
            "Included supply nonce decreased"
        );
        require(_maxSupplyNonce <= supplyNonce, "Included supply nonce exceeds latest supply");

        fallbackRoot = _root;
        fallbackMaxIncludedSupplyNonce = _maxSupplyNonce;
        fallbackSetDate = block.timestamp;

        emit FallbackRootHashSet(_root, fallbackMaxIncludedSupplyNonce, block.timestamp);
    }

    /**
     * @notice Resets the fallback set date to the current block's timestamp. This can be used to
     * delay the start of the fallback period without publishing a new root, or to deactivate the
     * fallback mechanism so a new fallback root may be published.
     */
    function resetFallbackMechanismDate() external {
        require(msg.sender == owner || msg.sender == fallbackPublisher, "Invalid sender");
        fallbackSetDate = block.timestamp;

        emit FallbackMechanismDateReset(fallbackSetDate);
    }

    /**
     * @notice Updates the time-lock period before the fallback mechanism is activated after the
     * last fallback root was published.
     * @param _newFallbackDelaySeconds The new delay period in seconds
     */
    function setFallbackWithdrawalDelay(uint256 _newFallbackDelaySeconds) external {
        require(msg.sender == owner, "Invalid sender");
        require(_newFallbackDelaySeconds != 0, "Invalid zero delay seconds");
        require(_newFallbackDelaySeconds < 10 * 365 days, "Invalid delay over 10 years");

        uint256 oldDelay = fallbackWithdrawalDelaySeconds;
        fallbackWithdrawalDelaySeconds = _newFallbackDelaySeconds;

        emit FallbackWithdrawalDelayUpdate(oldDelay, _newFallbackDelaySeconds);
    }

    /**********************************************************************************************
     * Role Management
     *********************************************************************************************/

    /**
     * @notice Authorizes the transfer of ownership from owner to the provided address.
     * NOTE: No transfer will occur unless authorizedAddress calls assumeOwnership().
     * This authorization may be removed by another call to this function authorizing the zero
     * address.
     * @param _authorizedAddress The address authorized to become the new owner
     */
    function authorizeOwnershipTransfer(address _authorizedAddress) external {
        require(msg.sender == owner, "Invalid sender");

        authorizedNewOwner = _authorizedAddress;

        emit OwnershipTransferAuthorization(authorizedNewOwner);
    }

    /**
     * @notice Transfers ownership of this contract to the authorizedNewOwner
     * @dev Error invalid sender.
     */
    function assumeOwnership() external {
        require(msg.sender == authorizedNewOwner, "Invalid sender");
        address oldValue = owner;
        owner = authorizedNewOwner;
        authorizedNewOwner = address(0);

        emit OwnerUpdate(oldValue, owner);
    }

    /**
     * @notice Updates the Withdrawal Publisher address, the only address other than the owner that
     * can publish / remove withdrawal Merkle tree roots.
     * @param _newWithdrawalPublisher The address of the new Withdrawal Publisher
     * @dev Error invalid sender.
     */
    function setWithdrawalPublisher(address _newWithdrawalPublisher) external {
        require(msg.sender == owner, "Invalid sender");

        address oldValue = withdrawalPublisher;
        withdrawalPublisher = _newWithdrawalPublisher;

        emit WithdrawalPublisherUpdate(oldValue, withdrawalPublisher);
    }

    /**
     * @notice Updates the Fallback Publisher address, the only address other than the owner that
     * can publish / remove fallback withdrawal Merkle tree roots.
     * @param _newFallbackPublisher The address of the new Fallback Publisher
     * @dev Error invalid sender.
     */
    function setFallbackPublisher(address _newFallbackPublisher) external {
        require(msg.sender == owner, "Invalid sender");

        address oldValue = fallbackPublisher;
        fallbackPublisher = _newFallbackPublisher;

        emit FallbackPublisherUpdate(oldValue, fallbackPublisher);
    }

    /**
     * @notice Updates the Withdrawal Limit Publisher address, the only address other than the
     * owner that can set the withdrawal limit.
     * @param _newWithdrawalLimitPublisher The address of the new Withdrawal Limit Publisher
     * @dev Error invalid sender.
     */
    function setWithdrawalLimitPublisher(address _newWithdrawalLimitPublisher) external {
        require(msg.sender == owner, "Invalid sender");

        address oldValue = withdrawalLimitPublisher;
        withdrawalLimitPublisher = _newWithdrawalLimitPublisher;

        emit WithdrawalLimitPublisherUpdate(oldValue, withdrawalLimitPublisher);
    }

    /**
     * @notice Updates the Consumer address, the only address other than the owner that can execute
     * supply consumptions.
     * @param _newConsumer The address of the new Consumer
     */
    function setConsumer(address _newConsumer) external {
        require(msg.sender == owner, "Invalid sender");

        address oldValue = consumer;
        consumer = _newConsumer;

        emit ConsumerUpdate(oldValue, consumer);
    }

    /**
     * @notice Updates the Partition Manager address, the only address other than the owner that
     * can add and remove permitted partitions
     * @param _newPartitionManager The address of the new PartitionManager
     */
    function setPartitionManager(address _newPartitionManager) external {
        require(msg.sender == owner, "Invalid sender");

        address oldValue = partitionManager;
        partitionManager = _newPartitionManager;

        emit PartitionManagerUpdate(oldValue, partitionManager);
    }

    /**********************************************************************************************
     * Partition Decoder
     *********************************************************************************************/

    /**
     * @notice Helper method to split the partition into the prefix, sub-partition and partition
     * owner components.
     * @param _partition The partition to be split into its subcomponents
     * @return prefix, the 4-byte partition prefix
     * @return partitionOwner, the 20-byte partition owner address
     */
    function _splitPartition(bytes32 _partition) internal pure returns (bytes4, address) {
        bytes4 prefix = bytes4(_partition);
        address paritionOwner = address(uint160(uint256(_partition)));

        return (prefix, paritionOwner);
    }

    /**********************************************************************************************
     * Data Decoders
     *********************************************************************************************/

    /**
     * @notice Retrieve the destination partition from the 'data' field. A partition change is
     * requested ONLY when 'data' starts with the flag:
     *
     *   0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
     *
     * When the flag is detected, the destination partition is extracted from the 32 bytes
     * following the flag.
     * @param _fromPartition Partition the tokens are transferred from.
     * @param _data Information attached to the transfer. Will contain the destination partition
     * if a change is requested.
     * @return toPartition Destination partition. If the `_data` does not contain the flag and bytes32
     * partition in the first 64 bytes, the method will return the provided _fromPartition.
     */
    function _getDestinationPartition(bytes32 _fromPartition, bytes memory _data)
        internal
        pure
        returns (bytes32 toPartition)
    {
        toPartition = _fromPartition;
        if (_data.length < 64) {
            return toPartition;
        }

        bytes32 flag;
        assembly {
            flag := mload(add(_data, 32))
        }
        if (flag == CHANGE_PARTITION_FLAG) {
            assembly {
                toPartition := mload(add(_data, 64))
            }
        }
    }

    /**********************************************************************************************
     * Operator Data Decoders
     *********************************************************************************************/

    /**
     * @notice Extract flag from operatorData
     * @param _operatorData The operator data to be decoded
     * @return flag, the transfer operation type
     */
    function _decodeOperatorDataFlag(bytes memory _operatorData) internal pure returns (bytes32) {
        bytes32 flag;
        assembly {
            flag := mload(add(_operatorData, 32))
        }
        return (flag);
    }

    /**
     * @notice Extracts the supplier, max authorized nonce, and Merkle proof from the operator data
     * @param _operatorData The operator data to be decoded
     * @return supplier, the address whose account is authorized
     * @return For withdrawals: max authorized nonce, the last used withdrawal root nonce for the
     * supplier and partition. For fallback withdrawals: max cumulative withdrawal amount, the
     * maximum amount of tokens that can be withdrawn for the supplier's account, including both
     * withdrawals and fallback withdrawals
     * @return proof, the Merkle proof to be used for the authorization
     */
    function _decodeWithdrawalOperatorData(bytes memory _operatorData)
        internal
        pure
        returns (
            address,
            uint256,
            bytes32[] memory
        )
    {
        bytes20 supplierB;
        assembly {
            supplierB := mload(add(_operatorData, 64))
        }
        address supplier = address(supplierB);

        bytes32 nonceB;
        assembly {
            nonceB := mload(add(_operatorData, 84))
        }
        uint256 nonce = uint256(nonceB);
        // SWC-128-DoS With Block Gas Limit: L1463-L1470
        uint256 proofNb = (_operatorData.length - 84) / 32;
        bytes32[] memory proof = new bytes32[](proofNb);
        uint256 index = 0;
        for (uint256 i = 116; i <= _operatorData.length; i = i + 32) {
            bytes32 temp;
            assembly {
                temp := mload(add(_operatorData, i))
            }
            proof[index] = temp;
            index++;
        }

        return (supplier, nonce, proof);
    }

    /**
     * @notice Extracts the supply nonce from the operator data
     * @param _operatorData The operator data to be decoded
     * @return nonce, the nonce of the supply to be refunded
     */
    function _decodeRefundOperatorData(bytes memory _operatorData) internal pure returns (uint256) {
        bytes32 nonceB;
        assembly {
            nonceB := mload(add(_operatorData, 64))
        }

        return uint256(nonceB);
    }

    /**********************************************************************************************
     * Merkle Tree Verification
     *********************************************************************************************/

    /**
     * @notice Hashes the supplied data and returns the hash to be used in conjunction with a proof
     * to calculate the Merkle tree root
     * @param _supplier The address whose account is authorized
     * @param _partition Source partition of the tokens
     * @param _value Number of tokens to be transferred
     * @param _maxAuthorizedAccountNonce The maximum existing used withdrawal nonce for the
     * supplier and partition
     * @return leaf, the hash of the supplied data
     */
    function _calculateWithdrawalLeaf(
        address _supplier,
        bytes32 _partition,
        uint256 _value,
        uint256 _maxAuthorizedAccountNonce
    ) internal pure returns (bytes32) {
        return
            keccak256(abi.encodePacked(_supplier, _partition, _value, _maxAuthorizedAccountNonce));
    }

    /**
     * @notice Hashes the supplied data and returns the hash to be used in conjunction with a proof
     * to calculate the Merkle tree root
     * @param _supplier The address whose account is authorized
     * @param _partition Source partition of the tokens
     * @param _maxCumulativeWithdrawalAmount, the maximum amount of tokens that can be withdrawn
     * for the supplier's account, including both withdrawals and fallback withdrawals
     * @return leaf, the hash of the supplied data
     */
    function _calculateFallbackLeaf(
        address _supplier,
        bytes32 _partition,
        uint256 _maxCumulativeWithdrawalAmount
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_supplier, _partition, _maxCumulativeWithdrawalAmount));
    }

    /**
     * @notice Calculates the Merkle root for the unique Merkle tree described by the provided
       Merkle proof and leaf hash.
     * @param _merkleProof The sibling node hashes at each level of the tree.
     * @param _leafHash The hash of the leaf data for which merkleProof is an inclusion proof.
     * @return The calculated Merkle root.
     */
    function _calculateMerkleRoot(bytes32[] memory _merkleProof, bytes32 _leafHash)
        private
        pure
        returns (bytes32)
    {
        bytes32 computedHash = _leafHash;

        for (uint256 i = 0; i < _merkleProof.length; i++) {
            bytes32 proofElement = _merkleProof[i];

            if (computedHash < proofElement) {
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }

        return computedHash;
    }
}
