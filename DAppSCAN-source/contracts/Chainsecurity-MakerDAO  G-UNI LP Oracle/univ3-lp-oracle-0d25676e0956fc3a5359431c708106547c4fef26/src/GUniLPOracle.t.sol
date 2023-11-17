// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity =0.6.12;

import "ds-test/test.sol";

import {GUniLPOracle,GUniLPOracleFactory} from "./GUniLPOracle.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
    function load(address, bytes32 slot) external returns (bytes32);
}

interface OSMLike {
    function bud(address) external returns (uint);
    function peek() external returns (bytes32, bool);
    function kiss(address) external;
    function poke() external;
}

interface UniPoolLike {
    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool);
    function swap(address, bool, int256, uint160, bytes calldata) external;
    function positions(bytes32) external view returns (uint128, uint256, uint256, uint128, uint128);
}

interface AuthLike {
    function wards(address) external returns (uint256);
}

interface ERC20Like {
    function decimals()                 external view returns (uint8);
    function balanceOf(address)         external view returns (uint256);
    function totalSupply()              external view returns (uint256);
    function transfer(address, uint256) external;
    function approve(address, uint256)  external;
}

interface GUNILike {
    function token0()                               external view returns (address);
    function token1()                               external view returns (address);
    function getMintAmounts(uint256, uint256)       external view returns (uint256,uint256,uint256);
    function getUnderlyingBalances()                external view returns (uint256,uint256);
    function getUnderlyingBalancesAtPrice(uint160)  external view returns (uint256,uint256);
    function getPositionID()                        external view returns (bytes32);
    function pool()                                 external view returns (address);
    function mint(uint256, address)                 external returns (uint256, uint256, uint128);
    function burn(uint256, address)                 external returns (uint256, uint256, uint128);
}

interface OracleLike {
    function read() external view returns (uint256);
}

contract GUniLPOracleTest is DSTest {

    function assertEqApprox(uint256 _a, uint256 _b, uint256 _tolerance) internal {
        uint256 a = _a;
        uint256 b = _b;
        if (a < b) {
            uint256 tmp = a;
            a = b;
            b = tmp;
        }
        if (a - b > _tolerance * a / 1e4) {
            emit log_bytes32("Error: Wrong `uint' value");
            emit log_named_uint("  Expected", _b);
            emit log_named_uint("    Actual", _a);
            fail();
        }
    }

    function assertNotEqApprox(uint256 _a, uint256 _b, uint256 _tolerance) internal {
        uint256 a = _a;
        uint256 b = _b;
        if (a < b) {
            uint256 tmp = a;
            a = b;
            b = tmp;
        }
        if (a - b < _tolerance * a / 1e4) {
            emit log_bytes32("Error: `uint' should not match");
            emit log_named_uint("  Expected", _b);
            emit log_named_uint("    Actual", _a);
            fail();
        }
    }

    function giveAuthAccess (address _base, address target) internal {
        AuthLike base = AuthLike(_base);

        // Edge case - ward is already set
        if (base.wards(target) == 1) return;

        for (int i = 0; i < 100; i++) {
            // Scan the storage for the ward storage slot
            bytes32 prevValue = hevm.load(
                address(base),
                keccak256(abi.encode(target, uint256(i)))
            );
            hevm.store(
                address(base),
                keccak256(abi.encode(target, uint256(i))),
                bytes32(uint256(1))
            );
            if (base.wards(target) == 1) {
                // Found it
                return;
            } else {
                // Keep going after restoring the original value
                hevm.store(
                    address(base),
                    keccak256(abi.encode(target, uint256(i))),
                    prevValue
                );
            }
        }

        // We have failed if we reach here
        assertTrue(false);
    }

    function giveTokens(address token, uint256 amount) internal {
        // Edge case - balance is already set for some reason
        if (ERC20Like(token).balanceOf(address(this)) == amount) return;

        for (int i = 0; i < 100; i++) {
            // Scan the storage for the balance storage slot
            bytes32 prevValue = hevm.load(
                token,
                keccak256(abi.encode(address(this), uint256(i)))
            );
            hevm.store(
                token,
                keccak256(abi.encode(address(this), uint256(i))),
                bytes32(amount)
            );
            if (ERC20Like(token).balanceOf(address(this)) == amount) {
                // Found it
                return;
            } else {
                // Keep going after restoring the original value
                hevm.store(
                    token,
                    keccak256(abi.encode(address(this), uint256(i))),
                    prevValue
                );
            }
        }

        // We have failed if we reach here
        assertTrue(false);
    }

    // --- Math ---
    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, "ds-math-sub-underflow");
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
    }
    function div(uint x, uint y) internal pure returns (uint z) {
        require(y > 0 && (z = x / y) * y == x, "ds-math-divide-by-zero");
    }
    function divup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = add(x, sub(y, 1)) / y;
    }
    function wmul(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, y), WAD / 2) / WAD;
    }
    function wdiv(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, WAD), y / 2) / y;
    }
    function toUint160(uint256 x) internal pure returns (uint160 z) {
        require((z = uint160(x)) == x, "GUniLPOracle/uint160-overflow");
    }

    // babylonian method (https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method)
    function sqrt1(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    // FROM https://github.com/abdk-consulting/abdk-libraries-solidity/blob/16d7e1dd8628dfa2f88d5dadab731df7ada70bdd/ABDKMath64x64.sol#L687
    function sqrt2(uint256 _x) private pure returns (uint128) {
        if (_x == 0) return 0;
        else {
            uint256 xx = _x;
            uint256 r = 1;
            if (xx >= 0x100000000000000000000000000000000) { xx >>= 128; r <<= 64; }
            if (xx >= 0x10000000000000000) { xx >>= 64; r <<= 32; }
            if (xx >= 0x100000000) { xx >>= 32; r <<= 16; }
            if (xx >= 0x10000) { xx >>= 16; r <<= 8; }
            if (xx >= 0x100) { xx >>= 8; r <<= 4; }
            if (xx >= 0x10) { xx >>= 4; r <<= 2; }
            if (xx >= 0x8) { r <<= 1; }
            r = (r + _x / r) >> 1;
            r = (r + _x / r) >> 1;
            r = (r + _x / r) >> 1;
            r = (r + _x / r) >> 1;
            r = (r + _x / r) >> 1;
            r = (r + _x / r) >> 1;
            r = (r + _x / r) >> 1; // Seven iterations should be enough
            uint256 r1 = _x / r;
            return uint128 (r < r1 ? r : r1);
        }
    }

    Hevm                 hevm;
    GUniLPOracleFactory  factory;
    GUniLPOracle         daiUsdcLPOracle;
    GUniLPOracle         ethUsdcLPOracle;

    address constant DAI_USDC_GUNI_POOL = 0xAbDDAfB225e10B90D798bB8A886238Fb835e2053;
    address constant DAI_USDC_UNI_POOL  = 0x6c6Bc977E13Df9b0de53b251522280BB72383700;
    address constant ETH_USDC_GUNI_POOL = 0xa6c49FD13E50a30C65E6C8480aADA132011D0613;
    address constant ETH_USDC_UNI_POOL  = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;
    address constant USDC_ORACLE        = 0x77b68899b99b686F415d074278a9a16b336085A0;
    address constant DAI_ORACLE         = 0x47c3dC029825Da43BE595E21fffD0b66FfcB7F6e;
    address constant ETH_ORACLE         = 0x81FE72B5A8d1A857d176C3E7d5Bd2679A9B85763;
    address constant DAI                = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDC               = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant ETH                = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    bytes32 constant poolNameDAI        = "DAI-USDC-GUNI-LP";
    bytes32 constant poolNameETH        = "ETH-USDC-GUNI-LP";

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        factory = new GUniLPOracleFactory();

        daiUsdcLPOracle = GUniLPOracle(factory.build(
            address(this),
            DAI_USDC_GUNI_POOL,
            poolNameDAI,
            DAI_ORACLE,
            USDC_ORACLE)
        );
        daiUsdcLPOracle.kiss(address(this));
        assertEq(GUNILike(DAI_USDC_GUNI_POOL).pool(), DAI_USDC_UNI_POOL);

        ethUsdcLPOracle = GUniLPOracle(factory.build(
            address(this),
            ETH_USDC_GUNI_POOL,
            poolNameETH,
            USDC_ORACLE,
            ETH_ORACLE)
        );
        giveAuthAccess(ETH_ORACLE, address(this));
        OSMLike(ETH_ORACLE).kiss(address(ethUsdcLPOracle));
        OSMLike(ETH_ORACLE).kiss(address(this));
        ethUsdcLPOracle.kiss(address(this));
        assertEq(GUNILike(ETH_USDC_GUNI_POOL).pool(), ETH_USDC_UNI_POOL);
    }

    /// @notice Uniswap v3 callback fn, called back on pool.swap
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata /*data*/
    ) external {
        if (amount0Delta > 0)
            ERC20Like(USDC).transfer(msg.sender, uint256(amount0Delta));
        else if (amount1Delta > 0)
            ERC20Like(ETH).transfer(msg.sender, uint256(amount1Delta));
    }

    ///////////////////////////////////////////////////////
    //                                                   //
    //                  Factory Tests                    //
    //                                                   //
    ///////////////////////////////////////////////////////

    function test_build() public {
        GUniLPOracle oracle = GUniLPOracle(factory.build(
            address(this),
            DAI_USDC_GUNI_POOL,
            poolNameDAI,
            DAI_ORACLE,
            USDC_ORACLE)
        );                                                  // Deploy new LP oracle
        assertTrue(address(oracle) != address(0));          // Verify oracle deployed successfully
        assertEq(oracle.wards(address(this)), 1);           // Verify caller is owner
        assertEq(oracle.wards(address(factory)), 0);        // Vérify factory is not owner
        assertEq(oracle.src(), DAI_USDC_GUNI_POOL);         // Verify uni pool is source
        assertEq(oracle.orb0(), DAI_ORACLE);                // Verify oracle configured correctly
        assertEq(oracle.orb1(), USDC_ORACLE);               // Verify oracle configured correctly
        assertEq(oracle.wat(), poolNameDAI);                // Verify name is set correctly
        assertEq(uint256(oracle.stopped()), 0);             // Verify contract is active
        assertTrue(factory.isOracle(address(oracle)));      // Verify factory recorded oracle
    }

    function testFail_build_invalid_pool() public {
        factory.build(
            address(this),
            address(0),
            poolNameDAI,
            DAI_ORACLE,
            USDC_ORACLE
        );                                                  // Attempt to deploy new LP oracle
    }

    function testFail_build_invalid_pool2() public {
        factory.build(
            address(this),
            USDC_ORACLE,
            poolNameDAI,
            DAI_ORACLE,
            USDC_ORACLE
        );                                                  // Attempt to deploy with invalid pool
    }

    function testFail_build_invalid_oracle() public {
        factory.build(
            address(this),
            DAI_USDC_GUNI_POOL,
            poolNameDAI,
            DAI_ORACLE,
            address(0)
        );                                                  // Attempt to deploy new LP oracle
    }

    function testFail_build_invalid_oracle2() public {
        factory.build(
            address(this),
            DAI_USDC_GUNI_POOL,
            poolNameDAI,
            address(0),
            USDC_ORACLE
        );                                                  // Attempt to deploy new LP oracle
    }

    ///////////////////////////////////////////////////////
    //                                                   //
    //                   Oracle Tests                    //
    //                                                   //
    ///////////////////////////////////////////////////////

    function test_dai_oracle_constructor() public {
        assertEq(daiUsdcLPOracle.src(), DAI_USDC_GUNI_POOL);
        assertEq(daiUsdcLPOracle.orb0(), DAI_ORACLE);
        assertEq(daiUsdcLPOracle.orb1(), USDC_ORACLE);
        assertEq(daiUsdcLPOracle.wat(), poolNameDAI);
        assertEq(daiUsdcLPOracle.wards(address(this)), 1);
        assertEq(daiUsdcLPOracle.wards(address(factory)), 0);
        assertEq(uint256(daiUsdcLPOracle.stopped()), 0);
    }

    function test_calc_sqrts_match_dai() public {
        // Both these oracles should be hard coded to 1
        uint256 dec0 = uint256(ERC20Like(GUNILike(daiUsdcLPOracle.src()).token0()).decimals());
        uint256 dec1 = uint256(ERC20Like(GUNILike(daiUsdcLPOracle.src()).token1()).decimals());
        uint256 p0 = OracleLike(DAI_ORACLE).read();
        assertEq(p0, 1e18);
        uint256 p1 = OracleLike(USDC_ORACLE).read();
        assertEq(p1, 1e18);
        p0 *= 10 ** (18 - dec0);
        p1 *= 10 ** (18 - dec1);
        
        // Check both square roots produce the same results
        uint256 sqrtPriceX96_1 = sqrt1(mul(p0, (1 << 96)) / p1) << 48;
        assertEq(sqrtPriceX96_1, 79228162314232456544256);
        uint256 sqrtPriceX96_2 = sqrt2(mul(p0, (1 << 96)) / p1) << 48;
        assertEq(sqrtPriceX96_2, 79228162314232456544256);
    }

    function test_calc_sqrt_price_dai() public {
        // Both these oracles should be hard coded to 1
        uint256 dec0 = uint256(ERC20Like(GUNILike(daiUsdcLPOracle.src()).token0()).decimals());
        uint256 dec1 = uint256(ERC20Like(GUNILike(daiUsdcLPOracle.src()).token1()).decimals());
        uint256 p0 = OracleLike(DAI_ORACLE).read();
        assertEq(p0, 1e18);
        uint256 p1 = OracleLike(USDC_ORACLE).read();
        assertEq(p1, 1e18);
        p0 *= 10 ** (18 - dec0);
        p1 *= 10 ** (18 - dec1);
        
        // Check that the price roughly matches the Uniswap pool price during normal conditions
        uint256 sqrtPriceX96 = sqrt2(mul(p0, (1 << 96)) / p1) << 48;
        assertEq(sqrtPriceX96, 79228162314232456544256);
        (uint256 sqrtPriceX96_uni,,,,,,) = UniPoolLike(DAI_USDC_UNI_POOL).slot0();
        assertEqApprox(sqrtPriceX96_uni, sqrtPriceX96, 10);
    }

    function test_seek_dai() public {
        daiUsdcLPOracle.poke();
        hevm.warp(now + 1 hours);
        daiUsdcLPOracle.poke();
        uint128 lpTokenPrice128 = uint128(uint256(daiUsdcLPOracle.read()));
        assertTrue(lpTokenPrice128 > 0);                                          // Verify price was set
        uint256 lpTokenPrice = uint256(lpTokenPrice128);
        // Price should be the value of all the tokens combined divided by totalSupply()
        (uint256 balDai, uint256 balUsdc) = GUNILike(daiUsdcLPOracle.src()).getUnderlyingBalances();
        uint256 expectedPrice = (balDai + balUsdc * 1e12) * WAD / ERC20Like(daiUsdcLPOracle.src()).totalSupply();
        // Price is slightly off due to difference between Uniswap spot price and the Maker oracles
        // Allow for a 0.1% discrepancy
        assertEqApprox(lpTokenPrice, expectedPrice, 10);    
    }

    function test_calc_sqrts_match_eth() public {
        hevm.warp(now + 1 hours);
        OSMLike(ETH_ORACLE).poke();
        ethUsdcLPOracle.poke();

        // Both these oracles should be hard coded to 1
        uint256 p0 = OracleLike(USDC_ORACLE).read();
        assertEq(p0, 1e18);
        uint256 p1 = OracleLike(ETH_ORACLE).read();
        assertGt(p1, 0);
        
        // Check both square roots produce the same results
        uint256 sqrtPriceX96_1 = sqrt1(mul(p0 * 1e12, (1 << 96)) / p1) << 48;
        uint256 sqrtPriceX96_2 = sqrt2(mul(p0 * 1e12, (1 << 96)) / p1) << 48;
        assertEq(sqrtPriceX96_2, sqrtPriceX96_1);
    }

    function test_calc_sqrt_price_eth() public {
        hevm.warp(now + 1 hours);
        OSMLike(ETH_ORACLE).poke();
        ethUsdcLPOracle.poke();

        // Both these oracles should be hard coded to 1
        uint256 p0 = OracleLike(USDC_ORACLE).read();
        assertEq(p0, 1e18);
        uint256 p1 = OracleLike(ETH_ORACLE).read();
        assertGt(p1, 0);
        
        // Check that the price roughly matches the Uniswap pool price during normal conditions
        uint256 sqrtPriceX96 = sqrt2(mul(p0 * 1e12, (1 << 96)) / p1) << 48;
        (uint256 sqrtPriceX96_uni,,,,,,) = UniPoolLike(ETH_USDC_UNI_POOL).slot0();
        assertEqApprox(sqrtPriceX96, sqrtPriceX96_uni, 100);      // We've used the most recent Medanizer price, but there may still be some deviation from Uniswap

        // Check that the reserves roughly match with Uniswap spot and our sqrtPrice
        (uint256 r0_1, uint256 r1_1) = GUNILike(ethUsdcLPOracle.src()).getUnderlyingBalancesAtPrice(uint160(sqrtPriceX96));
        (uint256 r0_2, uint256 r1_2) = GUNILike(ethUsdcLPOracle.src()).getUnderlyingBalances();
        assertEqApprox(r0_2, r0_1, 800);
        assertEqApprox(r1_2, r1_1, 800);
    }

    function test_seek_eth() public {
        ethUsdcLPOracle.poke();
        hevm.warp(now + 1 hours);
        ethUsdcLPOracle.poke();
        uint128 lpTokenPrice128 = uint128(uint256(ethUsdcLPOracle.read()));
        assertTrue(lpTokenPrice128 > 0);                                          // Verify price was set
        uint256 lpTokenPrice = uint256(lpTokenPrice128);
        // Price should be the value of all the tokens combined divided by totalSupply()
        (uint256 balUsdc, uint256 balEth) = GUNILike(ethUsdcLPOracle.src()).getUnderlyingBalances();
        uint256 p1 = OracleLike(ETH_ORACLE).read();
        uint256 expectedPrice = (balEth * p1 + balUsdc * 1e12 * 1e18) / ERC20Like(ethUsdcLPOracle.src()).totalSupply();
        // Price is slightly off due to difference between Uniswap spot price and the Maker oracles
        // Allow for a 0.1% discrepancy
        assertEqApprox(lpTokenPrice, expectedPrice, 10);    
    }

    // This will massively skew the ETH-USDC pool in Uniswap to confirm our Oracle is unaffected
    function test_flash_loan_protection() public {
        uint256 balOrig = ERC20Like(USDC).balanceOf(ETH_USDC_UNI_POOL);
        assertGt(balOrig, 0);

        ethUsdcLPOracle.poke();
        hevm.warp(now + 1 hours);
        ethUsdcLPOracle.poke();
        uint128 lpTokenPrice128 = uint128(uint256(ethUsdcLPOracle.read()));
        assertTrue(lpTokenPrice128 > 0);                                          // Verify price was set
        uint256 lpTokenPriceOrig = uint256(lpTokenPrice128);
        (uint256 balUsdc, uint256 balEth) = GUNILike(ethUsdcLPOracle.src()).getUnderlyingBalances();
        uint256 naivePriceOrig = (balEth + balUsdc * 1e12) * WAD / ERC20Like(ethUsdcLPOracle.src()).totalSupply();

        // Give enough tokens to totally skew the reserves
        uint256 amount = 10 * ERC20Like(ETH).balanceOf(ETH_USDC_UNI_POOL);
        giveTokens(ETH, amount);
        UniPoolLike(ETH_USDC_UNI_POOL).swap(address(this), false, int256(amount), 13714534615519655739241256778826810, "");
        assertLt(ERC20Like(USDC).balanceOf(ETH_USDC_UNI_POOL) * 1e4 / balOrig, 500);    // New USDC balance should be less than 5% of original balance

        hevm.warp(now + 1 hours);
        ethUsdcLPOracle.poke();
        hevm.warp(now + 1 hours);
        ethUsdcLPOracle.poke();
        lpTokenPrice128 = uint128(uint256(ethUsdcLPOracle.read()));
        assertTrue(lpTokenPrice128 > 0);                                          // Verify price was set
        uint256 lpTokenPrice = uint256(lpTokenPrice128);
        (balUsdc, balEth) = GUNILike(ethUsdcLPOracle.src()).getUnderlyingBalances();
        uint256 naivePrice = (balEth + balUsdc * 1e12) * WAD / ERC20Like(ethUsdcLPOracle.src()).totalSupply();

        assertNotEqApprox(naivePrice, naivePriceOrig, 5000);    // This should be off by a lot (above 50% deviation)
        assertEqApprox(lpTokenPrice, lpTokenPriceOrig, 10);     // This should not deviate by much as it is not using the Uniswap pool price to calculate reserves
    }

    function test_zero_totalSupply() public {
        ethUsdcLPOracle.poke();
        hevm.warp(now + 1 hours);
        ethUsdcLPOracle.poke();
        uint256 lpTokenPriceOrig = uint256(ethUsdcLPOracle.read());

        // Give ourselves all the tokens available
        uint256 lpTokens = ERC20Like(ETH_USDC_GUNI_POOL).totalSupply();
        (uint256 usdcBal, uint256 ethBal) = GUNILike(ETH_USDC_GUNI_POOL).getUnderlyingBalances();
        giveTokens(ETH_USDC_GUNI_POOL, lpTokens);

        // Burn all tokens
        (uint256 amount0, uint256 amount1, ) = GUNILike(ETH_USDC_GUNI_POOL).burn(lpTokens, address(this));

        assertEq(amount0, usdcBal);
        assertEq(amount1, ethBal);

        hevm.warp(now + 1 hours);
        // This poke should fail as both balances are zero
        try ethUsdcLPOracle.poke() {
            assertTrue(false);
        } catch {
        }
        uint256 lpTokenPrice = uint256(ethUsdcLPOracle.read());

        assertEq(lpTokenPrice, lpTokenPriceOrig);
    }

    function test_near_zero_totalSupply() public {
        ethUsdcLPOracle.poke();
        hevm.warp(now + 1 hours);
        ethUsdcLPOracle.poke();
        uint256 lpTokenPriceOrig = uint256(ethUsdcLPOracle.read());

        // Give ourselves nearly all the tokens available
        uint256 lpTokens = ERC20Like(ETH_USDC_GUNI_POOL).totalSupply();
        (uint256 usdcBal, uint256 ethBal) = GUNILike(ETH_USDC_GUNI_POOL).getUnderlyingBalances();
        giveTokens(ETH_USDC_GUNI_POOL, lpTokens);

        // Burn almost all tokens
        (uint256 amount0, uint256 amount1, ) = GUNILike(ETH_USDC_GUNI_POOL).burn(lpTokens - 1e9, address(this));

        assertEqApprox(amount0, usdcBal, 1);
        assertEqApprox(amount1, ethBal, 1);

        hevm.warp(now + 1 hours);
        ethUsdcLPOracle.poke();
        hevm.warp(now + 1 hours);
        ethUsdcLPOracle.poke();
        uint256 lpTokenPrice = uint256(ethUsdcLPOracle.read());

        assertEqApprox(lpTokenPrice, lpTokenPriceOrig, 1);
    }

    // Verify Oracle price is unaffected by more complex mint/swap/burn sequence
    function test_mint_swap_burn() public {
        ERC20Like(ETH).approve(address(ETH_USDC_GUNI_POOL), type(uint256).max);
        ERC20Like(USDC).approve(address(ETH_USDC_GUNI_POOL), type(uint256).max);

        ethUsdcLPOracle.poke();
        hevm.warp(now + 1 hours);
        ethUsdcLPOracle.poke();
        uint256 lpTokenPrice1 = uint256(ethUsdcLPOracle.read());
        (uint256 usdcBalOrig, uint256 ethBalOrig) = GUNILike(ETH_USDC_GUNI_POOL).getUnderlyingBalances();
        (uint128 liquidityOrig, , , , ) = UniPoolLike(ETH_USDC_UNI_POOL).positions(GUNILike(ETH_USDC_GUNI_POOL).getPositionID());

        // Mint a bunch of tokens
        giveTokens(USDC, 100 * usdcBalOrig);
        giveTokens(ETH, 100 * ethBalOrig);
        (,, uint256 liquidityToMint) = GUNILike(ETH_USDC_GUNI_POOL).getMintAmounts(100 * usdcBalOrig, 100 * ethBalOrig);
        GUNILike(ETH_USDC_GUNI_POOL).mint(liquidityToMint, address(this));

        hevm.warp(now + 1 hours);
        ethUsdcLPOracle.poke();
        hevm.warp(now + 1 hours);
        ethUsdcLPOracle.poke();
        uint256 lpTokenPrice2 = uint256(ethUsdcLPOracle.read());
        assertEqApprox(lpTokenPrice2, lpTokenPrice1, 1);

        // Give enough tokens to totally skew the reserves
        uint256 balOrig = ERC20Like(USDC).balanceOf(ETH_USDC_UNI_POOL);
        assertGt(balOrig, 0);
        uint256 amount = 10 * ERC20Like(ETH).balanceOf(ETH_USDC_UNI_POOL);
        giveTokens(ETH, amount);
        UniPoolLike(ETH_USDC_UNI_POOL).swap(address(this), false, int256(amount), 13714534615519655739241256778826810, "");
        assertLt(ERC20Like(USDC).balanceOf(ETH_USDC_UNI_POOL) * 1e4 / balOrig, 500);    // New USDC balance should be less than 5% of original balance

        // Burn all tokens we previously minted
        GUNILike(ETH_USDC_GUNI_POOL).burn(ERC20Like(ETH_USDC_GUNI_POOL).balanceOf(address(this)), address(this));

        hevm.warp(now + 1 hours);
        ethUsdcLPOracle.poke();
        hevm.warp(now + 1 hours);
        ethUsdcLPOracle.poke();
        uint256 lpTokenPrice3 = uint256(ethUsdcLPOracle.read());
        assertEqApprox(lpTokenPrice3, lpTokenPrice1, 100);

        // Verify user can't steal the liquidity of previous users
        (uint128 liquidityEnd, , , , ) = UniPoolLike(ETH_USDC_UNI_POOL).positions(GUNILike(ETH_USDC_GUNI_POOL).getPositionID());
        assertGt(uint256(liquidityEnd), uint256(liquidityOrig));
    }

    // --- Fuzz ---
    uint256 constant MAX_PRICE = 1e12 * WAD;   // Max underlying asset Oracle price supported is $1 Trillion USD
    uint256 constant MIN_PRICE = 10**9;        // $0.000000001 USD
    uint256 constant MAX_DEC = 18;

    // https://github.com/Uniswap/uniswap-v3-core/blob/main/contracts/libraries/TickMath.sol
    uint160 constant MIN_SQRT_RATIO = 4295128739;
    uint160 constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    function test_sqrt_price_overflow_fuzz(uint256 p0, uint256 dec0, uint256 p1, uint256 dec1) public {
        p0 %= MAX_PRICE;
        if (p0 < MIN_PRICE) p0 = MIN_PRICE;
        p1 %= MAX_PRICE;
        if (p1 < MIN_PRICE) p1 = MIN_PRICE;
        dec0 %= MAX_DEC;
        dec1 %= MAX_DEC;

        uint256 UNIT_0 = 10 ** dec0;
        uint256 UNIT_1 = 10 ** dec1;

        uint256 sqrtPriceX96 = sqrt2(mul(mul(p0, UNIT_1), (1 << 96)) / (mul(p1, UNIT_0))) << 48;
        assertLt(sqrtPriceX96, 1 << 160);
    }

    // --- GUNI DAI-USDC ---
    // https://forum.makerdao.com/t/guni-dai-usdc-collateral-onboarding-oracle-assessment-mip10c3-sp41/10268
    uint256 constant MAX_PRICE_STABLE = 10014 * 10**14; // 1.0014 USD
    uint256 constant MIN_PRICE_STABLE = 9994  * 10**14; // 0.9994 USD
    uint256 constant DEC0_DAI  = MAX_DEC;               // 18
    uint256 constant DEC1_USDC = 6;

    function test_sqrt_price_ratio_dai_usdc_fuzz(uint256 p0, uint256 p1) public {
        p0 %= MAX_PRICE_STABLE;
        if (p0 < MIN_PRICE_STABLE) p0 = MIN_PRICE_STABLE;
        p1 %= MAX_PRICE_STABLE;
        if (p1 < MIN_PRICE_STABLE) p1 = MIN_PRICE_STABLE;

        uint256 UNIT_0 = 10 ** DEC0_DAI;
        uint256 UNIT_1 = 10 ** DEC1_USDC;

        uint160 sqrtPriceX96 = toUint160(sqrt2(mul(mul(p0, UNIT_1), (1 << 96)) / (mul(p1, UNIT_0))) << 48);

        // second inequality must be < because the price can never reach the price at the max tick
        assertTrue(sqrtPriceX96 >= MIN_SQRT_RATIO && sqrtPriceX96 < MAX_SQRT_RATIO);
    }

    // --- GUNI ETH-USDC ---
    uint256 constant MAX_PRICE_ETH  = MAX_PRICE;         // 1 Trilion USD
    uint256 constant MIN_PRICE_ETH  = WAD;               // 1 USD
    uint256 constant MAX_PRICE_USDC = MAX_PRICE_STABLE;  // 1.0014 USD
    uint256 constant MIN_PRICE_USDC = MIN_PRICE_STABLE;  // 0.9994 USD
    uint256 constant DEC0_ETH = MAX_DEC;                 // 18

    function test_sqrt_price_ratio_eth_usdc_fuzz(uint256 p0, uint256 p1) public {
        p0 %= MAX_PRICE_ETH;
        if (p0 < MIN_PRICE_ETH) p0 = MIN_PRICE_ETH;
        p1 %= MAX_PRICE_USDC;
        if (p1 < MIN_PRICE_USDC) p1 = MIN_PRICE_USDC;

        uint256 UNIT_0 = 10 ** DEC0_ETH;
        uint256 UNIT_1 = 10 ** DEC1_USDC;

        uint160 sqrtPriceX96 = toUint160(sqrt2(mul(mul(p0, UNIT_1), (1 << 96)) / (mul(p1, UNIT_0))) << 48);

        // second inequality must be < because the price can never reach the price at the max tick
        assertTrue(sqrtPriceX96 >= MIN_SQRT_RATIO && sqrtPriceX96 < MAX_SQRT_RATIO);
    }
}
