pragma solidity ^0.5.4;
pragma experimental ABIEncoderV2;

import "openzeppelin-solidity/contracts/utils/ReentrancyGuard.sol";

import "./Lib/LibDerivative.sol";
import "./Lib/LibCommission.sol";

import "./Errors/SyntheticAggregatorErrors.sol";

import "./Interface/IOracleId.sol";
import "./Interface/IDerivativeLogic.sol";

/// @notice Opium.SyntheticAggregator contract initialized, identifies and caches syntheticId sensitive data
contract SyntheticAggregator is SyntheticAggregatorErrors, LibDerivative, LibCommission, ReentrancyGuard {
    // Emitted when new ticker is initialized
    event Create(Derivative derivative, bytes32 derivativeHash);

    // Enum for types of syntheticId
    // Invalid - syntheticId is not initialized yet
    // NotPool - syntheticId with p2p logic
    // Pool - syntheticId with pooled logic
    enum SyntheticTypes { Invalid, NotPool, Pool }

    // Cache of buyer margin by ticker
    // buyerMarginByHash[derivativeHash] = buyerMargin
    mapping (bytes32 => uint256) public buyerMarginByHash;

    // Cache of seller margin by ticker
    // sellerMarginByHash[derivativeHash] = sellerMargin
    mapping (bytes32 => uint256) public sellerMarginByHash;

    // Cache of type by ticker
    // typeByHash[derivativeHash] = type
    mapping (bytes32 => SyntheticTypes) public typeByHash;

    // Cache of commission by ticker
    // commissionByHash[derivativeHash] = commission
    mapping (bytes32 => uint256) public commissionByHash;

    // Cache of author addresses by ticker
    // authorAddressByHash[derivativeHash] = authorAddress
    mapping (bytes32 => address) public authorAddressByHash;

    // PUBLIC FUNCTIONS

    /// @notice Initializes ticker, if was not initialized and returns `syntheticId` author commission from cache
    /// @param _derivativeHash bytes32 Hash of derivative
    /// @param _derivative Derivative Derivative itself
    /// @return commission uint256 Synthetic author commission
    function getAuthorCommission(bytes32 _derivativeHash, Derivative memory _derivative) public nonReentrant returns (uint256 commission) {
        // Initialize derivative if wasn't initialized before
        _initDerivative(_derivativeHash, _derivative);
        commission = commissionByHash[_derivativeHash];
    }

    /// @notice Initializes ticker, if was not initialized and returns `syntheticId` author address from cache
    /// @param _derivativeHash bytes32 Hash of derivative
    /// @param _derivative Derivative Derivative itself
    /// @return authorAddress address Synthetic author address
    function getAuthorAddress(bytes32 _derivativeHash, Derivative memory _derivative) public nonReentrant returns (address authorAddress) {
        // Initialize derivative if wasn't initialized before
        _initDerivative(_derivativeHash, _derivative);
        authorAddress = authorAddressByHash[_derivativeHash];
    }

    /// @notice Initializes ticker, if was not initialized and returns buyer and seller margin from cache
    /// @param _derivativeHash bytes32 Hash of derivative
    /// @param _derivative Derivative Derivative itself
    /// @return buyerMargin uint256 Margin of buyer
    /// @return sellerMargin uint256 Margin of seller
    function getMargin(bytes32 _derivativeHash, Derivative memory _derivative) public nonReentrant returns (uint256 buyerMargin, uint256 sellerMargin) {
        // If it's a pool, just return margin from syntheticId contract
        if (_isPool(_derivativeHash, _derivative)) {
            return IDerivativeLogic(_derivative.syntheticId).getMargin(_derivative); 
        }

        // Initialize derivative if wasn't initialized before
        _initDerivative(_derivativeHash, _derivative);

        // Check if margins for _derivativeHash were already cached
        buyerMargin = buyerMarginByHash[_derivativeHash];
        sellerMargin = sellerMarginByHash[_derivativeHash];
    }

    /// @notice Checks whether `syntheticId` implements pooled logic
    /// @param _derivativeHash bytes32 Hash of derivative
    /// @param _derivative Derivative Derivative itself
    /// @return result bool Returns whether synthetic implements pooled logic
    function isPool(bytes32 _derivativeHash, Derivative memory _derivative) public nonReentrant returns (bool result) {
        result = _isPool(_derivativeHash, _derivative);
    }

    // PRIVATE FUNCTIONS

    /// @notice Initializes ticker, if was not initialized and returns whether `syntheticId` implements pooled logic
    /// @param _derivativeHash bytes32 Hash of derivative
    /// @param _derivative Derivative Derivative itself
    /// @return result bool Returns whether synthetic implements pooled logic
    function _isPool(bytes32 _derivativeHash, Derivative memory _derivative) private returns (bool result) {
        // Initialize derivative if wasn't initialized before
        _initDerivative(_derivativeHash, _derivative);
        result = typeByHash[_derivativeHash] == SyntheticTypes.Pool;
    }

    /// @notice Initializes ticker: caches syntheticId type, margin, author address and commission
    /// @param _derivativeHash bytes32 Hash of derivative
    /// @param _derivative Derivative Derivative itself
    function _initDerivative(bytes32 _derivativeHash, Derivative memory _derivative) private {
        // Check if type for _derivativeHash was already cached
        SyntheticTypes syntheticType = typeByHash[_derivativeHash];

        // Type could not be Invalid, thus this condition says us that type was not cached before
        if (syntheticType != SyntheticTypes.Invalid) {
            return;
        }

        // For security reasons we calculate hash of provided _derivative
        bytes32 derivativeHash = getDerivativeHash(_derivative);
        require(derivativeHash == _derivativeHash, ERROR_SYNTHETIC_AGGREGATOR_DERIVATIVE_HASH_NOT_MATCH);

        // POOL
        // Get isPool from SyntheticId
        bool result = IDerivativeLogic(_derivative.syntheticId).isPool();
        // Cache type returned from synthetic
        typeByHash[derivativeHash] = result ? SyntheticTypes.Pool : SyntheticTypes.NotPool;

        // MARGIN
        // Get margin from SyntheticId
        (uint256 buyerMargin, uint256 sellerMargin) = IDerivativeLogic(_derivative.syntheticId).getMargin(_derivative);
        // We are not allowing both margins to be equal to 0
        require(buyerMargin != 0 || sellerMargin != 0, ERROR_SYNTHETIC_AGGREGATOR_WRONG_MARGIN);
        // Cache margins returned from synthetic
        buyerMarginByHash[derivativeHash] = buyerMargin;
        sellerMarginByHash[derivativeHash] = sellerMargin;

        // AUTHOR ADDRESS
        // Cache author address returned from synthetic
        authorAddressByHash[derivativeHash] = IDerivativeLogic(_derivative.syntheticId).getAuthorAddress();

        // AUTHOR COMMISSION
        // Get commission from syntheticId
        uint256 commission = IDerivativeLogic(_derivative.syntheticId).getAuthorCommission();
        // Check if commission is not set > 100%
        require(commission <= COMMISSION_BASE, ERROR_SYNTHETIC_AGGREGATOR_COMMISSION_TOO_BIG);
        // Cache commission
        commissionByHash[derivativeHash] = commission;

        // If we are here, this basically means this ticker was not used before, so we emit an event for Dapps developers about new ticker (derivative) and it's hash
        emit Create(_derivative, derivativeHash);
    }
}
