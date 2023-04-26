pragma solidity ^0.5.4;
pragma experimental ABIEncoderV2;

import "./MatchLogic.sol";

import "../../TokenMinter.sol";

/// @title Opium.Matching.MatchSwap contract implements swap() function to make TMtm swap
/// TMtm swap is swaps of Token + Margin to Token + MArgin
contract MatchSwap is MatchLogic {
    // Emmited when swap is made
    event Swap(
        uint256 leftMakerTokenId, uint256 leftMakerTokenAmount,
        address leftMakerMarginAddress, uint256 leftMakerMarginAmount,
        uint256 rightMakerTokenId, uint256 rightMakerTokenAmount,
        address rightMakerMarginAddress, uint256 rightMakerMarginAmount
    );

    /// @notice This function receives left and right orders, and performs swap of Token + Margin to Token + Margin swaps
    /// @param _leftOrder Order
    /// @param _rightOrder Order
    function swap(Order memory _leftOrder, Order memory _rightOrder) public nonReentrant {
        // Validate taker if set
        validateTakerAddress(_leftOrder, _rightOrder);
        validateTakerAddress(_rightOrder, _leftOrder);

        // Validate sender if set
        validateSenderAddress(_leftOrder);
        validateSenderAddress(_rightOrder);

        // Validate expiration if set
        validateExpiration(_leftOrder);
        validateExpiration(_rightOrder);


        // Validate if was canceled
        // orderHashes[0] - leftOrderHash
        // orderHashes[1] - rightOrderHash
        bytes32[2] memory orderHashes;
        orderHashes[0] = hashOrder(_leftOrder);
        validateCanceled(orderHashes[0]);
        validateSignature(orderHashes[0], _leftOrder);

        orderHashes[1] = hashOrder(_rightOrder);
        validateCanceled(orderHashes[1]);
        validateSignature(orderHashes[1], _rightOrder);

        // Validate if values are correct
        // Fill orders as much as possible
        // leftFill[0] - Tokens that left sends to right
        // leftFill[1] - Margin that left sends to right
        // rightFill[0] - Tokens that right sends to left
        // rightFill[1] - Margin that right sends to left
        (uint256[2] memory leftFill, uint256[2] memory rightFill) = _validateOffersAndFillSwap(_leftOrder, orderHashes[0], _rightOrder, orderHashes[1]);

        // Take fees
        takeFees(orderHashes[0], _leftOrder);
        takeFees(orderHashes[1], _rightOrder);

        // Validate if swap is possible and make it
        _validateAndMakeSwap(_leftOrder, leftFill, _rightOrder, rightFill);
    }

    /// @notice Validates Orders according to TMtm logic and calculates fillability
    /// @param _leftOrder Order
    /// @param _leftOrderHash bytes32
    /// @param _rightOrder Order
    /// @param _rightOrderHash bytes32
    /// @return leftFill uint256[2] Left fillability
    /// @return rightFill uint256[2] Right fillability
    function _validateOffersAndFillSwap(Order memory _leftOrder, bytes32 _leftOrderHash, Order memory _rightOrder, bytes32 _rightOrderHash) private returns (uint256[2] memory leftFill, uint256[2] memory rightFill) {
        // Keep initial order takerTokenAmount and takerMarginAmount values
        uint256[2] memory leftInitial;
        uint256[2] memory rightInitial;
        leftInitial[0] = _leftOrder.takerTokenAmount;
        leftInitial[1] = _leftOrder.takerMarginAmount;
        rightInitial[0] = _rightOrder.takerTokenAmount;
        rightInitial[1] = _rightOrder.takerMarginAmount;
        
        // Calculates already filled part
        uint256[2] memory leftAlreadyFilled;
        leftAlreadyFilled[0] = getInitialPercentageValue(filled[_leftOrderHash], _leftOrder.takerTokenAmount);
        leftAlreadyFilled[1] = getInitialPercentageValue(filled[_leftOrderHash], _leftOrder.takerMarginAmount);
        _leftOrder.takerTokenAmount = _leftOrder.takerTokenAmount.sub(leftAlreadyFilled[0]);
        _leftOrder.takerMarginAmount = _leftOrder.takerMarginAmount.sub(leftAlreadyFilled[1]);

        // Subtract already filled part
        uint256[2] memory rightAlreadyFilled;
        rightAlreadyFilled[0] = getInitialPercentageValue(filled[_rightOrderHash], _rightOrder.takerTokenAmount);
        rightAlreadyFilled[1] = getInitialPercentageValue(filled[_rightOrderHash], _rightOrder.takerMarginAmount);
        _rightOrder.takerTokenAmount = _rightOrder.takerTokenAmount.sub(rightAlreadyFilled[0]);
        _rightOrder.takerMarginAmount = _rightOrder.takerMarginAmount.sub(rightAlreadyFilled[1]);

        // Calculate if swap is possible
        uint256[4] memory left;
        uint256[4] memory right;

        left[0] = _leftOrder.makerTokenAmount.mul(_rightOrder.makerTokenAmount);
        right[0] = _leftOrder.takerTokenAmount.mul(_rightOrder.takerTokenAmount);
        
        left[1] = _leftOrder.makerTokenAmount.mul(_rightOrder.makerMarginAmount);
        right[1] = _leftOrder.takerMarginAmount.mul(_rightOrder.takerTokenAmount);
        
        left[2] = _leftOrder.makerMarginAmount.mul(_rightOrder.makerTokenAmount);
        right[2] = _leftOrder.takerTokenAmount.mul(_rightOrder.takerMarginAmount);
        
        left[3] = _leftOrder.makerMarginAmount.mul(_rightOrder.makerMarginAmount);
        right[3] = _leftOrder.takerMarginAmount.mul(_rightOrder.takerMarginAmount);

        require(
            left[0] >= right[0] &&
            left[1] >= right[1] &&
            left[2] >= right[2] &&
            left[3] >= right[3],
            "MATCH:OFFERS_CONDITIONS_ARE_NOT_MET"
        );

        // Calculate fillable values
        leftFill[0] = min(_leftOrder.makerTokenAmount, _rightOrder.takerTokenAmount);
        leftFill[1] = min(_leftOrder.makerMarginAmount, _rightOrder.takerMarginAmount);

        rightFill[0] = min(_leftOrder.takerTokenAmount, _rightOrder.makerTokenAmount);
        rightFill[1] = min(_leftOrder.takerMarginAmount, _rightOrder.makerMarginAmount);
        require(
            leftFill[0] != 0 ||
            leftFill[1] != 0 ||
            rightFill[0] != 0 ||
            rightFill[1] != 0
            , "MATCH:NO_FILLABLE_POSITIONS");

        // Update filled
        // See Match.create()
        uint256[2] memory leftFilledPercents;
        leftFilledPercents[0] = leftInitial[0] == 0 ? PERCENTAGE_BASE : getDivisionPercentage(leftAlreadyFilled[0].add(rightFill[0]), leftInitial[0]);
        leftFilledPercents[1] = leftInitial[1] == 0 ? PERCENTAGE_BASE : getDivisionPercentage(leftAlreadyFilled[1].add(rightFill[1]), leftInitial[1]);

        filled[_leftOrderHash] = min(leftFilledPercents[0], leftFilledPercents[1]).add(1);

        uint256[2] memory rightFilledPercents;
        rightFilledPercents[0] = rightInitial[0] == 0 ? PERCENTAGE_BASE : getDivisionPercentage(rightAlreadyFilled[0].add(leftFill[0]), rightInitial[0]);
        rightFilledPercents[1] = rightInitial[1] == 0 ? PERCENTAGE_BASE : getDivisionPercentage(rightAlreadyFilled[1].add(leftFill[1]), rightInitial[1]);

        filled[_rightOrderHash] = min(rightFilledPercents[0], rightFilledPercents[1]).add(1);
    }

    /// @notice Validate order properties and distribute tokens and margins
    /// @param _leftOrder Order
    /// @param leftFill uint256[2] Left order fillability
    /// @param _rightOrder Order
    /// @param rightFill uint256[2] Right order fillability
    function _validateAndMakeSwap(Order memory _leftOrder, uint256[2] memory leftFill, Order memory _rightOrder, uint256[2] memory rightFill) private {
        TokenMinter tm = TokenMinter(registry.getMinter());
        TokenSpender tokenSpender = TokenSpender(registry.getTokenSpender());

        // Transfer positions left -> right if needed
        if (leftFill[0] != 0) {
            require(_leftOrder.makerTokenId == _rightOrder.takerTokenId, "MATCH:NOT_VALID_SWAP");

            require(tm.isApprovedOrOwner(address(tokenSpender), _leftOrder.makerAddress, _leftOrder.makerTokenId), "MATCH:NOT_ALLOWED_POSITION");
            tokenSpender.claimPositions(tm, _leftOrder.makerAddress, _rightOrder.makerAddress, _leftOrder.makerTokenId, leftFill[0]);
        }
        
        // Transfer positions right -> left if needed
        if (rightFill[0] != 0) {
            require(_leftOrder.takerTokenId == _rightOrder.makerTokenId, "MATCH:NOT_VALID_SWAP");

            require(tm.isApprovedOrOwner(address(tokenSpender), _rightOrder.makerAddress, _rightOrder.makerTokenId), "MATCH:NOT_ALLOWED_POSITION");
            tokenSpender.claimPositions(tm, _rightOrder.makerAddress, _leftOrder.makerAddress, _rightOrder.makerTokenId, rightFill[0]);
        }

        // Transfer margin left -> right if needed
        if (leftFill[1] != 0) {
            require(_leftOrder.makerMarginAddress == _rightOrder.takerMarginAddress, "MATCH:NOT_VALID_SWAP");

            IERC20 makerMarginToken = IERC20(_leftOrder.makerMarginAddress);
            require(makerMarginToken.allowance(_leftOrder.makerAddress, address(tokenSpender)) >= leftFill[1], "MATCH:NOT_ENOUGH_ALLOWED_MARGIN");
            tokenSpender.claimTokens(makerMarginToken, _leftOrder.makerAddress, _rightOrder.makerAddress, leftFill[1]);
        }

        // Transfer margin right -> left if needed
        if (rightFill[1] != 0) {
            require(_leftOrder.takerMarginAddress == _rightOrder.makerMarginAddress, "MATCH:NOT_VALID_SWAP");

            IERC20 takerMarginToken = IERC20(_leftOrder.takerMarginAddress);
            require(takerMarginToken.allowance(_rightOrder.makerAddress, address(tokenSpender)) >= rightFill[1], "MATCH:NOT_ENOUGH_ALLOWED_MARGIN");
            tokenSpender.claimTokens(takerMarginToken, _rightOrder.makerAddress, _leftOrder.makerAddress, rightFill[1]);
        }

        emit Swap(
            _leftOrder.makerTokenId, leftFill[0],
            _leftOrder.makerMarginAddress, leftFill[1],
            _rightOrder.makerTokenId, rightFill[0],
            _rightOrder.makerMarginAddress, rightFill[1]
        );
    }
}
