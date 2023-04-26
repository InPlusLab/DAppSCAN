/// DssDeploy.sol

// Copyright (C) 2018-2019 Gonzalo Balabasquer <gbalabasquer@gmail.com>

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

import {DSAuth, DSAuthority} from "ds-auth/auth.sol";
import {DSPause} from "ds-pause/pause.sol";

import {Vat} from "dss/vat.sol";
import {Jug} from "dss/jug.sol";
import {Vow} from "dss/vow.sol";
import {Cat} from "dss/cat.sol";
import {DaiJoin} from "dss/join.sol";
import {Flapper} from "dss/flap.sol";
import {Flopper} from "dss/flop.sol";
import {Flipper} from "dss/flip.sol";
import {Dai} from "dss/dai.sol";
import {End} from "dss/end.sol";
import {ESM} from "esm/ESM.sol";
import {Pot} from "dss/pot.sol";
import {Spotter} from "dss/spot.sol";

contract VatFab {
    function newVat() public returns (Vat vat) {
        vat = new Vat();
        vat.rely(msg.sender);
        vat.deny(address(this));
    }
}

contract JugFab {
    function newJug(address vat) public returns (Jug jug) {
        jug = new Jug(vat);
        jug.rely(msg.sender);
        jug.deny(address(this));
    }
}

contract VowFab {
    function newVow(address vat, address flap, address flop) public returns (Vow vow) {
        vow = new Vow(vat, flap, flop);
        vow.rely(msg.sender);
        vow.deny(address(this));
    }
}

contract CatFab {
    function newCat(address vat) public returns (Cat cat) {
        cat = new Cat(vat);
        cat.rely(msg.sender);
        cat.deny(address(this));
    }
}

contract DaiFab {
    function newDai(uint chainId) public returns (Dai dai) {
        dai = new Dai(chainId);
        dai.rely(msg.sender);
        dai.deny(address(this));
    }
}

contract DaiJoinFab {
    function newDaiJoin(address vat, address dai) public returns (DaiJoin daiJoin) {
        daiJoin = new DaiJoin(vat, dai);
    }
}

contract FlapFab {
    function newFlap(address vat, address gov) public returns (Flapper flap) {
        flap = new Flapper(vat, gov);
        flap.rely(msg.sender);
        flap.deny(address(this));
    }
}

contract FlopFab {
    function newFlop(address vat, address gov) public returns (Flopper flop) {
        flop = new Flopper(vat, gov);
        flop.rely(msg.sender);
        flop.deny(address(this));
    }
}

contract FlipFab {
    function newFlip(address vat, bytes32 ilk) public returns (Flipper flip) {
        flip = new Flipper(vat, ilk);
        flip.rely(msg.sender);
        flip.deny(address(this));
    }
}

contract SpotFab {
    function newSpotter(address vat) public returns (Spotter spotter) {
        spotter = new Spotter(vat);
        spotter.rely(msg.sender);
        spotter.deny(address(this));
    }
}

contract PotFab {
    function newPot(address vat) public returns (Pot pot) {
        pot = new Pot(vat);
        pot.rely(msg.sender);
        pot.deny(address(this));
    }
}

contract EndFab {
    function newEnd() public returns (End end) {
        end = new End();
        end.rely(msg.sender);
        end.deny(address(this));
    }
}

contract PauseFab {
    function newPause(uint delay, address owner, DSAuthority authority) public returns(DSPause pause) {
        pause = new DSPause(delay, owner, authority);
    }
}

contract DssDeploy is DSAuth {
    VatFab     public vatFab;
    JugFab     public jugFab;
    VowFab     public vowFab;
    CatFab     public catFab;
    DaiFab     public daiFab;
    DaiJoinFab public daiJoinFab;
    FlapFab    public flapFab;
    FlopFab    public flopFab;
    FlipFab    public flipFab;
    SpotFab    public spotFab;
    PotFab     public potFab;
    EndFab     public endFab;
    PauseFab   public pauseFab;

    Vat     public vat;
    Jug     public jug;
    Vow     public vow;
    Cat     public cat;
    Dai     public dai;
    DaiJoin public daiJoin;
    Flapper public flap;
    Flopper public flop;
    Spotter public spotter;
    Pot     public pot;
    End     public end;
    ESM     public esm;
    DSPause public pause;

    mapping(bytes32 => Ilk) public ilks;

    uint8 public step = 0;

    uint256 constant ONE = 10 ** 27;

    struct Ilk {
        Flipper flip;
        address adapter;
    }

    constructor(
        VatFab vatFab_,
        JugFab jugFab_,
        VowFab vowFab_,
        CatFab catFab_,
        DaiFab daiFab_,
        DaiJoinFab daiJoinFab_,
        FlapFab flapFab_,
        FlopFab flopFab_,
        FlipFab flipFab_,
        SpotFab spotFab_,
        PotFab potFab_,
        EndFab endFab_,
        PauseFab pauseFab_
    ) public {
        vatFab = vatFab_;
        jugFab = jugFab_;
        vowFab = vowFab_;
        catFab = catFab_;
        daiFab = daiFab_;
        daiJoinFab = daiJoinFab_;
        flapFab = flapFab_;
        flopFab = flopFab_;
        flipFab = flipFab_;
        spotFab = spotFab_;
        potFab = potFab_;
        endFab = endFab_;
        pauseFab = pauseFab_;
    }

    function rad(uint wad) internal pure returns (uint) {
        return wad * 10 ** 27;
    }

    function deployVat() public auth {
        require(address(vat) == address(0), "VAT already deployed");
        vat = vatFab.newVat();
        spotter = spotFab.newSpotter(address(vat));

        // Internal auth
        vat.rely(address(spotter));
    }

    function deployDai(uint256 chainId) public auth {
        require(address(vat) != address(0), "Missing previous step");

        // Deploy
        dai     = daiFab.newDai(chainId);
        daiJoin = daiJoinFab.newDaiJoin(address(vat), address(dai));
        dai.rely(address(daiJoin));
    }

    function deployTaxationAndAuctions(address gov) public auth {
        require(gov != address(0), "Missing GOV address");
        require(address(vat) != address(0), "Missing previous step");

        // Deploy
        jug = jugFab.newJug(address(vat));
        pot = potFab.newPot(address(vat));
        flap = flapFab.newFlap(address(vat), gov);
        flop = flopFab.newFlop(address(vat), gov);
        vow = vowFab.newVow(address(vat), address(flap), address(flop));

        // Internal references set up
        jug.file("vow", address(vow));
        pot.file("vow", address(vow));

        // Internal auth
        vat.rely(address(vow));
        vat.rely(address(jug));
        vat.rely(address(pot));
        flap.rely(address(vow));
        flop.rely(address(vow));
    }

    function deployLiquidator() public auth {
        require(address(vow) != address(0), "Missing previous step");

        // Deploy
        cat = catFab.newCat(address(vat));

        // Internal references set up
        cat.file("vow", address(vow));

        // Internal auth
        vat.rely(address(cat));
        vow.rely(address(cat));
    }

    function deployShutdown(address gov, address pit, uint256 min) public auth {
        require(address(cat) != address(0), "Missing previous step");

        // Deploy
        end = endFab.newEnd();

        // Internal references set up
        end.file("vat", address(vat));
        end.file("cat", address(cat));
        end.file("vow", address(vow));
        end.file("spot", address(spotter));

        // Internal auth
        vat.rely(address(end));
        cat.rely(address(end));
        vow.rely(address(end));

        // Deploy ESM
        esm = new ESM(gov, address(end), address(pit), min);
        end.rely(address(esm));
    }

    function deployPause(uint delay, DSAuthority authority) public auth {
        require(address(dai) != address(0), "Missing previous step");
        require(address(end) != address(0), "Missing previous step");

        pause = pauseFab.newPause(delay, address(0), authority);

        vat.rely(address(pause.proxy()));
        cat.rely(address(pause.proxy()));
        vow.rely(address(pause.proxy()));
        jug.rely(address(pause.proxy()));
        pot.rely(address(pause.proxy()));
        spotter.rely(address(pause.proxy()));
        flap.rely(address(pause.proxy()));
        flop.rely(address(pause.proxy()));
        end.rely(address(pause.proxy()));

        this.setAuthority(authority);
        this.setOwner(address(0));
    }

    function deployCollateral(bytes32 ilk, address adapter, address pip) public auth {
        require(ilk != bytes32(""), "Missing ilk name");
        require(adapter != address(0), "Missing adapter address");
        require(pip != address(0), "Missing PIP address");
        require(address(pause) != address(0), "Missing previous step");

        // Deploy
        ilks[ilk].flip = flipFab.newFlip(address(vat), ilk);
        ilks[ilk].adapter = adapter;
        Spotter(spotter).file(ilk, address(pip)); // Set pip

        // Internal references set up
        cat.file(ilk, "flip", address(ilks[ilk].flip));
        vat.init(ilk);
        jug.init(ilk);

        // Internal auth
        vat.rely(adapter);
        ilks[ilk].flip.rely(address(end));
        ilks[ilk].flip.rely(address(pause.proxy()));
    }

    function releaseAuth() public auth {
        vat.deny(address(this));
        cat.deny(address(this));
        vow.deny(address(this));
        jug.deny(address(this));
        pot.deny(address(this));
        dai.deny(address(this));
        spotter.deny(address(this));
        flap.deny(address(this));
        flop.deny(address(this));
        end.deny(address(this));
    }

    function releaseAuthFlip(bytes32 ilk) public auth {
        ilks[ilk].flip.deny(address(this));
    }
}
