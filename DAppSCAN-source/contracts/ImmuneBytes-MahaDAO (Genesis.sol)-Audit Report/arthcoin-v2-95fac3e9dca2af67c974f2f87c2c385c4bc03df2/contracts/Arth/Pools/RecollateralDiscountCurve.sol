// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Sigmoid} from '../../Curves/Sigmoid.sol';

contract RecollateralDiscountCurve is Sigmoid {
    constructor(
        uint256 _minX, // Ideally 0%.
        uint256 _maX, // Ideally should be 100%.
        uint256 minDiscount,
        uint256 maxDiscount,
        uint256[] memory slots // Should represent 1 - ( 0.6 * 1 / (1 + e^-5x) ).
    )
        Sigmoid(
            _minX,
            _maX,
            minDiscount,
            maxDiscount,
            false, // Decreasing curve(Discount decreases with time/collateral)
            slots
        )
    {
        // Slot values(0%- 30%), (100%- ~0.0069%).
        // slots[0] = 270099601612513200;  // 4%.
        // slots[1] = 240787403932528800;  // 8%.
        // slots[2] = 212606216264522750;  // 12%.
        // slots[3] = 186015311323432480;
        // slots[4] = 161364852821997060;
        // slots[5] = 138885129900589460;
        // slots[6] = 118689666864850910;
        // slots[7] = 100788968919645330;
        // slots[8] = 85110638940292770;
        // slots[9] = 71521753213270600;
        // slots[10] = 59850293471811120;
        // slots[11] = 49903617896353400;
        // slots[12] = 41483052206008160;
        // slots[13] = 34394505539321240;
        // slots[14] = 28455523906540110;
        // slots[15] = 23499433678058600;
        // slots[16] = 19377278819070276;
        // slots[17] = 15958196146119572;
        // slots[18] = 13128762561678342;
        // slots[19] = 10791725977254928;
        // slots[20] = 8864419015963841;
        // slots[21] = 7277060990564577;
        // slots[22] = 5971081120142552;
        // slots[23] = 4897542691895928;
    }
}
