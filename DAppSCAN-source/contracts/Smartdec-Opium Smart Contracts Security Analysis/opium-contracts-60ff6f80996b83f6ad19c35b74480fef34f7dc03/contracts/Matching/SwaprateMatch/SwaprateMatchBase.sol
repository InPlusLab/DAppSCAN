pragma solidity ^0.5.4;
pragma experimental ABIEncoderV2;

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";

import "erc721o/contracts/Libs/LibPosition.sol";

import "../../Lib/usingRegistry.sol";

import "../../Errors/MatchingErrors.sol";

import "./LibSwaprateOrder.sol";

import "../../Registry.sol";
import "../../Core.sol";
import "../../SyntheticAggregator.sol";

/// @title Opium.Matching.SwaprateMatchBase contract implements logic for order validation and cancelation
contract SwaprateMatchBase is MatchingErrors, LibSwaprateOrder, usingRegistry, ReentrancyGuard {
    using SafeMath for uint256;
    using LibPosition for bytes32;

    // Emmitted when order was canceled
    event Canceled(bytes32 orderHash);

    // Canceled orders
    // This mapping holds hashes of canceled orders
    // canceled[orderHash] => canceled
    mapping (bytes32 => bool) canceled;

    // Verified orders
    // This mapping holds hashes of verified orders to verify only once
    // verified[orderHash] => verified
    mapping (bytes32 => bool) verified;
    
    // Vaults for fees
    // This mapping holds balances of relayers and affiliates fees to withdraw
    // balances[feeRecipientAddress][tokenAddress] => balances
    mapping (address => mapping (address => uint256)) public balances;

    // Keeps whether fee was already taken
    mapping (bytes32 => bool) feeTaken;

    /// @notice Calling this function maker of the order could cancel it on-chain
    /// @param _order SwaprateOrder
    function cancel(SwaprateOrder memory _order) public {
        require(msg.sender == _order.makerAddress, ERROR_MATCH_CANCELLATION_NOT_ALLOWED);
        bytes32 orderHash = hashOrder(_order);
        require(!canceled[orderHash], ERROR_MATCH_ALREADY_CANCELED);
        canceled[orderHash] = true;

        emit Canceled(orderHash);
    }

    /// @notice Function to withdraw fees from orders for relayer and affiliates
    /// @param _token IERC20 Instance of token to withdraw
    function withdraw(IERC20 _token) public nonReentrant {
        uint256 balance = balances[msg.sender][address(_token)];
        balances[msg.sender][address(_token)] = 0;
        IERC20(address(0)).transfer(msg.sender, balance);
    }

    /// @notice This function checks whether order was canceled
    /// @param _hash bytes32 Hash of the order
    function validateCanceled(bytes32 _hash) internal view {
        require(!canceled[_hash], ERROR_MATCH_ORDER_WAS_CANCELED);
    }

    /// @notice This function validates takerAddress of _leftOrder. It should match either with _rightOrder.makerAddress or be set to zero address
    /// @param _leftOrder SwaprateOrder Left order
    /// @param _rightOrder SwaprateOrder Right order
    function validateTakerAddress(SwaprateOrder memory _leftOrder, SwaprateOrder memory _rightOrder) pure internal {
        require(
            _leftOrder.takerAddress == address(0) ||
            _leftOrder.takerAddress == _rightOrder.makerAddress,
            ERROR_MATCH_TAKER_ADDRESS_WRONG
        );
    }

    /// @notice This function validates whether sender address equals to `msg.sender` or set to zero address
    /// @param _order SwaprateOrder
    function validateSenderAddress(SwaprateOrder memory _order) internal view {
        require(
            _order.senderAddress == address(0) ||
            _order.senderAddress == msg.sender,
            ERROR_MATCH_SENDER_ADDRESS_WRONG
        );
    }

    /// @notice This function validates order signature if not validated before
    /// @param orderHash bytes32 Hash of the order
    /// @param _order SwaprateOrder
    function validateSignature(bytes32 orderHash, SwaprateOrder memory _order) internal {
        if (verified[orderHash]) {
            return;
        }

        bool result = verifySignature(orderHash, _order.signature, _order.makerAddress);

        require(result, ERROR_MATCH_SIGNATURE_NOT_VERIFIED);
        
        verified[orderHash] = true;
    }

    /// @notice This function is responsible for taking relayer and affiliate fees, if they were not taken already
    /// @param _orderHash bytes32 Hash of the order
    /// @param _order Order Order itself
    function takeFees(bytes32 _orderHash, SwaprateOrder memory _order) internal {
        // Check if fee was already taken
        if (feeTaken[_orderHash]) {
            return;
        }

        // Check if feeTokenAddress is not set to zero address
        if (_order.feeTokenAddress == address(0)) {
            return;
        }

        // Calculate total amount of fees needs to be transfered
        uint256 fees = _order.relayerFee.add(_order.affiliateFee);

        // If total amount of fees is non-zero
        if (fees == 0) {
            return;
        }

        // Create instance of fee token
        IERC20 feeToken = IERC20(_order.feeTokenAddress);

        // Check if user has enough token approval to pay the fees
        require(feeToken.allowance(_order.makerAddress, registry.getTokenSpender()) >= fees, ERROR_MATCH_NOT_ENOUGH_ALLOWED_FEES);
        // Transfer fee
        TokenSpender(registry.getTokenSpender()).claimTokens(feeToken, _order.makerAddress, address(this), fees);

        // Add commission to relayer balance, or to opium balance if relayer is not set
        if (_order.relayerAddress != address(0)) {
            balances[_order.relayerAddress][_order.feeTokenAddress] = balances[_order.relayerAddress][_order.feeTokenAddress].add(_order.relayerFee);
        } else {
            balances[registry.getOpiumAddress()][_order.feeTokenAddress] = balances[registry.getOpiumAddress()][_order.feeTokenAddress].add(_order.relayerFee);
        }

        // Add commission to affiliate balance, or to opium balance if affiliate is not set
        if (_order.affiliateAddress != address(0)) {
            balances[_order.affiliateAddress][_order.feeTokenAddress] = balances[_order.affiliateAddress][_order.feeTokenAddress].add(_order.affiliateFee);
        } else {
            balances[registry.getOpiumAddress()][_order.feeTokenAddress] = balances[registry.getOpiumAddress()][_order.feeTokenAddress].add(_order.affiliateFee);
        }

        // Mark the fee of token as taken
        feeTaken[_orderHash] = true;
    }

    /// @notice Helper to get minimal of two integers
    /// @param _a uint256 First integer
    /// @param _b uint256 Second integer
    /// @return uint256 Minimal integer
    function min(uint256 _a, uint256 _b) internal pure returns (uint256) {
        return _a < _b ? _a : _b;
    }
}
