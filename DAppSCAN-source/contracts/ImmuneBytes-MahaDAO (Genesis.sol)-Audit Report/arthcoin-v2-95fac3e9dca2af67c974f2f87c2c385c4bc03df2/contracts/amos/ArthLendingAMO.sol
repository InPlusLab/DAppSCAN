// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import '../Arth/IARTH.sol';
import '../ARTHX/IARTHX.sol';
import '../ERC20/IERC20.sol';
import '../utils/math/SafeMath.sol';
import './finnexus/IFNX_CFNX.sol';
import './cream/ICREAM_crARTH.sol';
import './finnexus/IFNX_FPT_B.sol';
import '../Arth/Pools/IARTHPool.sol';
import '../ERC20/Variants/Comp.sol';
import './finnexus/IFNX_Oracle.sol';
import './finnexus/IFNX_MinePool.sol';
import './finnexus/IFNX_FPT_ARTH.sol';
import '../Oracle/UniswapPairOracle.sol';
import '../access/AccessControl.sol';
import './finnexus/IFNX_ManagerProxy.sol';
import './finnexus/IFNX_TokenConverter.sol';
import './finnexus/IFNX_IntegratedStake.sol';
import '../Arth/IARTHController.sol';

contract ArthLendingAMO is AccessControl {
    using SafeMath for uint256;

    /* ========== STATE VARIABLES ========== */

    IERC20 private collateralToken;
    IARTHX private ARTHX;
    IARTH private ARTH;
    IARTHPool private pool;
    IARTHController private controller;

    // Cream
    ICREAM_crARTH private crARTH =
        ICREAM_crARTH(0xb092b4601850E23903A42EaCBc9D8A0EeC26A4d5);

    // FinNexus
    // More addresses: https://github.com/FinNexus/FinNexus-Documentation/blob/master/content/developers/smart-contracts.md
    IFNX_FPT_ARTH private fnxFPT_ARTH =
        IFNX_FPT_ARTH(0x39ad661bA8a7C9D3A7E4808fb9f9D5223E22F763);
    IFNX_FPT_B private fnxFPT_B =
        IFNX_FPT_B(0x7E605Fb638983A448096D82fFD2958ba012F30Cd);
    IFNX_IntegratedStake private fnxIntegratedStake =
        IFNX_IntegratedStake(0x23e54F9bBe26eD55F93F19541bC30AAc2D5569b2);
    IFNX_MinePool private fnxMinePool =
        IFNX_MinePool(0x4e6005396F80a737cE80d50B2162C0a7296c9620);
    IFNX_TokenConverter private fnxTokenConverter =
        IFNX_TokenConverter(0x955282b82440F8F69E901380BeF2b603Fba96F3b);
    IFNX_ManagerProxy private fnxManagerProxy =
        IFNX_ManagerProxy(0xa2904Fd151C9d9D634dFA8ECd856E6B9517F9785);
    IFNX_Oracle private fnxOracle =
        IFNX_Oracle(0x43BD92bF3Bb25EBB3BdC2524CBd6156E3Fdd41F3);

    // Reward Tokens
    IFNX_CFNX private CFNX =
        IFNX_CFNX(0x9d7beb4265817a4923FAD9Ca9EF8af138499615d);
    IERC20 private FNX = IERC20(0xeF9Cd7882c067686691B6fF49e650b43AFBBCC6B);

    address public collateralAddress;
    address public pool_address;
    address public ownerAddress;
    address public timelock_address;
    address public custodian_address;

    uint256 public immutable missing_decimals;
    uint256 private constant PRICE_PRECISION = 1e6;

    // Max amount of ARTH this contract mint
    uint256 public mint_cap = uint256(100000e18);

    // Minimum collateral ratio needed for new ARTH minting
    uint256 public min_cr = 850000;

    // Amount the contract borrowed
    uint256 public minted_sum_historical = 0;
    uint256 public burned_sum_historical = 0;

    // Allowed strategies (can eventually be made into an array)
    bool public allow_cream = true;
    bool public allow_finnexus = true;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _arth_contract_address,
        address _arthx_contract_address,
        address _pool_address,
        address _collateralAddress,
        address _ownerAddress,
        address _custodian_address,
        address _timelock_address
    ) {
        ARTH = IARTH(_arth_contract_address);
        ARTHX = IARTHX(_arthx_contract_address);
        pool_address = _pool_address;
        pool = IARTHPool(_pool_address);
        collateralAddress = _collateralAddress;
        collateralToken = IERC20(_collateralAddress);
        timelock_address = _timelock_address;
        ownerAddress = _ownerAddress;
        custodian_address = _custodian_address;
        missing_decimals = uint256(18).sub(collateralToken.decimals());

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    /* ========== MODIFIERS ========== */

    modifier onlyByOwnerOrGovernance() {
        require(
            msg.sender == timelock_address || msg.sender == ownerAddress,
            'You are not the owner or the governance timelock'
        );
        _;
    }

    modifier onlyCustodian() {
        require(
            msg.sender == custodian_address,
            'You are not the rewards custodian'
        );
        _;
    }

    /* ========== VIEWS ========== */

    function showAllocations()
        external
        view
        returns (uint256[9] memory allocations)
    {
        // IMPORTANT
        // Should ONLY be used externally, because it may fail if any one of the functions below fail

        // All numbers given are in ARTH unless otherwise stated
        allocations[0] = ARTH.balanceOf(address(this)); // Unallocated ARTH
        allocations[1] = (
            crARTH
                .balanceOf(address(this))
                .mul(crARTH.exchangeRateStored())
                .div(1e18)
        ); // Cream
        allocations[2] = (fnxMinePool.getUserFPTABalance(address(this)))
            .mul(1e8)
            .div(fnxManagerProxy.getTokenNetworth()); // Staked FPT-ARTH
        allocations[3] = (fnxFPT_ARTH.balanceOf(address(this))).mul(1e8).div(
            fnxManagerProxy.getTokenNetworth()
        ); // Free FPT-ARTH
        allocations[4] = fnxTokenConverter.lockedBalanceOf(address(this)); // Unwinding CFNX
        allocations[5] = fnxTokenConverter.getClaimAbleBalance(address(this)); // Claimable Unwound FNX
        allocations[6] = FNX.balanceOf(address(this)); // Free FNX

        uint256 sum_fnx = allocations[4];
        sum_fnx = sum_fnx.add(allocations[5]);
        sum_fnx = sum_fnx.add(allocations[6]);
        allocations[7] = sum_fnx; // Total FNX possessed in various forms

        uint256 sum_arth = allocations[0];
        sum_arth = sum_arth.add(allocations[1]);
        sum_arth = sum_arth.add(allocations[2]);
        sum_arth = sum_arth.add(allocations[3]);
        allocations[8] = sum_arth; // Total ARTH possessed in various forms
    }

    function showRewards() external view returns (uint256[1] memory rewards) {
        // IMPORTANT
        // Should ONLY be used externally, because it may fail if FNX.balanceOf() fails
        rewards[0] = FNX.balanceOf(address(this)); // FNX
    }

    // In ARTH
    function mintedBalance() public view returns (uint256) {
        if (minted_sum_historical >= burned_sum_historical)
            return minted_sum_historical.sub(burned_sum_historical);
        else return 0;
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    // Needed for the Arth contract to not brick
    function getCollateralGMUBalance() external pure returns (uint256) {
        return 1e18; // 1 USDC
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    // This contract is essentially marked as a 'pool' so it can call OnlyPools functions like poolMint and poolBurnFrom
    // on the main ARTH contract
    function mintARTHForInvestments(uint256 arth_amount)
        public
        onlyByOwnerOrGovernance
    {
        uint256 borrowed_balance = mintedBalance();

        // Make sure you aren't minting more than the mint cap
        require(
            borrowed_balance.add(arth_amount) <= mint_cap,
            'Borrow cap reached'
        );
        minted_sum_historical = minted_sum_historical.add(arth_amount);

        // Make sure the current CR isn't already too low
        require(
            controller.getGlobalCollateralRatio() > min_cr,
            'Collateral ratio is already too low'
        );

        // Make sure the ARTH minting wouldn't push the CR down too much
        uint256 current_collateral_E18 =
            (controller.getGlobalCollateralValue()).mul(10**missing_decimals);
        uint256 cur_arth_supply = ARTH.totalSupply();
        uint256 new_arth_supply = cur_arth_supply.add(arth_amount);
        uint256 new_cr =
            (current_collateral_E18.mul(PRICE_PRECISION)).div(new_arth_supply);
        require(
            new_cr > min_cr,
            'Minting would cause collateral ratio to be too low'
        );

        // Mint the arth
        ARTH.poolMint(address(this), arth_amount);
    }

    // Give USDC profits back
    function giveCollatBack(uint256 amount) public onlyByOwnerOrGovernance {
        collateralToken.transfer(address(pool), amount);
    }

    // Burn unneeded or excess ARTH
    function burnARTH(uint256 arth_amount) public onlyByOwnerOrGovernance {
        // ARTH.burn(arth_amount);
        burned_sum_historical = burned_sum_historical.add(arth_amount);
    }

    // Burn unneeded ARTHX
    function burnARTHX(uint256 amount) public onlyByOwnerOrGovernance {
        ARTHX.approve(address(this), amount);
        ARTHX.poolBurnFrom(address(this), amount);
    }

    /* ==================== CREAM ==================== */

    // E18
    function creamDeposit_ARTH(uint256 ARTH_amount)
        public
        onlyByOwnerOrGovernance
    {
        require(allow_cream, 'Cream strategy is disabled');
        ARTH.approve(address(crARTH), ARTH_amount);
        require(crARTH.mint(ARTH_amount) == 0, 'Mint failed');
    }

    // E18
    function creamWithdraw_ARTH(uint256 ARTH_amount)
        public
        onlyByOwnerOrGovernance
    {
        require(
            crARTH.redeemUnderlying(ARTH_amount) == 0,
            'RedeemUnderlying failed'
        );
    }

    // E8
    function creamWithdraw_crARTH(uint256 crARTH_amount)
        public
        onlyByOwnerOrGovernance
    {
        require(crARTH.redeem(crARTH_amount) == 0, 'Redeem failed');
    }

    /* ==================== FinNexus ==================== */

    /* --== Staking ==-- */

    function fnxIntegratedStakeFPTs_ARTH_FNX(
        uint256 ARTH_amount,
        uint256 FNX_amount,
        uint256 lock_period
    ) public onlyByOwnerOrGovernance {
        require(allow_finnexus, 'FinNexus strategy is disabled');
        ARTH.approve(address(fnxIntegratedStake), ARTH_amount);
        FNX.approve(address(fnxIntegratedStake), FNX_amount);

        address[] memory fpta_tokens = new address[](1);
        uint256[] memory fpta_amounts = new uint256[](1);
        address[] memory fptb_tokens = new address[](1);
        uint256[] memory fptb_amounts = new uint256[](1);

        fpta_tokens[0] = address(ARTH);
        fpta_amounts[0] = ARTH_amount;
        fptb_tokens[0] = address(FNX);
        fptb_amounts[0] = FNX_amount;

        fnxIntegratedStake.stake(
            fpta_tokens,
            fpta_amounts,
            fptb_tokens,
            fptb_amounts,
            lock_period
        );
    }

    // FPT-ARTH : FPT-B = 10:1 is the best ratio for staking. You can get it using the prices.
    function fnxStakeARTHForFPT_ARTH(uint256 ARTH_amount, uint256 lock_period)
        public
        onlyByOwnerOrGovernance
    {
        require(allow_finnexus, 'FinNexus strategy is disabled');
        ARTH.approve(address(fnxIntegratedStake), ARTH_amount);

        address[] memory fpta_tokens = new address[](1);
        uint256[] memory fpta_amounts = new uint256[](1);
        address[] memory fptb_tokens = new address[](0);
        uint256[] memory fptb_amounts = new uint256[](0);

        fpta_tokens[0] = address(ARTH);
        fpta_amounts[0] = ARTH_amount;

        fnxIntegratedStake.stake(
            fpta_tokens,
            fpta_amounts,
            fptb_tokens,
            fptb_amounts,
            lock_period
        );
    }

    /* --== Collect CFNX ==-- */

    function fnxCollectCFNX() public onlyByOwnerOrGovernance {
        uint256 claimable_cfnx =
            fnxMinePool.getMinerBalance(address(this), address(CFNX));
        fnxMinePool.redeemMinerCoin(address(CFNX), claimable_cfnx);
    }

    /* --== UnStaking ==-- */

    // FPT-ARTH = Staked ARTH
    function fnxUnStakeFPT_ARTH(uint256 FPT_ARTH_amount)
        public
        onlyByOwnerOrGovernance
    {
        fnxMinePool.unstakeFPTA(FPT_ARTH_amount);
    }

    // FPT-B = Staked FNX
    function fnxUnStakeFPT_B(uint256 FPT_B_amount)
        public
        onlyByOwnerOrGovernance
    {
        fnxMinePool.unstakeFPTB(FPT_B_amount);
    }

    /* --== Unwrapping LP Tokens ==-- */

    // FPT-ARTH = Staked ARTH
    function fnxUnRedeemFPT_ARTHForARTH(uint256 FPT_ARTH_amount)
        public
        onlyByOwnerOrGovernance
    {
        fnxFPT_ARTH.approve(address(fnxManagerProxy), FPT_ARTH_amount);
        fnxManagerProxy.redeemCollateral(FPT_ARTH_amount, address(ARTH));
    }

    // FPT-B = Staked FNX
    function fnxUnStakeFPT_BForFNX(uint256 FPT_B_amount)
        public
        onlyByOwnerOrGovernance
    {
        fnxFPT_B.approve(address(fnxManagerProxy), FPT_B_amount);
        fnxManagerProxy.redeemCollateral(FPT_B_amount, address(FNX));
    }

    /* --== Convert CFNX to FNX ==-- */

    // Has to be done in batches, since it unlocks over several months
    function fnxInputCFNXForUnwinding() public onlyByOwnerOrGovernance {
        uint256 cfnx_amount = CFNX.balanceOf(address(this));
        CFNX.approve(address(fnxTokenConverter), cfnx_amount);
        fnxTokenConverter.inputCfnxForInstallmentPay(cfnx_amount);
    }

    function fnxClaimFNX_From_CFNX() public onlyByOwnerOrGovernance {
        fnxTokenConverter.claimFnxExpiredReward();
    }

    /* --== Combination Functions ==-- */

    function fnxCFNXCollectConvertUnwind() public onlyByOwnerOrGovernance {
        fnxCollectCFNX();
        fnxInputCFNXForUnwinding();
        fnxClaimFNX_From_CFNX();
    }

    /* ========== Custodian ========== */

    function withdrawRewards() public onlyCustodian {
        FNX.transfer(custodian_address, FNX.balanceOf(address(this)));
    }

    /* ========== RESTRICTED GOVERNANCE FUNCTIONS ========== */

    function setTimelock(address new_timelock)
        external
        onlyByOwnerOrGovernance
    {
        timelock_address = new_timelock;
    }

    function setOwner(address _ownerAddress) external onlyByOwnerOrGovernance {
        ownerAddress = _ownerAddress;
    }

    function setMiscRewardsCustodian(address _custodian_address)
        external
        onlyByOwnerOrGovernance
    {
        custodian_address = _custodian_address;
    }

    function setPool(address _pool_address) external onlyByOwnerOrGovernance {
        pool_address = _pool_address;
        pool = IARTHPool(_pool_address);
    }

    function setMintCap(uint256 _mint_cap) external onlyByOwnerOrGovernance {
        mint_cap = _mint_cap;
    }

    function setMinimumCollateralRatio(uint256 _min_cr)
        external
        onlyByOwnerOrGovernance
    {
        min_cr = _min_cr;
    }

    function setAllowedStrategies(bool _cream, bool _finnexus)
        external
        onlyByOwnerOrGovernance
    {
        allow_cream = _cream;
        allow_finnexus = _finnexus;
    }

    function recoverERC20(address tokenAddress, uint256 tokenAmount)
        external
        onlyByOwnerOrGovernance
    {
        // Can only be triggered by owner or governance, not custodian
        // Tokens are sent to the custodian, as a sort of safeguard

        IERC20(tokenAddress).transfer(custodian_address, tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    /* ========== EVENTS ========== */

    event Recovered(address token, uint256 amount);
}
