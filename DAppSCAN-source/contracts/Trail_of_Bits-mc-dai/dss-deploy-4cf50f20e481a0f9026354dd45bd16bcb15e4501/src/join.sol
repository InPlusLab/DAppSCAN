/// join.sol -- Non-standard token adapters

// Copyright (C) 2018 Rain <rainbreak@riseup.net>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity >=0.5.0;

import "dss/lib.sol";

contract VatLike {
    function slip(bytes32,address,int) public;
}

// GemJoin1

contract GemLike {
    function decimals() public view returns (uint);
    function transfer(address,uint) public returns (bool);
    function transferFrom(address,address,uint) public returns (bool);
}

contract GemJoin1 is DSNote {
    VatLike public vat;
    bytes32 public ilk;
    GemLike public gem;
    uint    public dec;

    constructor(address vat_, bytes32 ilk_, address gem_) public {
        vat = VatLike(vat_);
        ilk = ilk_;
        gem = GemLike(gem_);
        dec = gem.decimals();
    }

    function join(address usr, uint wad) public note {
        require(int(wad) >= 0, "GemJoin1/overflow");
        vat.slip(ilk, usr, int(wad));
        require(gem.transferFrom(msg.sender, address(this), wad), "GemJoin1/failed-transfer");
    }

    function exit(address usr, uint wad) public note {
        require(wad <= 2 ** 255, "GemJoin1/overflow");
        vat.slip(ilk, msg.sender, -int(wad));
        require(gem.transfer(usr, wad), "GemJoin1/failed-transfer");
    }
}

// GemJoin2

// For a token that does not return a bool on transfer or transferFrom (like OMG)
// This is one way of doing it. Check the balances before and after calling a transfer

contract GemLike2 {
    function decimals() public view returns (uint);
    function transfer(address,uint) public;
    function transferFrom(address,address,uint) public;
    function balanceOf(address) public view returns (uint);
    function allowance(address,address) public view returns (uint);
}

contract GemJoin2 is DSNote {
    VatLike public vat;
    bytes32 public ilk;
    GemLike2 public gem;
    uint     public dec;

    constructor(address vat_, bytes32 ilk_, address gem_) public {
        vat = VatLike(vat_);
        ilk = ilk_;
        gem = GemLike2(gem_);
        dec = gem.decimals();
    }

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, "GemJoin2/overflow");
    }

    function join(address urn, uint wad) public note {
        require(wad <= 2 ** 255, "GemJoin2/overflow");
        vat.slip(ilk, urn, int(wad));
        uint256 prevBalance = gem.balanceOf(msg.sender);

        require(prevBalance >= wad, "GemJoin2/no-funds");
        require(gem.allowance(msg.sender, address(this)) >= wad, "GemJoin2/no-allowance");

        (bool ok,) = address(gem).call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", msg.sender, address(this), wad)
        );
        require(ok, "GemJoin2/failed-transfer");

        require(prevBalance - wad == gem.balanceOf(msg.sender), "GemJoin2/failed-transfer");
    }

    function exit(address guy, uint wad) public note {
        require(wad <= 2 ** 255, "GemJoin2/overflow");
        vat.slip(ilk, msg.sender, -int(wad));
        uint256 prevBalance = gem.balanceOf(address(this));

        require(prevBalance >= wad, "GemJoin2/no-funds");

        (bool ok,) = address(gem).call(
            abi.encodeWithSignature("transfer(address,uint256)", guy, wad)
        );
        require(ok, "GemJoin2/failed-transfer");

        require(prevBalance - wad == gem.balanceOf(address(this)), "GemJoin2/failed-transfer");
    }
}

// GemJoin3
// For a token that has a lower precision than 18 and doesn't have decimals field in place (like DGD)

contract GemLike3 {
    function transfer(address,uint) public returns (bool);
    function transferFrom(address,address,uint) public returns (bool);
}

contract GemJoin3 is DSNote {
    VatLike public vat;
    bytes32 public ilk;
    GemLike3 public gem;
    uint     public dec;

    constructor(address vat_, bytes32 ilk_, address gem_, uint decimals) public {
        vat = VatLike(vat_);
        ilk = ilk_;
        gem = GemLike3(gem_);
        require(decimals < 18, "GemJoin3/decimals-higher-18");
        dec = decimals;
    }

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, "GemJoin3/overflow");
    }

    function join(address urn, uint wad) public note {
        uint wad18 = mul(wad, 10 ** (18 - dec));
        require(wad18 <= 2 ** 255, "GemJoin3/overflow");
        vat.slip(ilk, urn, int(wad18));
        require(gem.transferFrom(msg.sender, address(this), wad), "GemJoin3/failed-transfer");
    }

    function exit(address guy, uint wad) public note {
        uint wad18 = mul(wad, 10 ** (18 - dec));
        require(wad18 <= 2 ** 255, "GemJoin3/overflow");
        vat.slip(ilk, msg.sender, -int(wad18));
        require(gem.transfer(guy, wad), "GemJoin3/failed-transfer");
    }
}

/// GemJoin4

// Copyright (C) 2019 Lorenzo Manacorda <lorenzo@mailbox.org>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

// For tokens that do not implement transferFrom (like GNT), meaning the usual adapter
// approach won't work: the adapter cannot call transferFrom and therefore
// has no way of knowing when users deposit gems into it.

// To work around this, we introduce the concept of a bag, which is a trusted
// (it's created by the adapter), personalized component (one for each user).

// Users first have to create their bag with `GemJoin4.make`, then transfer
// gem to it, and then call `GemJoin4.join`, which transfer the gems from the
// bag to the adapter.

contract GemLike4 {
    function decimals() public view returns (uint);
    function balanceOf(address) public returns (uint256);
    function transfer(address, uint256) public returns (bool);
}

contract GemBag {
    address  public ada;
    address  public lad;
    GemLike4 public gem;

    constructor(address lad_, address gem_) public {
        ada = msg.sender;
        lad = lad_;
        gem = GemLike4(gem_);
    }

    function exit(address usr, uint256 wad) external {
        require(msg.sender == ada || msg.sender == lad, "GemBag/invalid-caller");
        require(gem.transfer(usr, wad), "GemBag/failed-transfer");
    }
}

contract GemJoin4 is DSNote {
    VatLike  public vat;
    bytes32  public ilk;
    GemLike4 public gem;
    uint     public dec;

    mapping(address => address) public bags;

    constructor(address vat_, bytes32 ilk_, address gem_) public {
        vat = VatLike(vat_);
        ilk = ilk_;
        gem = GemLike4(gem_);
        dec = gem.decimals();
    }

    // --- math ---
    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "GemJoin4/overflow");
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "GemJoin4/underflow");
    }

    // -- admin --
    function make() external returns (address bag) {
        bag = make(msg.sender);
    }

    function make(address usr) public note returns (address bag) {
        require(bags[usr] == address(0), "GemJoin4/bag-already-exists");

        bag = address(new GemBag(address(usr), address(gem)));
        bags[usr] = bag;
    }

    // -- gems --
    function join(address urn, uint256 wad) external note {
        require(int256(wad) >= 0, "GemJoin4/negative-amount");

        GemBag(bags[msg.sender]).exit(address(this), wad);
        vat.slip(ilk, urn, int256(wad));
    }

    function exit(address usr, uint256 wad) external note {
        require(int256(wad) >= 0, "GemJoin4/negative-amount");

        vat.slip(ilk, msg.sender, -int256(wad));
        require(gem.transfer(usr, wad), "GemJoin4/failed-transfer");
    }
}
