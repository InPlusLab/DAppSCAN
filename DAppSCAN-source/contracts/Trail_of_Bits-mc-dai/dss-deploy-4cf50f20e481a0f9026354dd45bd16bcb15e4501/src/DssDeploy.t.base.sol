pragma solidity >=0.5.0;

import {DSTest} from "ds-test/test.sol";
import {DSToken} from "ds-token/token.sol";
import {DSValue} from "ds-value/value.sol";
import {DSRoles} from "ds-roles/roles.sol";
import {DSGuard} from "ds-guard/guard.sol";
import {WETH9_} from "ds-weth/weth9.sol";

import "./DssDeploy.sol";
import {GemJoin1} from "./join.sol";
import {GovActions} from "./govActions.sol";

contract Hevm {
    function warp(uint256) public;
}

contract AuctionLike {
    function tend(uint, uint, uint) public;
    function dent(uint, uint, uint) public;
    function deal(uint) public;
}

contract HopeLike {
    function hope(address guy) public;
}

contract FakeUser {
    function doApprove(address token, address guy) public {
        DSToken(token).approve(guy);
    }

    function doDaiJoin(address obj, address urn, uint wad) public {
        DaiJoin(obj).join(urn, wad);
    }

    function doDaiExit(address obj, address guy, uint wad) public {
        DaiJoin(obj).exit(guy, wad);
    }

    function doEthJoin(address payable obj, address gem, address urn, uint wad) public {
        WETH9_(obj).deposit.value(wad)();
        WETH9_(obj).approve(address(gem), uint(-1));
        GemJoin1(gem).join(urn, wad);
    }

    function doFrob(address obj, bytes32 ilk, address urn, address gem, address dai, int dink, int dart) public {
        Vat(obj).frob(ilk, urn, gem, dai, dink, dart);
    }

    function doFork(address obj, bytes32 ilk, address src, address dst, int dink, int dart) public {
        Vat(obj).fork(ilk, src, dst, dink, dart);
    }

    function doHope(address obj, address guy) public {
        HopeLike(obj).hope(guy);
    }

    function doTend(address obj, uint id, uint lot, uint bid) public {
        AuctionLike(obj).tend(id, lot, bid);
    }

    function doDent(address obj, uint id, uint lot, uint bid) public {
        AuctionLike(obj).dent(id, lot, bid);
    }

    function doDeal(address obj, uint id) public {
        AuctionLike(obj).deal(id);
    }

    function doEndFree(address end, bytes32 ilk) public {
        End(end).free(ilk);
    }

    function doESMJoin(address gem, address esm, uint256 wad) public {
        DSToken(gem).approve(esm, uint256(-1));
        ESM(esm).join(wad);
    }

    function() external payable {
    }
}

contract ProxyActions {
    DSPause pause;
    GovActions govActions;

    function file(address who, bytes32 what, uint256 data) external {
        address      usr = address(govActions);
        bytes32      tag;  assembly { tag := extcodehash(usr) }
        bytes memory fax = abi.encodeWithSignature("file(address,bytes32,uint256)", who, what, data);
        uint         eta = now;

        pause.plot(usr, tag, fax, eta);
        pause.exec(usr, tag, fax, eta);
    }

    function file(address who, bytes32 ilk, bytes32 what, uint256 data) external {
        address      usr = address(govActions);
        bytes32      tag;  assembly { tag := extcodehash(usr) }
        bytes memory fax = abi.encodeWithSignature("file(address,bytes32,bytes32,uint256)", who, ilk, what, data);
        uint         eta = now;

        pause.plot(usr, tag, fax, eta);
        pause.exec(usr, tag, fax, eta);
    }

    function cage(address end) external {
        address      usr = address(govActions);
        bytes32      tag;  assembly { tag := extcodehash(usr) }
        bytes memory fax = abi.encodeWithSignature("cage(address)", end);
        uint         eta = now;

        pause.plot(usr, tag, fax, eta);
        pause.exec(usr, tag, fax, eta);
    }

    function cage(address end, bytes32 ilk) external {
        address      usr = address(govActions);
        bytes32      tag;  assembly { tag := extcodehash(usr) }
        bytes memory fax = abi.encodeWithSignature("cage(address,bytes32)", end, ilk);
        uint         eta = now;

        pause.plot(usr, tag, fax, eta);
        pause.exec(usr, tag, fax, eta);
    }

    function setAuthority(address newAuthority) external {
        address      usr = address(govActions);
        bytes32      tag;  assembly { tag := extcodehash(usr) }
        bytes memory fax = abi.encodeWithSignature("setAuthority(address,address)", pause, newAuthority);
        uint         eta = now;

        pause.plot(usr, tag, fax, eta);
        pause.exec(usr, tag, fax, eta);
    }

    function setDelay(uint newDelay) external {
        address      usr = address(govActions);
        bytes32      tag;  assembly { tag := extcodehash(usr) }
        bytes memory fax = abi.encodeWithSignature("setDelay(address,uint256)", pause, newDelay);
        uint         eta = now;

        pause.plot(usr, tag, fax, eta);
        pause.exec(usr, tag, fax, eta);
    }

    function setAuthorityAndDelay(address newAuthority, uint newDelay) external {
        address      usr = address(govActions);
        bytes32      tag;  assembly { tag := extcodehash(usr) }
        bytes memory fax = abi.encodeWithSignature("setAuthorityAndDelay(address,address,uint256)", pause, newAuthority, newDelay);
        uint         eta = now;

        pause.plot(usr, tag, fax, eta);
        pause.exec(usr, tag, fax, eta);
    }
}

contract DssDeployTestBase is DSTest, ProxyActions {
    Hevm hevm;

    VatFab vatFab;
    JugFab jugFab;
    VowFab vowFab;
    CatFab catFab;
    DaiFab daiFab;
    DaiJoinFab daiJoinFab;
    FlapFab flapFab;
    FlopFab flopFab;
    FlipFab flipFab;
    SpotFab spotFab;
    PotFab potFab;
    EndFab endFab;
    PauseFab pauseFab;

    DssDeploy dssDeploy;

    DSToken gov;
    DSValue pipETH;
    DSValue pipCOL;

    DSRoles authority;

    WETH9_ weth;
    GemJoin1 ethJoin;
    GemJoin1 colJoin;

    Vat vat;
    Jug jug;
    Vow vow;
    Cat cat;
    Flapper flap;
    Flopper flop;
    Dai dai;
    DaiJoin daiJoin;
    Spotter spotter;
    Pot pot;
    End end;
    ESM esm;

    Flipper ethFlip;

    DSToken col;
    Flipper colFlip;

    FakeUser user1;
    FakeUser user2;

    // --- Math ---
    uint256 constant ONE = 10 ** 27;
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    function setUp() public {
        vatFab = new VatFab();
        jugFab = new JugFab();
        vowFab = new VowFab();
        catFab = new CatFab();
        daiFab = new DaiFab();
        daiJoinFab = new DaiJoinFab();
        flapFab = new FlapFab();
        flopFab = new FlopFab();
        flipFab = new FlipFab();
        spotFab = new SpotFab();
        potFab = new PotFab();
        endFab = new EndFab();
        pauseFab = new PauseFab();
        govActions = new GovActions();

        dssDeploy = new DssDeploy(
            vatFab,
            jugFab,
            vowFab,
            catFab,
            daiFab,
            daiJoinFab,
            flapFab,
            flopFab,
            flipFab,
            spotFab,
            potFab,
            endFab,
            pauseFab
        );

        gov = new DSToken("GOV");
        gov.setAuthority(new DSGuard());
        pipETH = new DSValue();
        pipCOL = new DSValue();
        authority = new DSRoles();
        authority.setRootUser(address(this), true);

        user1 = new FakeUser();
        user2 = new FakeUser();
        address(user1).transfer(100 ether);
        address(user2).transfer(100 ether);

        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(0);
    }

    function rad(uint wad) internal pure returns (uint) {
        return wad * 10 ** 27;
    }

    function deployKeepAuth() public {
        dssDeploy.deployVat();
        dssDeploy.deployDai(99);
        dssDeploy.deployTaxationAndAuctions(address(gov));
        dssDeploy.deployLiquidator();
        dssDeploy.deployShutdown(address(gov), address(0x0), 10);
        dssDeploy.deployPause(0, authority);

        vat = dssDeploy.vat();
        jug = dssDeploy.jug();
        vow = dssDeploy.vow();
        cat = dssDeploy.cat();
        flap = dssDeploy.flap();
        flop = dssDeploy.flop();
        dai = dssDeploy.dai();
        daiJoin = dssDeploy.daiJoin();
        spotter = dssDeploy.spotter();
        pot = dssDeploy.pot();
        end = dssDeploy.end();
        esm = dssDeploy.esm();
        pause = dssDeploy.pause();
        authority.setRootUser(address(pause.proxy()), true);

        weth = new WETH9_();
        ethJoin = new GemJoin1(address(vat), "ETH", address(weth));
        dssDeploy.deployCollateral("ETH", address(ethJoin), address(pipETH));

        col = new DSToken("COL");
        colJoin = new GemJoin1(address(vat), "COL", address(col));
        dssDeploy.deployCollateral("COL", address(colJoin), address(pipCOL));

        // Set Params
        this.file(address(vat), bytes32("Line"), uint(10000 * 10 ** 45));
        this.file(address(vat), bytes32("ETH"), bytes32("line"), uint(10000 * 10 ** 45));
        this.file(address(vat), bytes32("COL"), bytes32("line"), uint(10000 * 10 ** 45));

        pipETH.poke(bytes32(uint(300 * 10 ** 18))); // Price 300 DAI = 1 ETH (precision 18)
        pipCOL.poke(bytes32(uint(45 * 10 ** 18))); // Price 45 DAI = 1 COL (precision 18)
        (ethFlip,) = dssDeploy.ilks("ETH");
        (colFlip,) = dssDeploy.ilks("COL");
        this.file(address(spotter), "ETH", "mat", uint(1500000000 ether)); // Liquidation ratio 150%
        this.file(address(spotter), "COL", "mat", uint(1100000000 ether)); // Liquidation ratio 110%
        spotter.poke("ETH");
        spotter.poke("COL");
        (,,uint spot,,) = vat.ilks("ETH");
        assertEq(spot, 300 * ONE * ONE / 1500000000 ether);
        (,, spot,,) = vat.ilks("COL");
        assertEq(spot, 45 * ONE * ONE / 1100000000 ether);

        DSGuard(address(gov.authority())).permit(address(flop), address(gov), bytes4(keccak256("mint(address,uint256)")));

        gov.mint(100 ether);
    }

    function deploy() public {
        deployKeepAuth();
        dssDeploy.releaseAuth();
    }

    function() external payable {
    }
}
