pragma solidity 0.4.24;

import "@aragon/os/contracts/apps/AragonApp.sol";
import "@aragon/os/contracts/common/EtherTokenConstant.sol";
import "@aragon/os/contracts/common/IsContract.sol";
import "@aragon/os/contracts/common/SafeERC20.sol";
import "@aragon/os/contracts/lib/math/SafeMath.sol";
import "@aragon/os/contracts/lib/token/ERC20.sol";
import "@aragon/apps-agent/contracts/Agent.sol";
import "@ablack/fundraising-batched-bancor-market-maker/contracts/BatchedBancorMarketMaker.sol";
import "@ablack/fundraising-presale/contracts/Presale.sol";
import "@ablack/fundraising-tap/contracts/Tap.sol";
import "@ablack/fundraising-shared-interfaces/contracts/IAragonFundraisingController.sol";


contract AragonFundraisingController is EtherTokenConstant, IsContract, IAragonFundraisingController, AragonApp {
    using SafeERC20 for ERC20;
    using SafeMath  for uint256;

    /**
    Hardcoded constants to save gas
    bytes32 public constant UPDATE_BENEFICIARY_ROLE                    = keccak256("UPDATE_BENEFICIARY_ROLE");
    bytes32 public constant UPDATE_FEES_ROLE                           = keccak256("UPDATE_FEES_ROLE");
    bytes32 public constant ADD_COLLATERAL_TOKEN_ROLE                  = keccak256("ADD_COLLATERAL_TOKEN_ROLE");
    bytes32 public constant REMOVE_COLLATERAL_TOKEN_ROLE               = keccak256("REMOVE_COLLATERAL_TOKEN_ROLE");
    bytes32 public constant UPDATE_COLLATERAL_TOKEN_ROLE               = keccak256("UPDATE_COLLATERAL_TOKEN_ROLE");
    bytes32 public constant UPDATE_MAXIMUM_TAP_RATE_INCREASE_PCT_ROLE  = keccak256("UPDATE_MAXIMUM_TAP_RATE_INCREASE_PCT_ROLE");
    bytes32 public constant UPDATE_MAXIMUM_TAP_FLOOR_DECREASE_PCT_ROLE = keccak256("UPDATE_MAXIMUM_TAP_FLOOR_DECREASE_PCT_ROLE");
    bytes32 public constant ADD_TOKEN_TAP_ROLE                         = keccak256("ADD_TOKEN_TAP_ROLE");
    bytes32 public constant UPDATE_TOKEN_TAP_ROLE                      = keccak256("UPDATE_TOKEN_TAP_ROLE");
    bytes32 public constant OPEN_PRESALE_ROLE                          = keccak256("OPEN_PRESALE_ROLE");
    bytes32 public constant OPEN_TRADING_ROLE                          = keccak256("OPEN_TRADING_ROLE");
    bytes32 public constant CONTRIBUTE_ROLE                            = keccak256("CONTRIBUTE_ROLE");
    bytes32 public constant OPEN_BUY_ORDER_ROLE                        = keccak256("OPEN_BUY_ORDER_ROLE");
    bytes32 public constant OPEN_SELL_ORDER_ROLE                       = keccak256("OPEN_SELL_ORDER_ROLE");
    bytes32 public constant WITHDRAW_ROLE                              = keccak256("WITHDRAW_ROLE");
    */
    bytes32 public constant UPDATE_BENEFICIARY_ROLE                    = 0xf7ea2b80c7b6a2cab2c11d2290cb005c3748397358a25e17113658c83b732593;
    bytes32 public constant UPDATE_FEES_ROLE                           = 0x5f9be2932ed3a723f295a763be1804c7ebfd1a41c1348fb8bdf5be1c5cdca822;
    bytes32 public constant ADD_COLLATERAL_TOKEN_ROLE                  = 0x217b79cb2bc7760defc88529853ef81ab33ae5bb315408ce9f5af09c8776662d;
    bytes32 public constant REMOVE_COLLATERAL_TOKEN_ROLE               = 0x2044e56de223845e4be7d0a6f4e9a29b635547f16413a6d1327c58d9db438ee2;
    bytes32 public constant UPDATE_COLLATERAL_TOKEN_ROLE               = 0xe0565c2c43e0d841e206bb36a37f12f22584b4652ccee6f9e0c071b697a2e13d;
    bytes32 public constant UPDATE_MAXIMUM_TAP_RATE_INCREASE_PCT_ROLE  = 0x5d94de7e429250eee4ff97e30ab9f383bea3cd564d6780e0a9e965b1add1d207;
    bytes32 public constant UPDATE_MAXIMUM_TAP_FLOOR_DECREASE_PCT_ROLE = 0x57c9c67896cf0a4ffe92cbea66c2f7c34380af06bf14215dabb078cf8a6d99e1;
    bytes32 public constant ADD_TOKEN_TAP_ROLE                         = 0xbc9cb5e3f7ce81c4fd021d86a4bcb193dee9df315b540808c3ed59a81e596207;
    bytes32 public constant UPDATE_TOKEN_TAP_ROLE                      = 0xdb8c88bedbc61ea0f92e1ce46da0b7a915affbd46d1c76c4bbac9a209e4a8416;
    bytes32 public constant OPEN_PRESALE_ROLE                          = 0xf323aa41eef4850a8ae7ebd047d4c89f01ce49c781f3308be67303db9cdd48c2;
    bytes32 public constant OPEN_TRADING_ROLE                          = 0x26ce034204208c0bbca4c8a793d17b99e546009b1dd31d3c1ef761f66372caf6;
    bytes32 public constant CONTRIBUTE_ROLE                            = 0x9ccaca4edf2127f20c425fdd86af1ba178b9e5bee280cd70d88ac5f6874c4f07;
    bytes32 public constant OPEN_BUY_ORDER_ROLE                        = 0xa589c8f284b76fc8d510d9d553485c47dbef1b0745ae00e0f3fd4e28fcd77ea7;
    bytes32 public constant OPEN_SELL_ORDER_ROLE                       = 0xd68ba2b769fa37a2a7bd4bed9241b448bc99eca41f519ef037406386a8f291c0;
    bytes32 public constant WITHDRAW_ROLE                              = 0x5d8e12c39142ff96d79d04d15d1ba1269e4fe57bb9d26f43523628b34ba108ec;

    uint256 public constant TO_RESET_CAP = 10;

    string private constant ERROR_CONTRACT_IS_EOA = "FUNDRAISING_CONTRACT_IS_EOA";
    string private constant ERROR_INVALID_TOKENS  = "FUNDRAISING_INVALID_TOKENS";

    Presale                  public presale;
    BatchedBancorMarketMaker public marketMaker;
    Agent                    public reserve;
    Tap                      public tap;
    address[]                public toReset;


    /***** external functions *****/

    /**
     * @notice Initialize Aragon Fundraising controller
     * @param _presale     The address of the presale contract
     * @param _marketMaker The address of the market maker contract
     * @param _reserve     The address of the reserve [pool] contract
     * @param _tap         The address of the tap contract
     * @param _toReset     The addresses of the tokens whose tap timestamps are to be reset [when presale is closed and trading is open]
    */
    function initialize(
        Presale                  _presale,
        BatchedBancorMarketMaker _marketMaker,
        Agent                    _reserve,
        Tap                      _tap,
        address[]                _toReset
    )
        external
        onlyInit
    {
        require(isContract(_presale),           ERROR_CONTRACT_IS_EOA);
        require(isContract(_marketMaker),       ERROR_CONTRACT_IS_EOA);
        require(isContract(_reserve),           ERROR_CONTRACT_IS_EOA);
        require(isContract(_tap),               ERROR_CONTRACT_IS_EOA);
        require(_toReset.length < TO_RESET_CAP, ERROR_INVALID_TOKENS);

        initialized();

        presale = _presale;
        marketMaker = _marketMaker;
        reserve = _reserve;
        tap = _tap;

        for (uint256 i = 0; i < _toReset.length; i++) {
            require(_tokenIsContractOrETH(_toReset[i]), ERROR_INVALID_TOKENS);
            toReset.push(_toReset[i]);
        }
    }

    /* generic settings related function */

    /**
     * @notice Update beneficiary to `_beneficiary`
     * @param _beneficiary The address of the new beneficiary
    */
    function updateBeneficiary(address _beneficiary) external auth(UPDATE_BENEFICIARY_ROLE) {
        marketMaker.updateBeneficiary(_beneficiary);
        tap.updateBeneficiary(_beneficiary);
    }

    /**
     * @notice Update fees deducted from buy and sell orders to respectively `@formatPct(_buyFeePct)`% and `@formatPct(_sellFeePct)`%
     * @param _buyFeePct  The new fee to be deducted from buy orders [in PCT_BASE]
     * @param _sellFeePct The new fee to be deducted from sell orders [in PCT_BASE]
    */
    function updateFees(uint256 _buyFeePct, uint256 _sellFeePct) external auth(UPDATE_FEES_ROLE) {
        marketMaker.updateFees(_buyFeePct, _sellFeePct);
    }

    /* presale related functions */

    /**
     * @notice Open presale
    */
    function openPresale() external auth(OPEN_PRESALE_ROLE) {
        presale.open();
    }

    /**
     * @notice Close presale and open trading
    */
    function closePresale() external isInitialized {
        presale.close();
    }

    /**
     * @notice Contribute to the presale up to `@tokenAmount(self.contributionToken(): address, _value)`
     * @param _value The amount of contribution token to be spent
    */
    function contribute(uint256 _value) external payable auth(CONTRIBUTE_ROLE) {
        presale.contribute.value(msg.value)(msg.sender, _value);
    }

    /**
     * @notice Refund `_contributor`'s presale contribution #`_vestedPurchaseId`
     * @param _contributor      The address of the contributor whose presale contribution is to be refunded
     * @param _vestedPurchaseId The id of the contribution to be refunded
    */
    function refund(address _contributor, uint256 _vestedPurchaseId) external isInitialized {
        presale.refund(_contributor, _vestedPurchaseId);
    }

    /* market making related functions */

    /**
     * @notice Open trading [enabling users to open buy and sell orders]
    */
    function openTrading() external auth(OPEN_TRADING_ROLE) {
        for (uint256 i = 0; i < toReset.length; i++) {
            tap.resetTappedToken(toReset[i]);
        }

        marketMaker.open();
    }

    /**
     * @notice Open a buy order worth `@tokenAmount(_collateral, _value)`
     * @param _collateral The address of the collateral token to be spent
     * @param _value      The amount of collateral token to be spent
    */
    function openBuyOrder(address _collateral, uint256 _value) external payable auth(OPEN_BUY_ORDER_ROLE) {
        marketMaker.openBuyOrder.value(msg.value)(msg.sender, _collateral, _value);
    }

    /**
     * @notice Open a sell order worth `@tokenAmount(self.token(): address, _amount)` against `_collateral.symbol(): string`
     * @param _collateral The address of the collateral token to be returned
     * @param _amount     The amount of bonded token to be spent
    */
    function openSellOrder(address _collateral, uint256 _amount) external auth(OPEN_SELL_ORDER_ROLE) {
        marketMaker.openSellOrder(msg.sender, _collateral, _amount);
    }

    /**
     * @notice Claim the results of `_collateral.symbol(): string` buy orders from batch #`_batchId`
     * @param _buyer      The address of the user whose buy orders are to be claimed
     * @param _batchId    The id of the batch in which buy orders are to be claimed
     * @param _collateral The address of the collateral token against which buy orders are to be claimed
    */
    function claimBuyOrder(address _buyer, uint256 _batchId, address _collateral) external isInitialized {
        marketMaker.claimBuyOrder(_buyer, _batchId, _collateral);
    }

    /**
     * @notice Claim the results of `_collateral.symbol(): string` sell orders from batch #`_batchId`
     * @param _seller     The address of the user whose sell orders are to be claimed
     * @param _batchId    The id of the batch in which sell orders are to be claimed
     * @param _collateral The address of the collateral token against which sell orders are to be claimed
    */
    function claimSellOrder(address _seller, uint256 _batchId, address _collateral) external isInitialized {
        marketMaker.claimSellOrder(_seller, _batchId, _collateral);
    }

    /* collateral tokens related functions */

    /**
     * @notice Add `_collateral.symbol(): string` as a whitelisted collateral token
     * @param _collateral     The address of the collateral token to be whitelisted
     * @param _virtualSupply  The virtual supply to be used for that collateral token [in wei]
     * @param _virtualBalance The virtual balance to be used for that collateral token [in wei]
     * @param _reserveRatio   The reserve ratio to be used for that collateral token [in PPM]
     * @param _slippage       The price slippage below which each market making batch is to be kept for that collateral token [in PCT_BASE]
     * @param _rate           The rate at which that token is to be tapped [in wei / block]
     * @param _floor          The floor above which the reserve [pool] balance for that token is to be kept [in wei]
    */
    function addCollateralToken(
        address _collateral,
        uint256 _virtualSupply,
        uint256 _virtualBalance,
        uint32  _reserveRatio,
        uint256 _slippage,
        uint256 _rate,
        uint256 _floor
    )
    	external
        auth(ADD_COLLATERAL_TOKEN_ROLE)
    {
        marketMaker.addCollateralToken(_collateral, _virtualSupply, _virtualBalance, _reserveRatio, _slippage);
        if (_collateral != ETH) {
            reserve.addProtectedToken(_collateral);
        }
        if (_rate > 0) {
            tap.addTappedToken(_collateral, _rate, _floor);
        }
    }

    /**
     * @notice Re-add `_collateral.symbol(): string` as a whitelisted collateral token [if it has been un-whitelisted in the past]
     * @param _collateral     The address of the collateral token to be whitelisted
     * @param _virtualSupply  The virtual supply to be used for that collateral token [in wei]
     * @param _virtualBalance The virtual balance to be used for that collateral token [in wei]
     * @param _reserveRatio   The reserve ratio to be used for that collateral token [in PPM]
     * @param _slippage       The price slippage below which each market making batch is to be kept for that collateral token [in PCT_BASE]
    */
    function reAddCollateralToken(
        address _collateral,
        uint256 _virtualSupply,
        uint256 _virtualBalance,
        uint32  _reserveRatio,
        uint256 _slippage
    )
    	external
        auth(ADD_COLLATERAL_TOKEN_ROLE)
    {
        marketMaker.addCollateralToken(_collateral, _virtualSupply, _virtualBalance, _reserveRatio, _slippage);
    }

    /**
      * @notice Remove `_collateral.symbol(): string` as a whitelisted collateral token
      * @param _collateral The address of the collateral token to be un-whitelisted
    */
    function removeCollateralToken(address _collateral) external auth(REMOVE_COLLATERAL_TOKEN_ROLE) {
        marketMaker.removeCollateralToken(_collateral);
        // the token should still be tapped to avoid being locked
        // the token should still be protected to avoid being spent
    }

    /**
     * @notice Update `_collateral.symbol(): string` collateralization settings
     * @param _collateral     The address of the collateral token whose collateralization settings are to be updated
     * @param _virtualSupply  The new virtual supply to be used for that collateral token [in wei]
     * @param _virtualBalance The new virtual balance to be used for that collateral token [in wei]
     * @param _reserveRatio   The new reserve ratio to be used for that collateral token [in PPM]
     * @param _slippage       The new price slippage below which each market making batch is to be kept for that collateral token [in PCT_BASE]
    */
    function updateCollateralToken(
        address _collateral,
        uint256 _virtualSupply,
        uint256 _virtualBalance,
        uint32  _reserveRatio,
        uint256 _slippage
    )
        external
        auth(UPDATE_COLLATERAL_TOKEN_ROLE)
    {
        marketMaker.updateCollateralToken(_collateral, _virtualSupply, _virtualBalance, _reserveRatio, _slippage);
    }

    /* tap related functions */

    /**
     * @notice Update maximum tap rate increase percentage to `@formatPct(_maximumTapRateIncreasePct)`%
     * @param _maximumTapRateIncreasePct The new maximum tap rate increase percentage to be allowed [in PCT_BASE]
    */
    function updateMaximumTapRateIncreasePct(uint256 _maximumTapRateIncreasePct) external auth(UPDATE_MAXIMUM_TAP_RATE_INCREASE_PCT_ROLE) {
        tap.updateMaximumTapRateIncreasePct(_maximumTapRateIncreasePct);
    }

    /**
     * @notice Update maximum tap floor decrease percentage to `@formatPct(_maximumTapFloorDecreasePct)`%
     * @param _maximumTapFloorDecreasePct The new maximum tap floor decrease percentage to be allowed [in PCT_BASE]
    */
    function updateMaximumTapFloorDecreasePct(uint256 _maximumTapFloorDecreasePct) external auth(UPDATE_MAXIMUM_TAP_FLOOR_DECREASE_PCT_ROLE) {
        tap.updateMaximumTapFloorDecreasePct(_maximumTapFloorDecreasePct);
    }

    /**
     * @notice Add tap for `_token.symbol(): string` with a rate of `@tokenAmount(_token, _rate)` per block and a floor of `@tokenAmount(_token, _floor)`
     * @param _token The address of the token to be tapped
     * @param _rate  The rate at which that token is to be tapped [in wei / block]
     * @param _floor The floor above which the reserve [pool] balance for that token is to be kept [in wei]
    */
    function addTokenTap(address _token, uint256 _rate, uint256 _floor) external auth(ADD_TOKEN_TAP_ROLE) {
        tap.addTappedToken(_token, _rate, _floor);
    }

    /**
     * @notice Update tap for `_token.symbol(): string` with a rate of about `@tokenAmount(_token, 4 * 60 * 24 * 30 * _rate)` per month and a floor of `@tokenAmount(_token, _floor)`
     * @param _token The address of the token whose tap is to be updated
     * @param _rate  The new rate at which that token is to be tapped [in wei / block]
     * @param _floor The new floor above which the reserve [pool] balance for that token is to be kept [in wei]
    */
    function updateTokenTap(address _token, uint256 _rate, uint256 _floor) external auth(UPDATE_TOKEN_TAP_ROLE) {
        tap.updateTappedToken(_token, _rate, _floor);
    }

    /**
     * @notice Transfer about `@tokenAmount(_token, self.getMaximumWithdrawal(_token): uint256)` from the reserve to the beneficiary
     * @param _token The address of the token to be transfered from the reserve to the beneficiary
    */
    function withdraw(address _token) external auth(WITHDRAW_ROLE) {
        tap.withdraw(_token);
    }

    /***** public view functions *****/

    function token() public view isInitialized returns (address) {
        return marketMaker.token();
    }

    function contributionToken() public view isInitialized returns (address) {
        return presale.contributionToken();
    }

    function getMaximumWithdrawal(address _token) public view isInitialized returns (uint256) {
        return tap.getMaximumWithdrawal(_token);
    }

    function collateralsToBeClaimed(address _collateral) public view isInitialized returns (uint256) {
        return marketMaker.collateralsToBeClaimed(_collateral);
    }

    function balanceOf(address _who, address _token) public view isInitialized returns (uint256) {
        uint256 balance = _token == ETH ? _who.balance : ERC20(_token).staticBalanceOf(_who);

        if (_who == address(reserve)) {
            return balance.sub(tap.getMaximumWithdrawal(_token));
        } else {
            return balance;
        }
    }

    /***** internal functions *****/

     function _tokenIsContractOrETH(address _token) internal view returns (bool) {
        return isContract(_token) || _token == ETH;
    }
}
