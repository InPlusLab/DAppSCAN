// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "./interfaces/IController.sol";
import "./interfaces/ILiquidations.sol";
import "./interfaces/ITreasury.sol";
import "./helpers/DecimalMath.sol";
import "./helpers/Delegable.sol";
import "./helpers/Orchestrated.sol";


/**
 * @dev The Liquidations contract allows to liquidate undercollateralized weth vaults in a reverse Dutch auction.
 * Undercollateralized vaults can be liquidated by calling `liquidate`.
 * Collateral from vaults can be bought with Dai using `buy`.
 * Debt and collateral records will be adjusted in the Controller using `controller.grab`.
 * Dai taken in payment will be handed over to Treasury, and collateral assets bought will be taken from Treasury as well.
 * If a vault becomes colalteralized, the liquidation can be stopped with `cancel`.
 */
contract Liquidations is ILiquidations, Orchestrated(), Delegable(), DecimalMath {

    event Liquidation(address indexed user, uint256 started, uint256 collateral, uint256 debt);

    bytes32 public constant WETH = "ETH-A";
    uint256 public constant AUCTION_TIME = 3600;
    uint256 public constant DUST = 25000000000000000; // 0.025 ETH
    uint128 public constant FEE = 25000000000000000; // 0.025 ETH

    IERC20 internal _dai;
    ITreasury internal _treasury;
    IController internal _controller;

    struct Vault {
        uint128 collateral;
        uint128 debt;
    }

    mapping(address => uint256) public liquidations;
    mapping(address => Vault) public vaults;
    Vault public override totals;

    bool public live = true;

    /// @dev The Liquidations constructor links it to the Dai, Treasury and Controller contracts.
    constructor (
        address dai_,
        address treasury_,
        address controller_
    ) public {
        _dai = IERC20(dai_);
        _treasury = ITreasury(treasury_);
        _controller = IController(controller_);
    }

    /// @dev Only while Liquidations is not unwinding due to a MakerDAO shutdown.
    modifier onlyLive() {
        require(live == true, "Controller: Not available during unwind");
        _;
    }

    /// @dev Overflow-protected addition, from OpenZeppelin
    function add(uint128 a, uint128 b)
        internal pure returns (uint128)
    {
        uint128 c = a + b;
        require(c >= a, "Market: Dai reserves too high");

        return c;
    }

    /// @dev Overflow-protected substraction, from OpenZeppelin
    function sub(uint128 a, uint128 b) internal pure returns (uint128) {
        require(b <= a, "Market: yDai reserves too low");
        uint128 c = a - b;

        return c;
    }

    /// @dev Safe casting from uint256 to uint128
    function toUint128(uint256 x) internal pure returns(uint128) {
        require(
            x <= 340282366920938463463374607431768211455,
            "Market: Cast overflow"
        );
        return uint128(x);
    }

    /// @dev Disables buying at liquidations. To be called only when Treasury shuts down.
    function shutdown() public override {
        require(
            _treasury.live() == false,
            "Liquidations: Treasury is live"
        );
        live = false;
    }


    /// @dev Return if the debt of an user is between zero and the dust level
    /// @param user Address of the user vault
    function aboveDustOrZero(address user) public view returns (bool) {
        uint256 collateral = vaults[user].collateral;
        return collateral == 0 || DUST < collateral;
    }

    /// @dev Starts a liquidation process for an undercollateralized vault.
    /// A liquidation fee is transferred from the liquidated user to a designated account as payment.
    /// @param user Address of the user vault to liquidate.
    /// @param to Address of the liquidations account to receive the liquidation fee.
    function liquidate(address user, address to)
        public onlyLive
    {
        require(
            !_controller.isCollateralized(WETH, user),
            "Liquidations: Vault is not undercollateralized"
        );
        // A user in liquidation can be liquidated again, but doesn't restart the auction clock
        // solium-disable-next-line security/no-block-members
        if (liquidations[user] == 0) liquidations[user] = now;

        (uint256 userCollateral, uint256 userDebt) = _controller.erase(WETH, user);
        totals = Vault({
            collateral: add(totals.collateral, toUint128(userCollateral)),
            debt: add(totals.debt, toUint128(userDebt))
        });

        Vault memory vault = Vault({ // TODO: Test a user that is liquidated twice
            collateral: add(vaults[user].collateral, sub(toUint128(userCollateral), FEE)),
            debt: add(vaults[user].debt, toUint128(userDebt))
        });
        vaults[user] = vault;

        vaults[to].collateral = add(vaults[to].collateral, FEE);

        emit Liquidation(user, now, userCollateral, userDebt);
    }

    /// @dev Buy a portion of a position under liquidation.
    /// The caller pays the debt of `user`, and `from` receives an amount of collateral.
    /// `from` can delegate to other addresses to buy for him. Also needs to use `ERC20.approve`.
    /// @param liquidated Address of the user vault to liquidate.
    /// @param from Address of the wallet paying Dai for liquidated collateral.
    /// @param to Address of the wallet to send the obtained collateral to.
    /// @param daiAmount Amount of Dai to give in exchange for liquidated collateral.
    /// @return The amount of collateral obtained.
    function buy(address from, address to, address liquidated, uint256 daiAmount)
        public onlyLive
        onlyHolderOrDelegate(from, "Controller: Only Holder Or Delegate")
        returns (uint256)
    {
        require(
            vaults[liquidated].debt > 0,
            "Liquidations: Vault is not in liquidation"
        );
        _treasury.pushDai(from, daiAmount);

        // calculate collateral to grab. Using divdrup stops rounding from leaving 1 stray wei in vaults.
        uint256 tokenAmount = divdrup(daiAmount, price(liquidated));

        totals = Vault({
            collateral: sub(totals.collateral, toUint128(tokenAmount)),
            debt: sub(totals.debt, toUint128(daiAmount))
        });

        Vault memory vault = Vault({
            collateral: sub(vaults[liquidated].collateral, toUint128(tokenAmount)),
            debt: sub(vaults[liquidated].debt, toUint128(daiAmount))
        });
        vaults[liquidated] = vault;

        _treasury.pullWeth(to, tokenAmount);

        require(
            aboveDustOrZero(liquidated),
            "Liquidations: Below dust"
        );

        return tokenAmount;
    }

    /// @dev Retrieve weth from a liquidations account. This weth could come from liquidator fees or as remainders of liquidations.
    /// `from` can delegate to other addresses to withdraw from him.
    /// @param from Address of the liquidations user vault to withdraw weth from.
    /// @param to Address of the wallet receiving the withdrawn weth.
    /// @param tokenAmount Amount of Weth to withdraw.
    function withdraw(address from, address to, uint256 tokenAmount)
        public onlyLive
        onlyHolderOrDelegate(from, "Controller: Only Holder Or Delegate")
    {
        Vault storage vault = vaults[from];
        require(
            vault.debt == 0,
            "Liquidations: User still in liquidation"
        );

        totals.collateral = sub(totals.collateral, toUint128(tokenAmount));
        vault.collateral = sub(vault.collateral, toUint128(tokenAmount));

        _treasury.pullWeth(to, tokenAmount);
    }

    /// @dev Removes all collateral and debt for an user.
    /// This function can only be called by other Yield contracts, not users directly.
    /// @param user Address of the user vault
    /// @return The amounts of collateral and debt removed from Liquidations.
    function erase(address user)
        public override
        onlyOrchestrated("Liquidations: Not Authorized")
        returns (uint128, uint128)
    {
        Vault storage vault = vaults[user];
        uint128 collateral = vault.collateral;
        uint128 debt = vault.debt;

        totals = Vault({
            collateral: sub(totals.collateral, collateral),
            debt: sub(totals.debt, debt)
        });
        delete vaults[user];

        return (collateral, debt);
    }

    /// @dev Return price of a collateral unit, in dai, at the present moment, for a given user
    /// @param user Address of the user vault in liquidation.
    // dai = price * collateral
    //
    //                collateral      1      min(auction, elapsed)
    // price = 1 / (------------- * (--- + -----------------------))
    //                   debt         2       2 * auction
    function price(address user) public view returns (uint256) {
        require(
            liquidations[user] > 0,
            "Liquidations: Vault is not targeted"
        );
        uint256 dividend1 = uint256(vaults[user].collateral);
        uint256 divisor1 = uint256(vaults[user].debt);
        uint256 term1 = dividend1.mul(UNIT).div(divisor1);
        uint256 dividend3 = Math.min(AUCTION_TIME, now - liquidations[user]); // - unlikely to overflow
        uint256 divisor3 = AUCTION_TIME.mul(2);
        uint256 term2 = UNIT.div(2);
        uint256 term3 = dividend3.mul(UNIT).div(divisor3);
        return divd(UNIT, muld(term1, term2 + term3)); // + unlikely to overflow
    }
}
