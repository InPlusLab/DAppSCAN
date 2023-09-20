// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "../interfaces/IOracleMaster.sol";
import "../interfaces/ILido.sol";
import "../interfaces/IRelayEncoder.sol";
import "../interfaces/IXcmTransactor.sol";
import "../interfaces/IController.sol";
import "../interfaces/Types.sol";

import "./utils/LedgerUtils.sol";
import "./utils/ReportUtils.sol";



contract Ledger {
    using LedgerUtils for Types.OracleData;
    using SafeCast for uint256;

    event DownwardComplete(uint128 amount);
    event UpwardComplete(uint128 amount);
    event Rewards(uint128 amount, uint128 balance);
    event Slash(uint128 amount, uint128 balance);

    // ledger stash account
    bytes32 public stashAccount;

    // ledger controller account
    bytes32 public controllerAccount;

    // Stash balance that includes locked (bounded in stake) and free to transfer balance
    uint128 public totalBalance;

    // Locked, or bonded in stake module, balance
    uint128 public lockedBalance;

    // last reported active ledger balance
    uint128 public activeBalance;

    // last reported ledger status
    Types.LedgerStatus public status;

    // Cached stash balance. Need to calculate rewards between successfull up/down transfers
    uint128 public cachedTotalBalance;

    // Pending transfers
    uint128 public transferUpwardBalance;
    uint128 public transferDownwardBalance;


    // vKSM precompile
    IERC20 internal vKSM;

    IController internal controller;

    // Lido main contract address
    ILido public LIDO;

    // Minimal allowed balance to being a nominator
    uint128 public MIN_NOMINATOR_BALANCE;


    // Who pay off relay chain transaction fees
    bytes32 internal constant GARANTOR = 0x00;


    modifier onlyLido() {
        require(msg.sender == address(LIDO), "LEDGED: NOT_LIDO");
        _;
    }

    modifier onlyOracle() {
        address oracle = IOracleMaster(ILido(LIDO).ORACLE_MASTER()).getOracle(address(this));
        require(msg.sender == oracle, "LEDGED: NOT_ORACLE");
        _;
    }

    /**
    * @notice Initialize ledger contract.
    * @param _stashAccount - stash account id
    * @param _controllerAccount - controller account id
    * @param _vKSM - vKSM contract address
    * @param _controller - xcmTransactor(relaychain calls relayer) contract address
    * @param _minNominatorBalance - minimal allowed nominator balance
    */
    function initialize(
        bytes32 _stashAccount,
        bytes32 _controllerAccount,
        address _vKSM,
        address _controller,
        uint128 _minNominatorBalance
    ) external {
        require(address(vKSM) == address(0), "LEDGED: ALREADY_INITIALIZED");

        // The owner of the funds
        stashAccount = _stashAccount;
        // The account which handles bounded part of stash funds (unbond, rebond, withdraw, nominate)
        controllerAccount = _controllerAccount;

        status = Types.LedgerStatus.None;

        LIDO = ILido(msg.sender);

        vKSM = IERC20(_vKSM);

        controller = IController(_controller);

        MIN_NOMINATOR_BALANCE = _minNominatorBalance;

//        vKSM.approve(_controller, type(uint256).max);
    }

    /**
    * @notice Set new minimal allowed nominator balance, allowed to call only by lido contract
    * @dev That method designed to be called by lido contract when relay spec is changed
    * @param _minNominatorBalance - minimal allowed nominator balance
    */
    function setMinNominatorBalance(uint128 _minNominatorBalance) external onlyLido {
        MIN_NOMINATOR_BALANCE = _minNominatorBalance;
    }

    function refreshAllowances() external {
        vKSM.approve(address(controller), type(uint256).max);
    }

    /**
    * @notice Return target stake amount for this ledger
    * @return target stake amount
    */
    function ledgerStake() public view returns (uint256) {
        return LIDO.ledgerStake(address(this));
    }

    /**
    * @notice Return true if ledger doesn't have any funds
    */
    function isEmpty() external view returns (bool) {
        return totalBalance == 0 && transferUpwardBalance == 0 && transferDownwardBalance == 0;
    }

    /**
    * @notice Nominate on behalf of this ledger, allowed to call only by lido contract
    * @dev Method spawns xcm call to relaychain.
    * @param _validators - array of choosen validator to be nominated
    */
    function nominate(bytes32[] calldata _validators) external onlyLido {
        require(activeBalance >= MIN_NOMINATOR_BALANCE, "LEDGED: NOT_ENOUGH_STAKE");
        controller.nominate(_validators);
    }

    /**
    * @notice Provide portion of relaychain data about current ledger, allowed to call only by oracle contract
    * @dev Basically, ledger can obtain data from any source, but for now it allowed to recieve only from oracle.
           Method perform calculation of current state based on report data and saved state and expose
           required instructions(relaychain pallet calls) via xcm to adjust bonded amount to required target stake.
    * @param _eraId - reporting era id
    * @param _report - data that represent state of ledger on relaychain for `_eraId`
    */
    function pushData(uint64 _eraId, Types.OracleData memory _report) external onlyOracle {
        require(stashAccount == _report.stashAccount, "LEDGED: STASH_ACCOUNT_MISMATCH");

        status = _report.stakeStatus;
        activeBalance = _report.activeBalance;

        (uint128 unlockingBalance, uint128 withdrawableBalance) = _report.getTotalUnlocking(_eraId);
        uint128 nonWithdrawableBalance = unlockingBalance - withdrawableBalance;

        if (!_processRelayTransfers(_report)) {
            return;
        }
        uint128 _cachedTotalBalance = cachedTotalBalance;
        if (_cachedTotalBalance < _report.stashBalance) { // if cached balance > real => we have reward
            uint128 reward = _report.stashBalance - _cachedTotalBalance;
            LIDO.distributeRewards(reward, _report.stashBalance);

            emit Rewards(reward, _report.stashBalance);
        }
        else if (_cachedTotalBalance > _report.stashBalance) {
            uint128 slash = _cachedTotalBalance - _report.stashBalance;
            LIDO.distributeLosses(slash, _report.stashBalance);

            emit Slash(slash, _report.stashBalance);
        }

        uint128 _ledgerStake = ledgerStake().toUint128();

        // relay deficit or bonding
        if (_report.stashBalance <= _ledgerStake) {
            //    Staking strategy:
            //     - upward transfer deficit tokens
            //     - rebond all unlocking tokens
            //     - bond_extra all free balance

            uint128 deficit = _ledgerStake - _report.stashBalance;

            // just upward transfer if we have deficit
            if (deficit > 0) {
                uint128 lidoBalance = uint128(LIDO.avaliableForStake());
                uint128 forTransfer = lidoBalance > deficit ? deficit : lidoBalance;

                if (forTransfer > 0) {
                    vKSM.transferFrom(address(LIDO), address(this), forTransfer);
                    controller.transferToRelaychain(forTransfer);
                    transferUpwardBalance += forTransfer;
                }
            }

            // rebond all always
            if (unlockingBalance > 0) {
                controller.rebond(unlockingBalance);
            }

            uint128 relayFreeBalance = _report.getFreeBalance();

            if (relayFreeBalance > 0 &&
                (_report.stakeStatus == Types.LedgerStatus.Nominator || _report.stakeStatus == Types.LedgerStatus.Idle)) {
                controller.bondExtra(relayFreeBalance);
            } else if (_report.stakeStatus == Types.LedgerStatus.None && relayFreeBalance >= MIN_NOMINATOR_BALANCE) {
                controller.bond(controllerAccount, relayFreeBalance);
            }

        }
        else if (_report.stashBalance > _ledgerStake) { // parachain deficit
            //    Unstaking strategy:
            //     - try to downward transfer already free balance
            //     - if we still have deficit try to withdraw already unlocked tokens
            //     - if we still have deficit initiate unbond for remain deficit

            // if ledger is in the deadpool we need to put it to chill
            if (_ledgerStake < MIN_NOMINATOR_BALANCE && status != Types.LedgerStatus.Idle) {
                controller.chill();
            }

            uint128 deficit = _report.stashBalance - _ledgerStake;
            uint128 relayFreeBalance = _report.getFreeBalance();

            // need to downward transfer if we have some free
            if (relayFreeBalance > 0) {
                uint128 forTransfer = relayFreeBalance > deficit ? deficit : relayFreeBalance;
                controller.transferToParachain(forTransfer);
                transferDownwardBalance += forTransfer;
                deficit -= forTransfer;
                relayFreeBalance -= forTransfer;
            }

            // withdraw if we have some unlocked
            if (deficit > 0 && withdrawableBalance > 0) {
                controller.withdrawUnbonded();
                deficit -= withdrawableBalance > deficit ? deficit : withdrawableBalance;
            }

            // need to unbond if we still have deficit
            if (nonWithdrawableBalance < deficit) {
                // todo drain stake if remaining balance is less than MIN_NOMINATOR_BALANCE
                uint128 forUnbond = deficit - nonWithdrawableBalance;
                controller.unbond(forUnbond);
                // notice.
                // deficit -= forUnbond;
            }

            // bond all remain free balance
            if (relayFreeBalance > 0) {
                controller.bondExtra(relayFreeBalance);
            }
        }

        cachedTotalBalance = _report.stashBalance;
    }

    function _processRelayTransfers(Types.OracleData memory _report) internal returns(bool) {
        // wait for the downward transfer to complete
        uint128 _transferDownwardBalance = transferDownwardBalance;
        if (_transferDownwardBalance > 0) {
            uint128 totalDownwardTransferred = uint128(vKSM.balanceOf(address(this)));

            if (totalDownwardTransferred >= _transferDownwardBalance ) {
                // take transferred funds into buffered balance
                vKSM.transfer(address(LIDO), _transferDownwardBalance);

                // Clear transfer flag
                cachedTotalBalance -= _transferDownwardBalance;
                transferDownwardBalance = 0;

                emit DownwardComplete(_transferDownwardBalance);
                _transferDownwardBalance = 0;
            }
        }

        // wait for the upward transfer to complete
        uint128 _transferUpwardBalance = transferUpwardBalance;
        if (_transferUpwardBalance > 0) {
            uint128 ledgerFreeBalance = (totalBalance - lockedBalance);
            // SWC-101-Integer Overflow and Underflow: L298
            uint128 freeBalanceIncrement = _report.getFreeBalance() - ledgerFreeBalance;

            if (freeBalanceIncrement >= _transferUpwardBalance) {
                cachedTotalBalance += _transferUpwardBalance;

                transferUpwardBalance = 0;
                emit UpwardComplete(_transferUpwardBalance);
                _transferUpwardBalance = 0;
            }
        }

        if (_transferDownwardBalance == 0 && _transferUpwardBalance == 0) {
            // update ledger data from oracle report
            totalBalance = _report.stashBalance;
            lockedBalance = _report.totalBalance;
            return true;
        }

        return false;
    }
}
