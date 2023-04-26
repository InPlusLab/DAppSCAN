pragma solidity ^0.5.4;
pragma experimental ABIEncoderV2;

import "../../Lib/LibDerivative.sol";

import "../../Core.sol";
import "../../SyntheticAggregator.sol";

import "./MatchLogic.sol";

/// @title Opium.Matching.MatchCreate contract implements create() function to settle a pair of orders and create derivatives for order makers
contract MatchCreate is MatchLogic, LibDerivative {
    // Emmitted when new order pair was successfully settled
    event Create(bytes32 derivativeHash, address buyerPremiumAddress, uint256 buyerPremiumAmount, address sellerPremiumAddress, uint256 sellerPremiumAmount, uint256 filled);

    /// @notice This function receives buy and sell orders, derivative related to it and information whether buy order was first in orderbook (maker)
    /// @param _buyOrder Order Order of derivative buyer
    /// @param _sellOrder Order Order of derivative seller
    /// @param _derivative Derivative Data of derivative for validation and calculation purposes
    /// @param _buyerIsMaker bool Indicates whether buyer order came to orderbook first
    function create(Order memory _buyOrder, Order memory _sellOrder, Derivative memory _derivative, bool _buyerIsMaker) public nonReentrant {
        // New deals must not offer tokenIds
        require(
            _buyOrder.makerTokenId == _sellOrder.makerTokenId &&
            _sellOrder.makerTokenId == 0,
            "MATCH:NOT_CREATION"
        );

        // Check if it's not pooled positions
        require(!IDerivativeLogic(_derivative.syntheticId).isPool(), "MATCH:CANT_BE_POOL");

        // Validate taker if set
        validateTakerAddress(_buyOrder, _sellOrder);
        validateTakerAddress(_sellOrder, _buyOrder);

        // Validate sender if set
        validateSenderAddress(_buyOrder);
        validateSenderAddress(_sellOrder);

        // Validate expiration if set
        validateExpiration(_buyOrder);
        validateExpiration(_sellOrder);


        // Validate orders signatures and if orders were canceled
        // orderHashes[0] - buyOrderHash
        // orderHashes[1] - sellOrderHash
        bytes32[2] memory orderHashes;
        orderHashes[0] = hashOrder(_buyOrder);
        validateCanceled(orderHashes[0]);
        validateSignature(orderHashes[0], _buyOrder);

        orderHashes[1] = hashOrder(_sellOrder);
        validateCanceled(orderHashes[1]);
        validateSignature(orderHashes[1], _sellOrder);

        // Validates counterparty tokens and margin
        // Calculates available premiums
        // margins[0] - buyerMargin
        // margins[1] - sellerMargin
        (uint256[2] memory margins, bytes32 derivativeHash) = _validateDerivativeAndCalculateMargin(_buyOrder, _sellOrder, _derivative);

        // Premiums
        // premiums[0] - buyerReceivePremium
        // premiums[1] - sellerReceivePremium
        uint256[2] memory premiums;

        // If buyer requires premium on creation, should match with seller's margin token address
        // If buyer requires premium on creation, seller should provide at least the same premium or more
        // Returns buyer's premium for each contract
        premiums[0] = _validatePremium(_buyOrder, _sellOrder, margins[1], _buyerIsMaker);

        // If seller requires premium on creation, should match with buyer's margin token address
        // If seller requires premium on creation, buyer should provide at least the same premium or more
        // Returns seller's premium for each contract
        premiums[1] = _validatePremium(_sellOrder, _buyOrder, margins[0], !_buyerIsMaker);

        // Fill orders as much as possible
        // Returns available amount of positions to be filled
        uint256 fillPositions = _fillCreate(_buyOrder, orderHashes[0], _sellOrder, orderHashes[1]);

        // Take fees
        takeFees(orderHashes[0], _buyOrder);
        takeFees(orderHashes[1], _sellOrder);

        // Distribute margin and premium
        _distributeFunds(_buyOrder, _sellOrder, _derivative, margins, premiums, fillPositions);
        
        // Settle contracts
        Core(registry.getCore()).create(_derivative, fillPositions, [_buyOrder.makerAddress, _sellOrder.makerAddress]);
        
        emit Create(derivativeHash, _buyOrder.takerMarginAddress, premiums[0], _sellOrder.takerMarginAddress, premiums[1], fillPositions);
    }

    // PRIVATE FUNCTIONS

    /// @notice Validates derivative, tokenIds and gets required cached margin
    /// @param _buyOrder Order Order of derivative buyer
    /// @param _sellOrder Order Order of derivative seller
    /// @param _derivative Derivative Data of derivative for validation and calculation purposes
    /// @return margins uint256[2] buyer and seller margin array
    /// @return derivativeHash bytes32 Hash of derivative
    function _validateDerivativeAndCalculateMargin(Order memory _buyOrder, Order memory _sellOrder, Derivative memory _derivative) private returns (uint256[2] memory margins, bytes32 derivativeHash) {
        // Calculate derivative related data for validation
        derivativeHash = getDerivativeHash(_derivative);
        uint256 longTokenId = derivativeHash.getLongTokenId();
        uint256 shortTokenId = derivativeHash.getShortTokenId();

        // New deals must request opposite position tokens
        require(
            _buyOrder.takerTokenId != _sellOrder.takerTokenId &&
            _buyOrder.takerTokenId == longTokenId &&
            _sellOrder.takerTokenId == shortTokenId,
            "MATCH:DERIVATIVE_NOT_MATCH"
        );

        // Get cached total margin required according to logic
        // margins[0] - buyerMargin
        // margins[1] - sellerMargin
        (margins[0], margins[1]) = SyntheticAggregator(registry.getSyntheticAggregator()).getMargin(derivativeHash, _derivative);
        
        // Validate that provided margin token is the same as derivative margin token
        require(
            margins[0] == 0 || _buyOrder.makerMarginAddress == _derivative.token
            , "MATCH:PROVIDED_MARGIN_CURRENCY_WRONG"
        );
        require(
            margins[1] == 0 || _sellOrder.makerMarginAddress == _derivative.token
            , "MATCH:PROVIDED_MARGIN_CURRENCY_WRONG"
        );

        // Validate that provided margin is enough for creating new positions
        require(
            _buyOrder.makerMarginAmount >= _buyOrder.takerTokenAmount.mul(margins[0]) &&
            _sellOrder.makerMarginAmount >= _sellOrder.takerTokenAmount.mul(margins[1]),
            "MATCH:PROVIDED_MARGIN_NOT_ENOUGH"
        );
    }

    /// @notice Calculates and validates premium
    /// @param _leftOrder Order Order for which we calculate premium
    /// @param _rightOrder Order Counterparty order
    /// @param _rightOrderMargin uint256 Margin of counterparty order
    /// @param _leftIsMaker bool Whether left order first came to orderbook
    /// @return Returns left order premium
    function _validatePremium(Order memory _leftOrder, Order memory _rightOrder, uint256 _rightOrderMargin, bool _leftIsMaker) private pure returns(uint256) {
        // If order doesn't require premium, exit
        if (_leftOrder.takerMarginAmount == 0) {
            return 0; // leftReceivePremium is 0
        }

        // Validate premium/margin token address
        require(
            _leftOrder.takerMarginAddress == _rightOrder.makerMarginAddress,
            "MATCH:MARGIN_ADDRESS_NOT_MATCH"
        );

        // Calculate how much left order maker wants premium for each contract
        uint256 leftWantsPremium = _leftOrder.takerMarginAmount.div(_leftOrder.takerTokenAmount);
        // Calculate how much right order maker offers premium excluding margin required for derivative
        uint256 rightOffersPremium = _rightOrder.makerMarginAmount.div(_rightOrder.takerTokenAmount).sub(_rightOrderMargin);

        // Check if right order offers enough premium for left order
        require(
            leftWantsPremium <= rightOffersPremium,
            "MATCH:PREMIUM_IS_NOT_ENOUGH"
        );

        // Take premium of order, who first came to orderbook
        return _leftIsMaker ? leftWantsPremium : rightOffersPremium;
    }

    /// @notice Calculates orders fillability (available positions to fill) and validates
    /// @param _leftOrder Order 
    /// @param _leftOrderHash bytes32
    /// @param _rightOrder Order 
    /// @param _rightOrderHash bytes32
    /// @return fillPositions uint256 Available amount of positions to be filled
    function _fillCreate(Order memory _leftOrder, bytes32 _leftOrderHash, Order memory _rightOrder, bytes32 _rightOrderHash) private returns (uint256 fillPositions) {
        // Keep initial orders takerTokenAmount values
        uint256 leftInitial = _leftOrder.takerTokenAmount;
        uint256 rightInitial = _rightOrder.takerTokenAmount;

        // Calcualte already filled part
        uint256 leftAlreadyFilled = getInitialPercentageValue(filled[_leftOrderHash], _leftOrder.takerTokenAmount);
        uint256 rightAlreadyFilled = getInitialPercentageValue(filled[_rightOrderHash], _rightOrder.takerTokenAmount);

        // Subtract already filled part and calculate left order and right order available part
        (uint256 leftAvailable, uint256 rightAvailable) = (
            _leftOrder.takerTokenAmount.sub(leftAlreadyFilled), 
            _rightOrder.takerTokenAmount.sub(rightAlreadyFilled)
        );

        // We could only fill minimum available of both counterparties
        fillPositions = min(leftAvailable, rightAvailable);
        require(fillPositions > 0, "MATCH:NO_FILLABLE_POSITIONS");

        // Update filled
        // If initial takerTokenAmount was 0, set filled to 100%
        // Otherwise calculate new filled percetage -> (alreadyFilled + fill) / initial * 100%
        filled[_leftOrderHash] = leftInitial == 0 ? PERCENTAGE_BASE : getDivisionPercentage(leftAlreadyFilled.add(fillPositions), leftInitial).add(1);
        filled[_rightOrderHash] = rightInitial == 0 ? PERCENTAGE_BASE : getDivisionPercentage(rightAlreadyFilled.add(fillPositions), rightInitial).add(1);
    }

    /// @notice This function distributes premiums, takes margin and approves it to Core
    /// @param _buyOrder Order Order of derivative buyer
    /// @param _sellOrder Order Order of derivative seller
    /// @param _derivative Derivative Data of derivative for validation and calculation purposes
    /// @param margins uint256[2] Margins of buyer and seller
    /// @param premiums uint256[2] Premiums of buyer and seller
    /// @param fillPositions uint256 Quantity of positions to fill
    function _distributeFunds(
        Order memory _buyOrder,
        Order memory _sellOrder,
        Derivative memory _derivative,
        uint256[2] memory margins,
        uint256[2] memory premiums,
        uint256 fillPositions
    ) private {
        IERC20 marginToken = IERC20(_derivative.token);
        TokenSpender tokenSpender = TokenSpender(registry.getTokenSpender());

        // Transfer margin + premium from buyer to Match and distribute
        if (margins[0].add(premiums[1]) != 0) {
            // Check allowance for premiums + margins
            require(marginToken.allowance(_buyOrder.makerAddress, address(tokenSpender)) >= margins[0].add(premiums[1]).mul(fillPositions), "MATCH:NOT_ENOUGH_ALLOWED_MARGIN");

            if (premiums[1] != 0) {
                // Transfer premium to seller
                tokenSpender.claimTokens(marginToken, _buyOrder.makerAddress, _sellOrder.makerAddress, premiums[1].mul(fillPositions));
            }

            if (margins[0] != 0) {
                // Transfer margins from buyer to Match
                tokenSpender.claimTokens(marginToken, _buyOrder.makerAddress, address(this), margins[0].mul(fillPositions));
            }
        }
        
        // Transfer margin + premium from seller to Match and distribute
        if (margins[1].add(premiums[0]) != 0) {
            // Check allowance for premiums + margin
            require(marginToken.allowance(_sellOrder.makerAddress, address(tokenSpender)) >= margins[1].add(premiums[0]).mul(fillPositions), "MATCH:NOT_ENOUGH_ALLOWED_MARGIN");

            if (premiums[0] != 0) {
                // Transfer premium to buyer
                tokenSpender.claimTokens(marginToken, _sellOrder.makerAddress, _buyOrder.makerAddress, premiums[0].mul(fillPositions));
            }

            if (margins[1] != 0) {
                // Transfer margins from seller to Match
                tokenSpender.claimTokens(marginToken, _sellOrder.makerAddress, address(this), margins[1].mul(fillPositions));
            }
        }

        if (margins[0].add(margins[1]) != 0) {
            // Approve margin to Core for derivative creation
            require(marginToken.approve(address(tokenSpender), margins[0].add(margins[1]).mul(fillPositions)), "MATCH:COULDNT_APPROVE_MARGIN_FOR_CORE");
        }
    }
}
