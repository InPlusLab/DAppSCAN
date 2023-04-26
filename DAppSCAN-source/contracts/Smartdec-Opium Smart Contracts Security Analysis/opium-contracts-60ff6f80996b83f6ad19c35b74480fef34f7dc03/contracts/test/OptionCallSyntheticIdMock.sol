pragma solidity ^0.5.4;
pragma experimental ABIEncoderV2;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";

import "../Interface/IDerivativeLogic.sol";

import "../Helpers/ExecutableByThirdParty.sol";
import "../Helpers/HasCommission.sol";

contract OptionCallSyntheticIdMock is IDerivativeLogic, ExecutableByThirdParty, HasCommission {
    using SafeMath for uint256;

    uint256 constant BASE_PPT = 1 ether;
    
    constructor() public {
        /*
        {
            "author": "DIB.ONE",
            "type": "option",
            "subtype": "call",
            "description": "Option Call logic contract"
        }
        */
        emit MetadataSet("{\"author\":\"DIB.ONE\",\"type\":\"option\",\"subtype\":\"call\",\"description\":\"Option Call logic contract\"}");
    }

    function validateInput(Derivative memory _derivative) public view returns (bool) {
        if (_derivative.params.length < 1) {
            return false;
        }

        uint256 ppt;

        if (_derivative.params.length == 2) {
            ppt = _derivative.params[1];
        } else {
            ppt = BASE_PPT;
        }

        uint256 strikePrice = _derivative.params[0];
        return (
            _derivative.margin > 0 &&
            _derivative.endTime > now &&
            strikePrice > 0 &&
            ppt > 0
        );
    }

    function getMargin(Derivative memory _derivative) public view returns (uint256 buyerMargin, uint256 sellerMargin) {
        buyerMargin = 0;
        sellerMargin = _derivative.margin;
    }

    function getExecutionPayout(Derivative memory _derivative, uint256 _result)	public view returns (uint256 buyerPayout, uint256 sellerPayout) {
        uint256 ppt;

        uint256 strikePrice = _derivative.params[0];

        if (_derivative.params.length == 2) {
            ppt = _derivative.params[1];
        } else {
            ppt = BASE_PPT;
        }

        if (_result > strikePrice) {
            uint256 profit = _result.sub(strikePrice);
            profit = profit.mul(ppt).div(BASE_PPT);

            if (profit < _derivative.margin) {
                buyerPayout = profit;
                sellerPayout = _derivative.margin.sub(profit);
            } else {
                buyerPayout = _derivative.margin;
                sellerPayout = 0;
            }
        } else {
            buyerPayout = 0;
            sellerPayout = _derivative.margin;
        }
    }

    function isPool() public view returns (bool) {
        return false;
    }
}