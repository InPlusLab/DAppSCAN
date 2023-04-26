pragma solidity 0.4.24;

import "@aragon/os/contracts/apps/AragonApp.sol";
import "@aragon/os/contracts/common/EtherTokenConstant.sol";
import "@aragon/os/contracts/common/IsContract.sol";
import "@aragon/os/contracts/common/TimeHelpers.sol";
import "@aragon/os/contracts/common/SafeERC20.sol";
import "@aragon/os/contracts/lib/math/SafeMath.sol";
import "@aragon/os/contracts/lib/token/ERC20.sol";
import "@aragon/apps-vault/contracts/Vault.sol";
import "@ablack/fundraising-shared-interfaces/contracts/IAragonFundraisingController.sol";


contract Tap is TimeHelpers, EtherTokenConstant, IsContract, AragonApp {
    using SafeERC20 for ERC20;
    using SafeMath  for uint256;

    /**
    Hardcoded constants to save gas
    bytes32 public constant UPDATE_CONTROLLER_ROLE                     = keccak256("UPDATE_CONTROLLER_ROLE");
    bytes32 public constant UPDATE_RESERVE_ROLE                        = keccak256("UPDATE_RESERVE_ROLE");
    bytes32 public constant UPDATE_BENEFICIARY_ROLE                    = keccak256("UPDATE_BENEFICIARY_ROLE");
    bytes32 public constant UPDATE_MAXIMUM_TAP_RATE_INCREASE_PCT_ROLE  = keccak256("UPDATE_MAXIMUM_TAP_RATE_INCREASE_PCT_ROLE");
    bytes32 public constant UPDATE_MAXIMUM_TAP_FLOOR_DECREASE_PCT_ROLE = keccak256("UPDATE_MAXIMUM_TAP_FLOOR_DECREASE_PCT_ROLE");
    bytes32 public constant ADD_TAPPED_TOKEN_ROLE                      = keccak256("ADD_TAPPED_TOKEN_ROLE");
    bytes32 public constant REMOVE_TAPPED_TOKEN_ROLE                   = keccak256("REMOVE_TAPPED_TOKEN_ROLE");
    bytes32 public constant UPDATE_TAPPED_TOKEN_ROLE                   = keccak256("UPDATE_TAPPED_TOKEN_ROLE");
    bytes32 public constant RESET_TAPPED_TOKEN_ROLE                    = keccak256("RESET_TAPPED_TOKEN_ROLE");
    bytes32 public constant WITHDRAW_ROLE                              = keccak256("WITHDRAW_ROLE");
    */
    bytes32 public constant UPDATE_CONTROLLER_ROLE                     = 0x454b5d0dbb74f012faf1d3722ea441689f97dc957dd3ca5335b4969586e5dc30;
    bytes32 public constant UPDATE_RESERVE_ROLE                        = 0x7984c050833e1db850f5aa7476710412fd2983fcec34da049502835ad7aed4f7;
    bytes32 public constant UPDATE_BENEFICIARY_ROLE                    = 0xf7ea2b80c7b6a2cab2c11d2290cb005c3748397358a25e17113658c83b732593;
    bytes32 public constant UPDATE_MAXIMUM_TAP_RATE_INCREASE_PCT_ROLE  = 0x5d94de7e429250eee4ff97e30ab9f383bea3cd564d6780e0a9e965b1add1d207;
    bytes32 public constant UPDATE_MAXIMUM_TAP_FLOOR_DECREASE_PCT_ROLE = 0x57c9c67896cf0a4ffe92cbea66c2f7c34380af06bf14215dabb078cf8a6d99e1;
    bytes32 public constant ADD_TAPPED_TOKEN_ROLE                      = 0x5bc3b608e6be93b75a1c472a4a5bea3d31eabae46bf968e4bc4c7701562114dc;
    bytes32 public constant REMOVE_TAPPED_TOKEN_ROLE                   = 0xd76960be78bfedc5b40ce4fa64a2f8308f39dd2cbb1f9676dbc4ce87b817befd;
    bytes32 public constant UPDATE_TAPPED_TOKEN_ROLE                   = 0x83201394534c53ae0b4696fd49a933082d3e0525aa5a3d0a14a2f51e12213288;
    bytes32 public constant RESET_TAPPED_TOKEN_ROLE                    = 0x294bf52c518669359157a9fe826e510dfc3dbd200d44bf77ec9536bff34bc29e;
    bytes32 public constant WITHDRAW_ROLE                              = 0x5d8e12c39142ff96d79d04d15d1ba1269e4fe57bb9d26f43523628b34ba108ec;

    uint256 public constant PCT_BASE = 10 ** 18; // 0% = 0; 1% = 10 ** 16; 100% = 10 ** 18

    string private constant ERROR_CONTRACT_IS_EOA            = "TAP_CONTRACT_IS_EOA";
    string private constant ERROR_INVALID_BENEFICIARY        = "TAP_INVALID_BENEFICIARY";
    string private constant ERROR_INVALID_BATCH_BLOCKS       = "TAP_INVALID_BATCH_BLOCKS";
    string private constant ERROR_INVALID_FLOOR_DECREASE_PCT = "TAP_INVALID_FLOOR_DECREASE_PCT";
    string private constant ERROR_INVALID_TOKEN              = "TAP_INVALID_TOKEN";
    string private constant ERROR_INVALID_TAP_RATE           = "TAP_INVALID_TAP_RATE";
    string private constant ERROR_INVALID_TAP_UPDATE         = "TAP_INVALID_TAP_UPDATE";
    string private constant ERROR_TOKEN_ALREADY_TAPPED       = "TAP_TOKEN_ALREADY_TAPPED";
    string private constant ERROR_TOKEN_NOT_TAPPED           = "TAP_TOKEN_NOT_TAPPED";
    string private constant ERROR_WITHDRAWAL_AMOUNT_ZERO     = "TAP_WITHDRAWAL_AMOUNT_ZERO";

    IAragonFundraisingController public controller;
    Vault                        public reserve;
    address                      public beneficiary;
    uint256                      public batchBlocks;
    uint256                      public maximumTapRateIncreasePct;
    uint256                      public maximumTapFloorDecreasePct;

    mapping (address => uint256) public rates;
    mapping (address => uint256) public floors;
    mapping (address => uint256) public lastWithdrawals; // batch ids [block numbers]
    mapping (address => uint256) public lastTapUpdates;  // timestamps

    event UpdateController                (address indexed controller);
    event UpdateReserve                   (address indexed reserve);
    event UpdateBeneficiary               (address indexed beneficiary);
    event UpdateMaximumTapRateIncreasePct (uint256 maximumTapRateIncreasePct);
    event UpdateMaximumTapFloorDecreasePct(uint256 maximumTapFloorDecreasePct);
    event AddTappedToken                  (address indexed token, uint256 rate, uint256 floor);
    event RemoveTappedToken               (address indexed token);
    event UpdateTappedToken               (address indexed token, uint256 rate, uint256 floor);
    event ResetTappedToken                (address indexed token);
    event Withdraw                        (address indexed token, uint256 amount);


    /***** external functions *****/

    /**
     * @notice Initialize tap
     * @param _controller                 The address of the controller contract
     * @param _reserve                    The address of the reserve [pool] contract
     * @param _beneficiary                The address of the beneficiary [to whom funds are to be withdrawn]
     * @param _batchBlocks                The number of blocks batches are to last
     * @param _maximumTapRateIncreasePct  The maximum tap rate increase percentage allowed [in PCT_BASE]
     * @param _maximumTapFloorDecreasePct The maximum tap floor decrease percentage allowed [in PCT_BASE]
    */
    function initialize(
        IAragonFundraisingController _controller,
        Vault                        _reserve,
        address                      _beneficiary,
        uint256                      _batchBlocks,
        uint256                      _maximumTapRateIncreasePct,
        uint256                      _maximumTapFloorDecreasePct
    )
        external
        onlyInit
    {
        require(isContract(_controller),                                         ERROR_CONTRACT_IS_EOA);
        require(isContract(_reserve),                                            ERROR_CONTRACT_IS_EOA);
        require(_beneficiaryIsValid(_beneficiary),                               ERROR_INVALID_BENEFICIARY);
        require(_batchBlocks != 0,                                               ERROR_INVALID_BATCH_BLOCKS);
        require(_maximumTapFloorDecreasePctIsValid(_maximumTapFloorDecreasePct), ERROR_INVALID_FLOOR_DECREASE_PCT);

        initialized();

        controller = _controller;
        reserve = _reserve;
        beneficiary = _beneficiary;
        batchBlocks = _batchBlocks;
        maximumTapRateIncreasePct = _maximumTapRateIncreasePct;
        maximumTapFloorDecreasePct = _maximumTapFloorDecreasePct;
    }

    /**
     * @notice Update controller to `_controller`
     * @param _controller The address of the new controller contract
    */
    function updateController(IAragonFundraisingController _controller) external auth(UPDATE_CONTROLLER_ROLE) {
        require(isContract(_controller), ERROR_CONTRACT_IS_EOA);

        _updateController(_controller);
    }

    /**
     * @notice Update reserve to `_reserve`
     * @param _reserve The address of the new reserve [pool] contract
    */
    function updateReserve(Vault _reserve) external auth(UPDATE_RESERVE_ROLE) {
        require(isContract(_reserve), ERROR_CONTRACT_IS_EOA);

        _updateReserve(_reserve);
    }

    /**
     * @notice Update beneficiary to `_beneficiary`
     * @param _beneficiary The address of the new beneficiary [to whom funds are to be withdrawn]
    */
    function updateBeneficiary(address _beneficiary) external auth(UPDATE_BENEFICIARY_ROLE) {
        require(_beneficiaryIsValid(_beneficiary), ERROR_INVALID_BENEFICIARY);

        _updateBeneficiary(_beneficiary);
    }

    /**
     * @notice Update maximum tap rate increase percentage to `@formatPct(_maximumTapRateIncreasePct)`%
     * @param _maximumTapRateIncreasePct The new maximum tap rate increase percentage to be allowed [in PCT_BASE]
    */
    function updateMaximumTapRateIncreasePct(uint256 _maximumTapRateIncreasePct) external auth(UPDATE_MAXIMUM_TAP_RATE_INCREASE_PCT_ROLE) {
        _updateMaximumTapRateIncreasePct(_maximumTapRateIncreasePct);
    }

    /**
     * @notice Update maximum tap floor decrease percentage to `@formatPct(_maximumTapFloorDecreasePct)`%
     * @param _maximumTapFloorDecreasePct The new maximum tap floor decrease percentage to be allowed [in PCT_BASE]
    */
    function updateMaximumTapFloorDecreasePct(uint256 _maximumTapFloorDecreasePct) external auth(UPDATE_MAXIMUM_TAP_FLOOR_DECREASE_PCT_ROLE) {
        require(_maximumTapFloorDecreasePctIsValid(_maximumTapFloorDecreasePct), ERROR_INVALID_FLOOR_DECREASE_PCT);

        _updateMaximumTapFloorDecreasePct(_maximumTapFloorDecreasePct);
    }

    /**
     * @notice Add tap for `_token.symbol(): string` with a rate of `@tokenAmount(_token, _rate)` per block and a floor of `@tokenAmount(_token, _floor)`
     * @param _token The address of the token to be tapped
     * @param _rate  The rate at which that token is to be tapped [in wei / block]
     * @param _floor The floor above which the reserve [pool] balance for that token is to be kept [in wei]
    */
    function addTappedToken(address _token, uint256 _rate, uint256 _floor) external auth(ADD_TAPPED_TOKEN_ROLE) {
        require(_tokenIsContractOrETH(_token), ERROR_INVALID_TOKEN);
        require(!_tokenIsTapped(_token),       ERROR_TOKEN_ALREADY_TAPPED);
        require(_tapRateIsValid(_rate),        ERROR_INVALID_TAP_RATE);

        _addTappedToken(_token, _rate, _floor);
    }

    /**
     * @notice Remove tap for `_token.symbol(): string`
     * @param _token The address of the token to be un-tapped
    */
    function removeTappedToken(address _token) external auth(REMOVE_TAPPED_TOKEN_ROLE) {
        require(_tokenIsTapped(_token), ERROR_TOKEN_NOT_TAPPED);

        _removeTappedToken(_token);
    }

    /**
     * @notice Update tap for `_token.symbol(): string` with a rate of `@tokenAmount(_token, _rate)` per block and a floor of `@tokenAmount(_token, _floor)`
     * @param _token The address of the token whose tap is to be updated
     * @param _rate  The new rate at which that token is to be tapped [in wei / block]
     * @param _floor The new floor above which the reserve [pool] balance for that token is to be kept [in wei]
    */
    function updateTappedToken(address _token, uint256 _rate, uint256 _floor) external auth(UPDATE_TAPPED_TOKEN_ROLE) {
        require(_tokenIsTapped(_token),                   ERROR_TOKEN_NOT_TAPPED);
        require(_tapRateIsValid(_rate),                   ERROR_INVALID_TAP_RATE);
        require(_tapUpdateIsValid(_token, _rate, _floor), ERROR_INVALID_TAP_UPDATE);

        _updateTappedToken(_token, _rate, _floor);
    }

    /**
     * @notice Reset tap timestamps for `_token.symbol(): string`
     * @param _token The address of the token whose tap timestamps are to be reset
    */
    function resetTappedToken(address _token) external auth(RESET_TAPPED_TOKEN_ROLE) {
        require(_tokenIsTapped(_token), ERROR_TOKEN_NOT_TAPPED);

        _resetTappedToken(_token);
    }

    /**
     * @notice Transfer about `@tokenAmount(_token, self.getMaximalWithdrawal(_token): uint256)` from `self.reserve()` to `self.beneficiary()`
     * @param _token The address of the token to be transfered
    */
    function withdraw(address _token) external auth(WITHDRAW_ROLE) {
        require(_tokenIsTapped(_token), ERROR_TOKEN_NOT_TAPPED);
        uint256 amount = _maximumWithdrawal(_token);
        require(amount > 0, ERROR_WITHDRAWAL_AMOUNT_ZERO);

        _withdraw(_token, amount);
    }

    /***** public view functions *****/

    function getMaximumWithdrawal(address _token) public view isInitialized returns (uint256) {
        return _maximumWithdrawal(_token);
    }

    /***** internal functions *****/

    /* computation functions */

    function _currentBatchId() internal view returns (uint256) {
        return (block.number.div(batchBlocks)).mul(batchBlocks);
    }

    function _maximumWithdrawal(address _token) internal view returns (uint256) {
        uint256 toBeClaimed = controller.collateralsToBeClaimed(_token);
        uint256 floor = floors[_token];
        uint256 minimum = toBeClaimed.add(floor);
        uint256 balance = _token == ETH ? address(reserve).balance : ERC20(_token).staticBalanceOf(reserve);
        uint256 tapped = (_currentBatchId().sub(lastWithdrawals[_token])).mul(rates[_token]);

        if (minimum >= balance) {
            return 0;
        }

        if (balance >= tapped.add(minimum)) {
            return tapped;
        }

        return balance.sub(minimum);
    }

    /* check functions */

    function _beneficiaryIsValid(address _beneficiary) internal pure returns (bool) {
        return _beneficiary != address(0);
    }

    function _maximumTapFloorDecreasePctIsValid(uint256 _maximumTapFloorDecreasePct) internal pure returns (bool) {
        return _maximumTapFloorDecreasePct <= PCT_BASE;
    }

    function _tokenIsContractOrETH(address _token) internal view returns (bool) {
        return isContract(_token) || _token == ETH;
    }

    function _tokenIsTapped(address _token) internal view returns (bool) {
        return rates[_token] != uint256(0);
    }

    function _tapRateIsValid(uint256 _rate) internal pure returns (bool) {
        return _rate != 0;
    }

    function _tapUpdateIsValid(address _token, uint256 _rate, uint256 _floor) internal view returns (bool) {
        return _tapRateUpdateIsValid(_token, _rate) && _tapFloorUpdateIsValid(_token, _floor);
    }

    function _tapRateUpdateIsValid(address _token, uint256 _rate) internal view returns (bool) {
        uint256 rate = rates[_token];

        if (_rate <= rate) {
            return true;
        }

        if (getTimestamp() < lastTapUpdates[_token] + 30 days) {
            return false;
        }

        if (_rate.mul(PCT_BASE) <= rate.mul(PCT_BASE.add(maximumTapRateIncreasePct))) {
            return true;
        }

        return false;
    }

    function _tapFloorUpdateIsValid(address _token, uint256 _floor) internal view returns (bool) {
        uint256 floor = floors[_token];

        if (_floor >= floor) {
            return true;
        }

        if (getTimestamp() < lastTapUpdates[_token] + 30 days) {
            return false;
        }

        if (maximumTapFloorDecreasePct >= PCT_BASE) {
            return true;
        }

        if (_floor.mul(PCT_BASE) >= floor.mul(PCT_BASE.sub(maximumTapFloorDecreasePct))) {
            return true;
        }

        return false;
    }

    /* state modifying functions */

    function _updateController(IAragonFundraisingController _controller) internal {
        controller = _controller;

        emit UpdateController(address(_controller));
    }

    function _updateReserve(Vault _reserve) internal {
        reserve = _reserve;

        emit UpdateReserve(address(_reserve));
    }

    function _updateBeneficiary(address _beneficiary) internal {
        beneficiary = _beneficiary;

        emit UpdateBeneficiary(_beneficiary);
    }

    function _updateMaximumTapRateIncreasePct(uint256 _maximumTapRateIncreasePct) internal {
        maximumTapRateIncreasePct = _maximumTapRateIncreasePct;

        emit UpdateMaximumTapRateIncreasePct(_maximumTapRateIncreasePct);
    }

    function _updateMaximumTapFloorDecreasePct(uint256 _maximumTapFloorDecreasePct) internal {
        maximumTapFloorDecreasePct = _maximumTapFloorDecreasePct;

        emit UpdateMaximumTapFloorDecreasePct(_maximumTapFloorDecreasePct);
    }

    function _addTappedToken(address _token, uint256 _rate, uint256 _floor) internal {
        /**
         * NOTE
         * 1. if _token is tapped in the middle of a batch it will
         * reach the next batch faster than what it normally takes
         * to go through a batch [e.g. one block later]
         * 2. this will allow for a higher withdrawal than expected
         * a few blocks after _token is tapped
         * 3. this is not a problem because this extra amount is
         * static [at most rates[_token] * batchBlocks] and does
         * not increase in time
        */
        rates[_token] = _rate;
        floors[_token] = _floor;
        lastWithdrawals[_token] = _currentBatchId();
        lastTapUpdates[_token] = getTimestamp();

        emit AddTappedToken(_token, _rate, _floor);
    }

    function _removeTappedToken(address _token) internal {
        delete rates[_token];
        delete floors[_token];
        delete lastWithdrawals[_token];
        delete lastTapUpdates[_token];

        emit RemoveTappedToken(_token);
    }

    function _updateTappedToken(address _token, uint256 _rate, uint256 _floor) internal {
        /**
         * NOTE
         * withdraw before updating to keep the reserve
         * actual balance [balance - virtual withdrawal]
         * continuous in time [though a floor update can
         * still break this continuity]
        */
        uint256 amount = _maximumWithdrawal(_token);
        if (amount > 0) {
            _withdraw(_token, amount);
        }

        rates[_token] = _rate;
        floors[_token] = _floor;
        lastTapUpdates[_token] = getTimestamp();

        emit UpdateTappedToken(_token, _rate, _floor);
    }

    function _resetTappedToken(address _token) internal {
        lastWithdrawals[_token] = _currentBatchId();
        lastTapUpdates[_token] = getTimestamp();

        emit ResetTappedToken(_token);
    }

    function _withdraw(address _token, uint256 _amount) internal {
        lastWithdrawals[_token] = _currentBatchId();
        reserve.transfer(_token, beneficiary, _amount); // vault contract's transfer method already reverts on error

        emit Withdraw(_token, _amount);
    }
}