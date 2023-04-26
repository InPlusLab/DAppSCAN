pragma solidity ^0.5.4;
pragma experimental ABIEncoderV2;

import "../../Lib/LibDerivative.sol";

import "../../Core.sol";
import "../../SyntheticAggregator.sol";

import "./MatchLogic.sol";

contract MatchPool is MatchLogic, LibDerivative {
    constructor (address _registry) public usingRegistry(_registry) {}
    
    function create(Order memory _buyOrder, Derivative memory _derivative) public nonReentrant {
        // PROBABLY TODO: Implement subtraction "Relayer" order and subtract before all

        // New pool deal must not offer tokenId
        require(
            _buyOrder.makerTokenId == 0,
            "MATCH:NOT_CREATION"
        );

        // Check if it's really pool
        require(IDerivativeLogic(_derivative.syntheticId).isPool(), "MATCH:NOT_POOL");

        // Validate sender if set
        validateSenderAddress(_buyOrder);

        // Validate expiration if set
        validateExpiration(_buyOrder);

        // Validate if was canceled
        bytes32 orderHash;
        orderHash = hashOrder(_buyOrder);
        validateCanceled(orderHash);
        validateSignature(orderHash, _buyOrder);

        uint256 margin = calculatePool(_buyOrder, _derivative);

        // Distribute fees to relayer and affiliate
        takeFees(orderHash, _buyOrder);

        IERC20 marginToken = IERC20(_derivative.token);

        // Transfer margin + premium from buyer to Match and distribute
        if (margin != 0) {
            // Check allowance for premiums + margins
            require(marginToken.allowance(_buyOrder.makerAddress, registry.getTokenSpender()) >= margin.mul(_buyOrder.takerTokenAmount), "MATCH:NOT_ENOUGH_ALLOWED_MARGIN");

            // Transfer margins from buyer to Match
            TokenSpender(registry.getTokenSpender()).claimTokens(marginToken, _buyOrder.makerAddress, address(this), margin.mul(_buyOrder.takerTokenAmount));

            require(marginToken.approve(registry.getTokenSpender(), margin.mul(_buyOrder.takerTokenAmount)), "MATCH:COULDNT_APPROVE_MARGIN_FOR_CORE");
        }

        Core(registry.getCore()).create(_derivative, _buyOrder.takerTokenAmount, [_buyOrder.makerAddress, address(0)]);
    }

    // PRIVATE FUNCTIONS

    function calculatePool(Order memory _buyOrder, Derivative memory _derivative) private returns (uint256 margin) {
        // Calculate derivative related data for validation
        bytes32 derivativeHash = getDerivativeHash(_derivative);
        uint256 longTokenId = derivativeHash.getLongTokenId();

        // New deals must request opposite position tokens
        require(
            _buyOrder.takerTokenId == longTokenId,
            "MATCH:DERIVATIVE_NOT_MATCH"
        );

        // Get cached margin required according to logic
        (margin, ) = SyntheticAggregator(registry.getSyntheticAggregator()).getMargin(derivativeHash, _derivative);
        
        // Validate that provided margin has the same currency that derivative
        require(
            margin == 0 || _buyOrder.makerMarginAddress == _derivative.token
            , "MATCH:PROVIDED_MARGIN_CURRENCY_WRONG"
        );

        // Validate that provided margin is enough for creating
        require(
            _buyOrder.makerMarginAmount >= _buyOrder.takerTokenAmount.mul(margin),
            "MATCH:PROVIDED_MARGIN_NOT_ENOUGH"
        );
    }
}
