// "SPDX-License-Identifier: GPL-3.0-or-later"

pragma solidity 0.7.6;

import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "./ICollateralSplit.sol";
import "../oracleIterators/IOracleIterator.sol";

abstract contract CollateralSplitParent is ICollateralSplit {
    using SignedSafeMath for int256;

    int256 public constant FRACTION_MULTIPLIER = 10**12;
    int256 public constant NEGATIVE_INFINITY = type(int256).min;

    function isCollateralSplit() external pure override returns (bool) {
        return true;
    }

    function split(
        address[] calldata _oracles,
        address[] calldata _oracleIterators,
        int256[] calldata _underlyingStarts,
        uint256 _settleTime,
        uint256[] calldata _underlyingEndRoundHints
    )
        external
        view
        virtual
        override
        returns (uint256 _split, int256[] memory _underlyingEnds)
    {
        require(_oracles.length == 1, "More than one oracle");
        require(_oracles[0] != address(0), "Oracle is empty");
        require(_oracleIterators[0] != address(0), "Oracle iterator is empty");

        _underlyingEnds = new int256[](1);

        IOracleIterator iterator = IOracleIterator(_oracleIterators[0]);
        require(iterator.isOracleIterator(), "Not oracle iterator");

        _underlyingEnds[0] = iterator.getUnderlyingValue(
            _oracles[0],
            _settleTime,
            _underlyingEndRoundHints
        );

        _split = range(
            splitNominalValue(
                normalize(_underlyingStarts[0], _underlyingEnds[0])
            )
        );
    }

    function splitNominalValue(int256 _normalizedValue)
        public
        pure
        virtual
        returns (int256);

    function normalize(int256 _u_0, int256 _u_T)
        public
        pure
        virtual
        returns (int256)
    {
        require(_u_0 != NEGATIVE_INFINITY, "u_0 is absent");
        require(_u_T != NEGATIVE_INFINITY, "u_T is absent");
        require(_u_0 > 0, "u_0 is less or equal zero");

        if (_u_T < 0) {
            _u_T = 0;
        }

        return _u_T.sub(_u_0).mul(FRACTION_MULTIPLIER).div(_u_0);
    }

    function range(int256 _split) public pure returns (uint256) {
        if (_split >= FRACTION_MULTIPLIER) {
            return uint256(FRACTION_MULTIPLIER);
        }
        if (_split <= 0) {
            return 0;
        }
        return uint256(_split);
    }
}
