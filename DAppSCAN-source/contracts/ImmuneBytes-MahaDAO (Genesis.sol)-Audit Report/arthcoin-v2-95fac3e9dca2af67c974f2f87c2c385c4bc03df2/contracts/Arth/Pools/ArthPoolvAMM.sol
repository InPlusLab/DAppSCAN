// // SPDX-License-Identifier: MIT

// pragma solidity ^0.8.0;
// pragma experimental ABIEncoderV2;

// import '../../Arth/Arth.sol';
// import '../../utils/math/Math.sol';
// import '../../ERC20/ERC20.sol';
// import '../../ARTHS/ARTHS.sol';
// import '../../utils/math/SafeMath.sol';
// import '../../Uniswap/UniswapV2Library.sol';
// import '../../Oracle/UniswapPairOracle.sol';
// import '../../access/AccessControl.sol';

// /**
//  *  Original code written by:
//  *  - Travis Moore, Jason Huan, Same Kazemian, Sam Sun,
//  *  - github.com/denett
//  *  - github.com/realisation
//  *  Code modified by:
//  *  - Steven Enamakel, Yash Agrawal & Sagar Behara.
//  * TODO: 1) Have to call getVirtualReserves() on every update of the reserve, such that we can call _update with the averages of the reserve
//  */
// contract ArthPoolvAMM is AccessControl {
//     using SafeMath for uint256;

//     ERC20 private collateralToken;
//     ARTHStablecoin private ARTH;
//     ARTHShares private ARTHS;
//     UniswapPairOracle private arthxUSDCOracle;

//     address private collateralAddress;
//     address private arth_contract_address;
//     address private arthx_contract_address;
//     address public arthx_usdc_oracle_address;
//     address private uniswap_factory;

//     address private ownerAddress;
//     address private timelock_address;

//     uint256 public mintingFee;
//     uint256 public redemptionFee;
//     uint256 public buybackFee;
//     uint256 public recollatFee;

//     // Mint check tolerance
//     uint256 public max_drift_band;

//     mapping(address => uint256) public redeemARTHSBalances;
//     mapping(address => uint256) public redeemCollateralBalances;
//     uint256 public unclaimedPoolCollateral;
//     uint256 public unclaimedPoolARTHS;
//     mapping(address => uint256) public lastRedeemed;

//     // Constants for various precisions
//     uint256 private constant PRICE_PRECISION = 1e6;
//     uint256 private constant COLLATERAL_RATIO_PRECISION = 1e6;
//     uint256 private constant COLLATERAL_RATIO_MAX = 1e6;

//     // Number of decimals needed to get to 18
//     uint256 public immutable missing_decimals;
//     // Pool_ceiling is the total units of collateral that a pool contract can hold
//     uint256 public pool_ceiling;
//     // Stores price of the collateral, if price is paused
//     uint256 public pausedPrice;
//     // Bonus rate on ARTHX minted during recollateralizeARTH(); 6 decimals of precision
//     uint256 public bonus_rate;
//     // Number of blocks to wait before being able to collectRedemption()
//     uint256 public redemptionDelay;
//     // Number of seconds to wait before refreshing virtual AMM reserves
//     uint256 public reserve_refresh_cooldown;
//     // Last reserve refresh
//     uint256 public last_reserve_refresh;

//     // For investing collateral
//     uint256 public global_investment_cap_percentage = 10000; // 1e6 precision
//     uint256 public collateral_invested = 0; // Keeps track of how much collateral the investor was given
//     address public investor_contract_address; // All of the investing code logic will be offloaded to the investor contract

//     // AccessControl Roles
//     bytes32 private constant MINT_PAUSER = keccak256('MINT_PAUSER');
//     bytes32 private constant REDEEM_PAUSER = keccak256('REDEEM_PAUSER');
//     bytes32 private constant BUYBACK_PAUSER = keccak256('BUYBACK_PAUSER');
//     bytes32 private constant RECOLLATERALIZE_PAUSER =
//         keccak256('RECOLLATERALIZE_PAUSER');
//     bytes32 private constant COLLATERAL_PRICE_PAUSER =
//         keccak256('COLLATERAL_PRICE_PAUSER');

//     // AccessControl state variables
//     bool public mintPaused = false;
//     bool public redeemPaused = false;
//     bool public recollateralizePaused = false;
//     bool public buyBackPaused = false;
//     bool public collateralPricePaused = false;

//     // Drift related
//     uint256 public drift_end_time = 0;
//     uint256 public last_update_time = 0;
//     uint256 public collat_virtual_reserves = 0;
//     uint256 public arthx_virtual_reserves = 0; // Needs to be nonzero here initially
//     uint256 drift_arthx_positive = 0;
//     uint256 drift_arthx_negative = 0;
//     uint256 drift_collat_positive = 0;
//     uint256 drift_collat_negative = 0;
//     uint256 public arthxPrice_cumulative = 0;
//     uint256 public arthxPrice_cumulative_prev = 0;
//     uint256 public last_drift_refresh = 0;
//     uint256 public drift_refresh_period = 0;
//     uint256 public k_virtual_amm = 0;

//     /* ========== MODIFIERS ========== */

//     modifier onlyByOwnerOrGovernance() {
//         require(
//             msg.sender == timelock_address || msg.sender == ownerAddress,
//             'You are not the owner or the governance timelock'
//         );
//         _;
//     }

//     modifier onlyInvestor() {
//         require(
//             msg.sender == investor_contract_address,
//             'You are not the investor'
//         );
//         _;
//     }

//     modifier notMintPaused() {
//         require(mintPaused == false, 'Minting is paused');
//         _;
//     }

//     modifier notRedeemPaused() {
//         require(redeemPaused == false, 'Redeeming is paused');
//         _;
//     }

//     /* ========== CONSTRUCTOR ========== */

//     constructor(
//         address _arth_contract_address,
//         address _arthx_contract_address,
//         address _collateralAddress,
//         address _creator_address,
//         address _timelock_address,
//         address _uniswap_factory_address,
//         address _arthx_usdc_oracle_addr,
//         uint256 _pool_ceiling
//     ) {
//         ARTH = ARTHStablecoin(_arth_contract_address);
//         ARTHX = ARTHShares(_arthx_contract_address);
//         arth_contract_address = _arth_contract_address;
//         arthx_contract_address = _arthx_contract_address;
//         collateralAddress = _collateralAddress;
//         timelock_address = _timelock_address;
//         ownerAddress = _creator_address;
//         collateralToken = ERC20(_collateralAddress);
//         pool_ceiling = _pool_ceiling;
//         uniswap_factory = _uniswap_factory_address;

//         missing_decimals = uint256(18).sub(collateralToken.decimals());
//         pool_ceiling = 100000e6;
//         pausedPrice = 0;
//         bonus_rate = 0;
//         redemptionDelay = 2;
//         reserve_refresh_cooldown = 3600;
//         mintingFee = 4500;
//         redemptionFee = 4500;
//         buybackFee = 4500;
//         recollatFee = 4500;
//         max_drift_band = 50000; // 5%. Also used to potentially curtail sandwich attacks

//         drift_refresh_period = 900;

//         last_update_time = block.timestamp.sub(drift_refresh_period + 1);
//         drift_end_time = block.timestamp.sub(1);

//         arthx_usdc_oracle_address = _arthx_usdc_oracle_addr;
//         arthxUSDCOracle = UniswapPairOracle(_arthx_usdc_oracle_addr);

//         (uint112 reserve0, uint112 reserve1, ) =
//             arthxUSDCOracle.pair().getReserves();
//         if (arthxUSDCOracle.token0() == arthx_contract_address) {
//             arthx_virtual_reserves = reserve0;
//             collat_virtual_reserves = reserve1;
//         } else {
//             arthx_virtual_reserves = reserve1;
//             collat_virtual_reserves = reserve0;
//         }

//         _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
//         grantRole(MINT_PAUSER, timelock_address);
//         grantRole(REDEEM_PAUSER, timelock_address);
//         grantRole(RECOLLATERALIZE_PAUSER, timelock_address);
//         grantRole(BUYBACK_PAUSER, timelock_address);
//         grantRole(COLLATERAL_PRICE_PAUSER, timelock_address);
//     }

//     /* ========== VIEWS ========== */

//     // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
//     // uses constant product concept https://uniswap.org/docs/v2/core-concepts/swaps/
//     function getAmountOut(
//         uint256 amountIn,
//         uint256 reserveIn,
//         uint256 reserveOut,
//         uint256 the_fee
//     ) public pure returns (uint256 amountOut) {
//         require(amountIn > 0, 'ARTH_vAMM: INSUFFICIENT_INPUT_AMOUNT');
//         require(
//             reserveIn > 0 && reserveOut > 0,
//             'ARTH_vAMM: INSUFFICIENT_LIQUIDITY'
//         );
//         uint256 amountInWithFee = amountIn.mul(uint256(1e6).sub(the_fee));
//         uint256 numerator = amountInWithFee.mul(reserveOut);
//         uint256 denominator = (reserveIn.mul(1e6)).add(amountInWithFee);
//         amountOut = numerator / denominator;
//     }

//     // Courtesy of github.com/denett
//     function getVirtualReserves()
//         public
//         view
//         returns (
//             uint256 current_arthx_virtual_reserves,
//             uint256 current_collat_virtual_reserves,
//             uint256 average_arthx_virtual_reserves,
//             uint256 average_collat_virtual_reserves
//         )
//     {
//         current_arthx_virtual_reserves = arthx_virtual_reserves;
//         current_collat_virtual_reserves = collat_virtual_reserves;
//         uint256 drift_time = 0;
//         if (drift_end_time > last_update_time) {
//             drift_time =
//                 Math.min(block.timestamp, drift_end_time) -
//                 last_update_time;
//             if (drift_time > 0) {
//                 if (drift_arthx_positive > 0)
//                     current_arthx_virtual_reserves = current_arthx_virtual_reserves
//                         .add(drift_arthx_positive.mul(drift_time));
//                 else
//                     current_arthx_virtual_reserves = current_arthx_virtual_reserves
//                         .sub(drift_arthx_negative.mul(drift_time));

//                 if (drift_collat_positive > 0)
//                     current_collat_virtual_reserves = current_collat_virtual_reserves
//                         .add(drift_collat_positive.mul(drift_time));
//                 else
//                     current_collat_virtual_reserves = current_collat_virtual_reserves
//                         .sub(drift_collat_negative.mul(drift_time));
//             }
//         }
//         average_arthx_virtual_reserves = arthx_virtual_reserves
//             .add(current_arthx_virtual_reserves)
//             .div(2);
//         average_collat_virtual_reserves = collat_virtual_reserves
//             .add(current_collat_virtual_reserves)
//             .div(2);

//         // Adjust for when time was split between drift and no drift.
//         uint256 time_elapsed = block.timestamp - last_update_time;
//         if (time_elapsed > drift_time && drift_time > 0) {
//             average_arthx_virtual_reserves = average_arthx_virtual_reserves
//                 .mul(drift_time)
//                 .add(
//                 current_arthx_virtual_reserves.mul(time_elapsed.sub(drift_time))
//             )
//                 .div(time_elapsed);
//             average_collat_virtual_reserves = average_collat_virtual_reserves
//                 .mul(drift_time)
//                 .add(
//                 current_collat_virtual_reserves.mul(
//                     time_elapsed.sub(drift_time)
//                 )
//             )
//                 .div(time_elapsed);
//         }
//     }

//     // Courtesy of github.com/denett
//     // Updates the reserve drifts
//     function refreshDrift() external {
//         require(
//             block.timestamp >= drift_end_time,
//             'Drift refresh is cooling down'
//         );

//         // First apply the drift of the previous period
//         (
//             uint256 current_arthx_virtual_reserves,
//             uint256 current_collat_virtual_reserves,
//             uint256 average_arthx_virtual_reserves,
//             uint256 average_collat_virtual_reserves
//         ) = getVirtualReserves();
//         _update(
//             current_arthx_virtual_reserves,
//             current_collat_virtual_reserves,
//             average_arthx_virtual_reserves,
//             average_collat_virtual_reserves
//         );

//         // Calculate the reserves at the average internal price over the last period and the current K
//         uint256 time_elapsed = block.timestamp - last_drift_refresh;
//         uint256 average_period_price_arthx =
//             (arthxPrice_cumulative - arthxPrice_cumulative_prev).div(
//                 time_elapsed
//             );
//         uint256 internal_k =
//             current_arthx_virtual_reserves.mul(current_collat_virtual_reserves);
//         uint256 collat_reserves_average_price =
//             sqrt(internal_k.mul(average_period_price_arthx));
//         uint256 arthx_reserves_average_price =
//             internal_k.div(collat_reserves_average_price);

//         // Calculate the reserves at the average external price over the last period and the target K
//         (uint256 ext_average_arthx_usd_price, uint256 ext_k) = getOracleInfo();
//         uint256 targetK =
//             internal_k > ext_k
//                 ? Math.max(ext_k, internal_k.sub(internal_k.div(100))) // Decrease or
//                 : Math.min(ext_k, internal_k.add(internal_k.div(100))); // Increase K no more than 1% per period
//         uint256 ext_collat_reserves_average_price =
//             sqrt(targetK.mul(ext_average_arthx_usd_price));
//         uint256 ext_arthx_reserves_average_price =
//             targetK.div(ext_collat_reserves_average_price);

//         // Calculate the drifts per second
//         if (collat_reserves_average_price < ext_collat_reserves_average_price) {
//             drift_collat_positive = (ext_collat_reserves_average_price -
//                 collat_reserves_average_price)
//                 .div(drift_refresh_period);
//             drift_collat_negative = 0;
//         } else {
//             drift_collat_positive = 0;
//             drift_collat_negative = (collat_reserves_average_price -
//                 ext_collat_reserves_average_price)
//                 .div(drift_refresh_period);
//         }

//         if (arthx_reserves_average_price < ext_arthx_reserves_average_price) {
//             drift_arthx_positive = (ext_arthx_reserves_average_price -
//                 arthx_reserves_average_price)
//                 .div(drift_refresh_period);
//             drift_arthx_negative = 0;
//         } else {
//             drift_arthx_positive = 0;
//             drift_arthx_negative = (arthx_reserves_average_price -
//                 ext_arthx_reserves_average_price)
//                 .div(drift_refresh_period);
//         }

//         arthxPrice_cumulative_prev = arthxPrice_cumulative;
//         last_drift_refresh = block.timestamp;
//         drift_end_time = block.timestamp.add(drift_refresh_period);
//     }

//     // Gets the external average arthx price over the previous period and the external K
//     function getOracleInfo()
//         public
//         view
//         returns (uint256 ext_average_arthx_usd_price, uint256 ext_k)
//     {
//         ext_average_arthx_usd_price = arthxUSDCOracle.consult(
//             arthx_contract_address,
//             1e18
//         );
//         (uint112 reserve0, uint112 reserve1, ) =
//             arthxUSDCOracle.pair().getReserves();
//         ext_k = uint256(reserve0).mul(uint256(reserve1));
//     }

//     // Needed for compatibility with ArthPool standard
//     function getCollateralGMUBalance() public view returns (uint256) {
//         return
//             (
//                 collateralToken
//                     .balanceOf(address(this))
//                     .add(collateral_invested)
//                     .sub(unclaimedPoolCollateral)
//             )
//                 .mul(10**missing_decimals);
//     }

//     function getAvailableExcessCollateralDV() public view returns (uint256) {
//         uint256 total_supply = ARTH.totalSupply();
//         uint256 globalCollateralRatio = ARTH.globalCollateralRatio();
//         uint256 globalCollatValue = ARTH.globalCollateralValue();

//         uint256 target_collat_value =
//             total_supply.mul(globalCollateralRatio).div(1e6);

//         if (globalCollatValue > target_collat_value) {
//             return globalCollatValue.sub(target_collat_value);
//         } else {
//             return 0;
//         }
//     }

//     function availableForInvestment() public view returns (uint256 max_invest) {
//         uint256 curr_pool_bal =
//             collateralToken
//                 .balanceOf(address(this))
//                 .add(collateral_invested)
//                 .sub(unclaimedPoolCollateral);
//         max_invest = curr_pool_bal.mul(global_investment_cap_percentage).div(
//             1e6
//         );
//     }

//     /* ========== INTERNAL ========== */

//     // Courtesy of github.com/denett
//     // Update the reserves and the cumulative price
//     function _update(
//         uint256 current_arthx_virtual_reserves,
//         uint256 current_collat_virtual_reserves,
//         uint256 average_arthx_virtual_reserves,
//         uint256 average_collat_virtual_reserves
//     ) private {
//         uint256 time_elapsed = block.timestamp - last_update_time;
//         if (time_elapsed > 0) {
//             arthxPrice_cumulative += average_arthx_virtual_reserves
//                 .mul(1e18)
//                 .div(average_collat_virtual_reserves)
//                 .mul(time_elapsed);
//         }
//         arthx_virtual_reserves = current_arthx_virtual_reserves;
//         collat_virtual_reserves = current_collat_virtual_reserves;
//         last_update_time = block.timestamp;
//     }

//     /* ========== PUBLIC FUNCTIONS ========== */

//     function mintFractionalARTH(
//         uint256 collateralAmount,
//         uint256 arthxAmount,
//         uint256 ARTHOutMin
//     )
//         public
//         notMintPaused
//         returns (
//             uint256,
//             uint256,
//             uint256
//         )
//     {
//         uint256 globalCollateralRatio = ARTH.globalCollateralRatio();

//         // Do not need to equalize decimals between ARTHX and collateral, getAmountOut & reserves takes care of it
//         // Still need to adjust for ARTH (18 decimals) and collateral (not always 18 decimals)
//         uint256 total_arth_mint;
//         uint256 collat_needed;
//         uint256 arthx_needed;
//         if (globalCollateralRatio == 1e6) {
//             // 1-to-1
//             total_arth_mint = collateralAmount.mul(10**missing_decimals);
//             collat_needed = collateralAmount;
//             arthx_needed = 0;
//         } else if (globalCollateralRatio == 0) {
//             // Algorithmic
//             // Assumes 1 collat = 1 ARTH at all times
//             total_arth_mint = getAmountOut(
//                 arthxAmount,
//                 arthx_virtual_reserves,
//                 collat_virtual_reserves,
//                 mintingFee
//             );
//             _update(
//                 arthx_virtual_reserves.add(arthxAmount),
//                 collat_virtual_reserves.sub(total_arth_mint),
//                 arthx_virtual_reserves,
//                 collat_virtual_reserves
//             );

//             total_arth_mint = total_arth_mint.mul(10**missing_decimals);
//             collat_needed = 0;
//             arthx_needed = arthxAmount;
//         } else {
//             // Fractional
//             // Assumes 1 collat = 1 ARTH at all times
//             uint256 arth_mint_from_arthx =
//                 getAmountOut(
//                     arthxAmount,
//                     arthx_virtual_reserves,
//                     collat_virtual_reserves,
//                     mintingFee
//                 );
//             _update(
//                 arthx_virtual_reserves.add(arthxAmount),
//                 collat_virtual_reserves.sub(arth_mint_from_arthx),
//                 arthx_virtual_reserves,
//                 collat_virtual_reserves
//             );

//             collat_needed = arth_mint_from_arthx.mul(1e6).div(
//                 uint256(1e6).sub(globalCollateralRatio)
//             ); // find collat needed at collateral ratio
//             require(
//                 collat_needed <= collateralAmount,
//                 'Not enough collateral inputted'
//             );

//             uint256 arth_mint_from_collat =
//                 collat_needed.mul(10**missing_decimals);
//             arth_mint_from_arthx = arth_mint_from_arthx.mul(
//                 10**missing_decimals
//             );
//             total_arth_mint = arth_mint_from_arthx.add(arth_mint_from_collat);
//             arthx_needed = arthxAmount;
//         }

//         require(total_arth_mint >= ARTHOutMin, 'Slippage limit reached');
//         require(
//             collateralToken
//                 .balanceOf(address(this))
//                 .add(collateral_invested)
//                 .sub(unclaimedPoolCollateral)
//                 .add(collat_needed) <= pool_ceiling,
//             'Pool ceiling reached, no more ARTH can be minted with this collateral'
//         );

//         ARTHS.poolBurnFrom(msg.sender, arthx_needed);
//         collateralToken.transferFrom(msg.sender, address(this), collat_needed);

//         // Sanity check to make sure the ARTH mint amount is close to the expected amount from the collateral input
//         // Using collateral_needed here could cause problems if the reserves are off
//         // Useful in case of a sandwich attack or some other fault with the virtual reserves
//         // Assumes $1 collateral (USDC, USDT, DAI, etc)
//         require(
//             total_arth_mint <=
//                 collateralAmount
//                     .mul(10**missing_decimals)
//                     .mul(uint256(1e6).add(max_drift_band))
//                     .div(globalCollateralRatio),
//             '[max_drift_band] Too much ARTH being minted'
//         );
//         ARTH.poolMint(msg.sender, total_arth_mint);

//         return (total_arth_mint, collat_needed, arthx_needed);
//     }

//     function redeemFractionalARTH(
//         uint256 ARTH_amount,
//         uint256 ARTHXOutMin,
//         uint256 collateral_out_min
//     )
//         public
//         notRedeemPaused
//         returns (
//             uint256,
//             uint256,
//             uint256
//         )
//     {
//         uint256 globalCollateralRatio = ARTH.globalCollateralRatio();

//         uint256 collat_out;
//         uint256 arthx_out;

//         uint256 collat_equivalent = ARTH_amount.div(10**missing_decimals);

//         if (globalCollateralRatio == 1e6) {
//             // 1-to-1
//             collat_out = collat_equivalent;
//             arthx_out = 0;
//         } else if (globalCollateralRatio == 0) {
//             // Algorithmic
//             arthx_out = getAmountOut(
//                 collat_equivalent,
//                 collat_virtual_reserves,
//                 arthx_virtual_reserves,
//                 redemptionFee
//             ); // switch ARTH to units of collateral and swap
//             collat_out = 0;

//             _update(
//                 arthx_virtual_reserves.sub(arthx_out),
//                 collat_virtual_reserves.add(collat_equivalent),
//                 arthx_virtual_reserves,
//                 collat_virtual_reserves
//             );
//         } else {
//             // Fractional
//             collat_out = collat_equivalent.mul(globalCollateralRatio).div(
//                 1e6
//             );
//             arthx_out = getAmountOut(
//                 collat_equivalent
//                     .mul((uint256(1e6).sub(globalCollateralRatio)))
//                     .div(1e6),
//                 collat_virtual_reserves,
//                 arthx_virtual_reserves,
//                 redemptionFee
//             );

//             _update(
//                 arthx_virtual_reserves.sub(arthx_out),
//                 collat_virtual_reserves.add(
//                     collat_equivalent
//                         .mul((uint256(1e6).sub(globalCollateralRatio)))
//                         .div(1e6)
//                 ),
//                 arthx_virtual_reserves,
//                 collat_virtual_reserves
//             );
//         }

//         require(
//             collat_out <=
//                 collateralToken.balanceOf(address(this)).sub(
//                     unclaimedPoolCollateral
//                 ),
//             'Not enough collateral in pool'
//         );
//         require(
//             collat_out >= collateral_out_min,
//             'Slippage limit reached [collateral]'
//         );
//         require(arthx_out >= ARTHXOutMin, 'Slippage limit reached [ARTHS]');

//         // Sanity check to make sure the collat amount is close to the expected amount from the ARTH input
//         // This check is redundant since collat_out is essentially supplied by the user
//         // Useful in case of a sandwich attack or some other fault with the virtual reserves	        // arthx_out should receive a sanity check instead
//         // Assumes $1 collateral (USDC, USDT, DAI, etc)	        // one possible way to do this may be to obtain the twap price while infering how much slippage
//         // a trade at that price might incur according to the percentage of the reserves that were
//         // traded and that may approximate a sane transaction.
//         // Alternatively, maybe it could be done as it is done on lines 496 and 497.

//         require(
//             collat_out.mul(10**missing_decimals) <=
//                 ARTH_amount
//                     .mul(globalCollateralRatio)
//                     .mul(uint256(1e6).add(max_drift_band))
//                     .div(1e12),
//             '[max_drift_band] Too much collateral being released'
//         );

//         redeemCollateralBalances[msg.sender] = redeemCollateralBalances[
//             msg.sender
//         ]
//             .add(collat_out);
//         unclaimedPoolCollateral = unclaimedPoolCollateral.add(collat_out);

//         redeemARTHSBalances[msg.sender] = redeemARTHSBalances[msg.sender].add(
//             arthx_out
//         );
//         unclaimedPoolARTHX = unclaimedPoolARTHS.add(arthx_out);

//         lastRedeemed[msg.sender] = block.number;

//         ARTH.poolBurnFrom(msg.sender, ARTH_amount);
//         ARTHS.poolMint(address(this), arthx_out);

//         return (ARTH_amount, collat_out, arthx_out);
//     }

//     // After a redemption happens, transfer the newly minted ARTHX and owed collateral from this pool
//     // contract to the user. Redemption is split into two functions to prevent flash loans from being able
//     // to take out ARTH/collateral from the system, use an AMM to trade the new price, and then mint back into the system.
//     function collectRedemption() external returns (uint256, uint256) {
//         require(
//             (lastRedeemed[msg.sender].add(redemptionDelay)) <= block.number,
//             'Must wait for redemptionDelay blocks before collecting redemption'
//         );
//         bool sendARTHX = false;
//         bool sendCollateral = false;
//         uint256 ARTHSAmount;
//         uint256 CollateralAmount;

//         // Use Checks-Effects-Interactions pattern
//         if (redeemARTHSBalances[msg.sender] > 0) {
//             ARTHSAmount = redeemARTHSBalances[msg.sender];
//             redeemARTHSBalances[msg.sender] = 0;
//             unclaimedPoolARTHX = unclaimedPoolARTHS.sub(ARTHSAmount);

//             sendARTHX = true;
//         }

//         if (redeemCollateralBalances[msg.sender] > 0) {
//             CollateralAmount = redeemCollateralBalances[msg.sender];
//             redeemCollateralBalances[msg.sender] = 0;
//             unclaimedPoolCollateral = unclaimedPoolCollateral.sub(
//                 CollateralAmount
//             );

//             sendCollateral = true;
//         }

//         if (sendARTHX == true) {
//             ARTHS.transfer(msg.sender, ARTHSAmount);
//         }
//         if (sendCollateral == true) {
//             collateralToken.transfer(msg.sender, CollateralAmount);
//         }

//         return (CollateralAmount, ARTHSAmount);
//     }

//     function recollateralizeARTH(
//         uint256 collateralAmount,
//         uint256 ARTHS_out_min
//     ) external returns (uint256, uint256) {
//         require(recollateralizePaused == false, 'Recollateralize is paused');
//         uint256 arthx_out =
//             getAmountOut(
//                 collateralAmount,
//                 collat_virtual_reserves,
//                 arthx_virtual_reserves,
//                 recollatFee
//             );

//         _update(
//             arthx_virtual_reserves.sub(arthx_out),
//             collat_virtual_reserves.add(collateralAmount),
//             arthx_virtual_reserves,
//             collat_virtual_reserves
//         );
//         require(arthx_out >= ARTHS_out_min, 'Slippage limit reached');

//         uint256 total_supply = ARTH.totalSupply();
//         uint256 globalCollateralRatio = ARTH.globalCollateralRatio();
//         uint256 globalCollatValue = ARTH.globalCollateralValue();
//         uint256 target_collat_value = total_supply.mul(globalCollateralRatio);

//         require(
//             target_collat_value >=
//                 globalCollatValue +
//                     collateralAmount.mul(10**missing_decimals),
//             'Too much recollateralize inputted'
//         );

//         collateralToken.transferFrom(
//             msg.sender,
//             address(this),
//             collateralAmount
//         );

//         // Sanity check to make sure the value of the outgoing ARTHX amount is close to the expected amount based on the collateral input
//         // Ignores the bonus, as it will be added in later
//         // Useful in case of a sandwich attack or some other fault with the virtual reserves
//         // Assumes $1 collateral (USDC, USDT, DAI, etc)
//         uint256 arthxPrice =
//             arthxUSDCOracle.consult(arthx_contract_address, 1e18); // comes out e6
//         require(
//             arthx_out.mul(arthxPrice).div(1e6) <=
//                 collateralAmount
//                     .mul(10**missing_decimals)
//                     .mul(uint256(1e6).add(max_drift_band))
//                     .div(1e6),
//             '[max_drift_band] Too much ARTHX being released'
//         );

//         // Add in the bonus
//         arthx_out = arthx_out.add(arthx_out.mul(bonus_rate).div(1e6));

//         ARTHS.poolMint(msg.sender, arthx_out);

//         return (collateralAmount, arthx_out);
//     }

//     function buyBackARTHX(uint256 ARTHS_amount, uint256 COLLATERAL_out_min)
//         external
//         returns (uint256, uint256)
//     {
//         require(buyBackPaused == false, 'Buyback is paused');
//         uint256 buyback_available =
//             getAvailableExcessCollateralDV().div(10**missing_decimals);
//         uint256 collat_out =
//             getAmountOut(
//                 ARTHS_amount,
//                 arthx_virtual_reserves,
//                 collat_virtual_reserves,
//                 buybackFee
//             );

//         require(buyback_available > 0, 'Zero buyback available');
//         require(
//             collat_out <= buyback_available,
//             'Not enough buyback available'
//         );
//         require(collat_out >= COLLATERAL_out_min, 'Slippage limit reached');
//         _update(
//             arthx_virtual_reserves.sub(ARTHS_amount),
//             collat_virtual_reserves.add(collat_out),
//             arthx_virtual_reserves,
//             collat_virtual_reserves
//         );

//         ARTHS.poolBurnFrom(msg.sender, ARTHS_amount);

//         // Sanity check to make sure the value of the outgoing collat amount is close to the expected amount based on the ARTHX input
//         // Useful in case of a sandwich attack or some other fault with the virtual reserves
//         // Assumes $1 collateral (USDC, USDT, DAI, etc)
//         uint256 arthxPrice =
//             arthxUSDCOracle.consult(arthx_contract_address, 1e18); // comes out e6
//         require(
//             collat_out.mul(10**missing_decimals) <=
//                 ARTHS_amount
//                     .mul(arthxPrice)
//                     .mul(uint256(1e6).add(max_drift_band))
//                     .div(1e12),
//             '[max_drift_band] Too much collateral being released'
//         );

//         collateralToken.transfer(msg.sender, collat_out);

//         return (ARTHS_amount, collat_out);
//     }

//     // Send collateral to investor contract
//     // Called by INVESTOR CONTRACT
//     function takeOutCollat_Inv(uint256 amount) external onlyInvestor {
//         require(
//             collateral_invested.add(amount) <= availableForInvestment(),
//             'Investment cap reached'
//         );
//         collateral_invested = collateral_invested.add(amount);
//         collateralToken.transfer(investor_contract_address, amount);
//     }

//     // Deposit collateral back to this contract
//     // Called by INVESTOR CONTRACT
//     function putBackCollat_Inv(uint256 amount) external onlyInvestor {
//         if (amount < collateral_invested)
//             collateral_invested = collateral_invested.sub(amount);
//         else collateral_invested = 0;
//         collateralToken.transferFrom(
//             investor_contract_address,
//             address(this),
//             amount
//         );
//     }

//     /* ========== MISC FUNCTIONS ========== */

//     // SQRT from here: https://ethereum.stackexchange.com/questions/2910/can-i-square-root-in-solidity
//     function sqrt(uint256 x) internal pure returns (uint256 y) {
//         uint256 z = (x + 1) / 2;
//         y = x;
//         while (z < y) {
//             y = z;
//             z = (x / z + z) / 2;
//         }
//     }

//     /* ========== RESTRICTED FUNCTIONS ========== */

//     function toggleMinting(bool state) external {
//         require(hasRole(MINT_PAUSER, msg.sender));
//         mintPaused = state;
//     }

//     function toggleRedeeming(bool state) external {
//         require(hasRole(REDEEM_PAUSER, msg.sender));
//         redeemPaused = state;
//     }

//     function toggleRecollateralize(bool state) external {
//         require(hasRole(RECOLLATERALIZE_PAUSER, msg.sender));
//         recollateralizePaused = state;
//     }

//     function toggleBuyBack(bool state) external {
//         require(hasRole(BUYBACK_PAUSER, msg.sender));
//         buyBackPaused = state;
//     }

//     function toggleCollateralPrice(bool state, uint256 _new_price) external {
//         require(hasRole(COLLATERAL_PRICE_PAUSER, msg.sender));
//         collateralPricePaused = state;

//         if (collateralPricePaused == true) {
//             pausedPrice = _new_price;
//         }
//     }

//     // Combined into one function due to 24KiB contract memory limit
//     function setPoolParameters(
//         uint256 new_ceiling,
//         uint256 new_bonus_rate,
//         uint256 new_redemptionDelay,
//         uint256 new_mint_fee,
//         uint256 new_redeem_fee,
//         uint256 new_buybackFee,
//         uint256 new_recollatFee,
//         uint256 _reserve_refresh_cooldown,
//         uint256 _max_drift_band
//     ) external onlyByOwnerOrGovernance {
//         pool_ceiling = new_ceiling;
//         bonus_rate = new_bonus_rate;
//         redemptionDelay = new_redemptionDelay;
//         mintingFee = new_mint_fee;
//         redemptionFee = new_redeem_fee;
//         buybackFee = new_buybackFee;
//         recollatFee = new_recollatFee;
//         reserve_refresh_cooldown = _reserve_refresh_cooldown;
//         max_drift_band = _max_drift_band;
//     }

//     // Sets the ARTHS_USDC Uniswap oracle address
//     function setARTHSUSDCOracle(address _arthx_usdc_oracle_addr)
//         public
//         onlyByOwnerOrGovernance
//     {
//         arthx_usdc_oracle_address = _arthx_usdc_oracle_addr;
//         arthxUSDCOracle = UniswapPairOracle(_arthx_usdc_oracle_addr);
//     }

//     function setTimelock(address new_timelock)
//         external
//         onlyByOwnerOrGovernance
//     {
//         timelock_address = new_timelock;
//     }

//     function setOwner(address _ownerAddress) external onlyByOwnerOrGovernance {
//         ownerAddress = _ownerAddress;
//     }

//     function setInvestorParameters(
//         address _investor_contract_address,
//         uint256 _global_investment_cap_percentage
//     ) external onlyByOwnerOrGovernance {
//         investor_contract_address = _investor_contract_address;
//         global_investment_cap_percentage = _global_investment_cap_percentage;
//     }
// }
