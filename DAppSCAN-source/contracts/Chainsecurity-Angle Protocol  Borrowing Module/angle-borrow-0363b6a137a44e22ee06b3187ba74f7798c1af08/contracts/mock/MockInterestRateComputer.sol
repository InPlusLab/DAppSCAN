// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.12;

contract MockInterestRateComputer {
    uint256 public interestRate;
    uint256 public interestAccumulator;
    uint256 public immutable baseInterest;
    uint256 public immutable halfBase;

    uint256 public constant WEEK = 7 * 86400;

    constructor(uint256 _baseInterest, uint256 _interestRate) {
        interestAccumulator = _baseInterest;
        baseInterest = _baseInterest;
        halfBase = _baseInterest / 2;
        interestRate = _interestRate;
    }

    function _calculateAngle(uint256 exp, uint256 _interestAccumulator) internal view returns (uint256) {
        uint256 ratePerSecond = interestRate;
        if (exp == 0 || ratePerSecond == 0) return _interestAccumulator;
        uint256 expMinusOne = exp - 1;
        uint256 expMinusTwo = exp > 2 ? exp - 2 : 0;
        uint256 basePowerTwo = (ratePerSecond * ratePerSecond) / baseInterest;
        uint256 basePowerThree = (basePowerTwo * ratePerSecond) / baseInterest;
        uint256 secondTerm = (exp * expMinusOne * basePowerTwo) / 2;
        uint256 thirdTerm = (exp * expMinusOne * expMinusTwo * basePowerThree) / 6;
        return (_interestAccumulator * (baseInterest + ratePerSecond * exp + secondTerm + thirdTerm)) / baseInterest;
    }

    function _calculateAave(uint256 exp, uint256 _interestAccumulator) internal view returns (uint256) {
        uint256 ratePerSecond = interestRate;
        if (exp == 0 || ratePerSecond == 0) return _interestAccumulator;
        uint256 expMinusOne = exp - 1;
        uint256 expMinusTwo = exp > 2 ? exp - 2 : 0;
        uint256 basePowerTwo = (ratePerSecond * ratePerSecond + halfBase) / baseInterest;
        uint256 basePowerThree = (basePowerTwo * ratePerSecond + halfBase) / baseInterest;
        uint256 secondTerm = (exp * expMinusOne * basePowerTwo) / 2;
        uint256 thirdTerm = (exp * expMinusOne * expMinusTwo * basePowerThree) / 6;
        return (_interestAccumulator * (baseInterest + ratePerSecond * exp + secondTerm + thirdTerm)) / baseInterest;
    }

    function _rpow(
        uint256 x,
        uint256 n,
        uint256 base
    ) internal pure returns (uint256 z) {
        //solhint-disable-next-line
        assembly {
            switch x
            case 0 {
                switch n
                case 0 {
                    z := base
                }
                default {
                    z := 0
                }
            }
            default {
                switch mod(n, 2)
                case 0 {
                    z := base
                }
                default {
                    z := x
                }
                let half := div(base, 2) // for rounding.
                for {
                    n := div(n, 2)
                } n {
                    n := div(n, 2)
                } {
                    let xx := mul(x, x)
                    if iszero(eq(div(xx, x), x)) {
                        revert(0, 0)
                    }
                    let xxRound := add(xx, half)
                    if lt(xxRound, xx) {
                        revert(0, 0)
                    }
                    x := div(xxRound, base)
                    if mod(n, 2) {
                        let zx := mul(z, x)
                        if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) {
                            revert(0, 0)
                        }
                        let zxRound := add(zx, half)
                        if lt(zxRound, zx) {
                            revert(0, 0)
                        }
                        z := div(zxRound, base)
                    }
                }
            }
        }
    }

    function _calculateMaker(uint256 delta, uint256 _interestAccumulator) internal view returns (uint256) {
        return (_rpow(baseInterest + interestRate, delta, baseInterest) * _interestAccumulator) / baseInterest;
    }

    function calculateAngle(uint256 delta) external view returns (uint256) {
        return _calculateAngle(delta, interestAccumulator);
    }

    function calculateAave(uint256 delta) external view returns (uint256) {
        return _calculateAave(delta, interestAccumulator);
    }

    function calculateMaker(uint256 delta) external view returns (uint256) {
        return _calculateMaker(delta, interestAccumulator);
    }

    function calculateAngle1Year() external view returns (uint256) {
        uint256 _interestAccumulator = interestAccumulator;
        for (uint256 i = 0; i < 52; i++) {
            _interestAccumulator = _calculateAngle(WEEK, _interestAccumulator);
        }
        return _interestAccumulator;
    }

    function calculateAave1Year() external view returns (uint256) {
        uint256 _interestAccumulator = interestAccumulator;
        for (uint256 i = 0; i < 52; i++) {
            _interestAccumulator = _calculateAave(WEEK, _interestAccumulator);
        }
        return _interestAccumulator;
    }

    function calculateMaker1Year() external view returns (uint256) {
        uint256 _interestAccumulator = interestAccumulator;
        for (uint256 i = 0; i < 52; i++) {
            _interestAccumulator = _calculateMaker(WEEK, _interestAccumulator);
        }
        return _interestAccumulator;
    }

    function calculateAngle1YearDirect() external view returns (uint256) {
        uint256 _interestAccumulator = interestAccumulator;
        _interestAccumulator = _calculateAngle(52 * WEEK, _interestAccumulator);

        return _interestAccumulator;
    }

    function calculateAave1YearDirect() external view returns (uint256) {
        uint256 _interestAccumulator = interestAccumulator;
        _interestAccumulator = _calculateAave(52 * WEEK, _interestAccumulator);

        return _interestAccumulator;
    }

    function calculateMaker1YearDirect() external view returns (uint256) {
        uint256 _interestAccumulator = interestAccumulator;
        _interestAccumulator = _calculateMaker(52 * WEEK, _interestAccumulator);

        return _interestAccumulator;
    }
}
