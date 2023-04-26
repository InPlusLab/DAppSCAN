// Copyright (C) 2017  DappHub, LLC

// Licensed under the Apache License, Version 2.0 (the "License").
// You may not use this file except in compliance with the License.

// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND (express or implied).

pragma solidity ^0.5.2;

import '../utility/DSThing.sol';

contract DSValue is DSThing {
    bool    has;
    bytes32 val;
    function peek() public view returns (bytes32, bool) {
        return (val,has);
    }
    function read() public view returns (bytes32) {
        bytes32 wut; bool haz;
        (wut, haz) = peek();
        require(haz, "haz-not");
        return wut;
    }
    function poke(bytes32 wut) public note auth {
        val = wut;
        has = true;
    }
    function void() public note auth {  // unset the value
        has = false;
    }
}

contract Medianizer is DSValue {
    mapping (bytes12 => address) public values;
    mapping (address => bytes12) public indexes;
    bytes12 public next = bytes12(uint96(0x1));
    uint96 public _min = 1;

    function set(address wat) public auth {
        bytes12 nextId = bytes12(uint96(next) + 1);
        assert(nextId != 0x0);
        set(next, wat);
        next = nextId;
    }

    function set(bytes12 pos, address wat) public note auth {
        if (pos == 0x0) revert("Set: pos zero");

        if (wat != address(0) && indexes[wat] != 0) revert("Set: address not-zero");

        indexes[values[pos]] = 0; // Making sure to remove a possible existing address in that position

        if (wat != address(0)) {
            indexes[wat] = pos;
        }

        values[pos] = wat;
    }

    function setMin(uint96 min_) public note auth {
        if (min_ == 0x0) revert("Min: zero");
        _min = min_;
    }

    function setNext(bytes12 next_) public note auth {
        if (next_ == 0x0) revert("SetNext: zero");
        next = next_;
    }

    function unset(bytes12 pos) public auth {
        set(pos, address(0));
    }

    function unset(address wat) public auth {
        set(indexes[wat], address(0));
    }

    function poke() public {
        poke(0);
    }

    function poke(bytes32) public note {
        (val, has) = compute();
    }

    function compute() public view returns (bytes32, bool) {
        bytes32[] memory wuts = new bytes32[](uint96(next) - 1);
        uint96 ctr = 0;
        for (uint96 i = 1; i < uint96(next); i++) {
            if (values[bytes12(i)] != address(0)) {
                (bytes32 wut, bool wuz) = DSValue(values[bytes12(i)]).peek();
                if (wuz) {
                    if (ctr == 0 || wut >= wuts[ctr - 1]) {
                        wuts[ctr] = wut;
                    } else {
                        uint96 j = 0;
                        while (wut >= wuts[j]) {
                            j++;
                        }
                        for (uint96 k = ctr; k > j; k--) {
                            wuts[k] = wuts[k - 1];
                        }
                        wuts[j] = wut;
                    }
                    ctr++;
                }
            }
        }

        if (ctr < _min) return (val, false);

        bytes32 value;
        if (ctr % 2 == 0) {
            uint val1 = uint(wuts[(ctr / 2) - 1]);
            uint val2 = uint(wuts[ctr / 2]);
            value = bytes32(wdiv(add(val1, val2), 2 ether));
        } else {
            value = wuts[(ctr - 1) / 2];
        }

        return (value, true);
    }
}