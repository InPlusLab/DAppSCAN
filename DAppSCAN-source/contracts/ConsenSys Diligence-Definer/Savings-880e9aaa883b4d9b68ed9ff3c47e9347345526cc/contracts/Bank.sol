pragma solidity 0.5.14;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./config/Constant.sol";
import "./config/GlobalConfig.sol";
import { ICToken } from "./compound/ICompound.sol";
import { ICETH } from "./compound/ICompound.sol";
import "@openzeppelin/upgrades/contracts/Initializable.sol";
// import "@nomiclabs/buidler/console.sol";

contract Bank is Constant, Initializable{
    using SafeMath for uint256;

    mapping(address => uint256) public totalLoans;     // amount of lended tokens
    mapping(address => uint256) public totalReserve;   // amount of tokens in reservation
    mapping(address => uint256) public totalCompound;  // amount of tokens in compound
    // Token => block-num => rate
    mapping(address => mapping(uint => uint)) public depositeRateIndex; // the index curve of deposit rate
    // Token => block-num => rate
    mapping(address => mapping(uint => uint)) public borrowRateIndex;   // the index curve of borrow rate
    // token address => block number
    mapping(address => uint) public lastCheckpoint;            // last checkpoint on the index curve
    // cToken address => rate
    mapping(address => uint) public lastCTokenExchangeRate;    // last compound cToken exchange rate
    mapping(address => ThirdPartyPool) compoundPool;    // the compound pool

    GlobalConfig globalConfig;            // global configuration contract address

    mapping(address => mapping(uint => uint)) public depositFINRateIndex;
    mapping(address => mapping(uint => uint)) public borrowFINRateIndex;
    mapping(address => uint) public lastDepositeFINRateCheckpoint;
    mapping(address => uint) public lastBorrowFINRateCheckpoint;

    modifier onlyAuthorized() {
        require(msg.sender == address(globalConfig.savingAccount()) || msg.sender == address(globalConfig.accounts()),
            "Only authorized to call from DeFiner internal contracts.");
        _;
    }

    struct ThirdPartyPool {
        bool supported;             // if the token is supported by the third party platforms such as Compound
        uint capitalRatio;          // the ratio of the capital in third party to the total asset
        uint depositRatePerBlock;   // the deposit rate of the token in third party
        uint borrowRatePerBlock;    // the borrow rate of the token in third party
    }

    event UpdateIndex(address indexed token, uint256 depositeRateIndex, uint256 borrowRateIndex);
    event UpdateDepositFINIndex(address indexed _token, uint256 depositFINRateIndex);
    event UpdateBorrowFINIndex(address indexed _token, uint256 borrowFINRateIndex);

    /**
     * Initialize the Bank
     * @param _globalConfig the global configuration contract
     */
    function initialize(
        GlobalConfig _globalConfig
    ) public initializer {
        globalConfig = _globalConfig;
    }

    /**
     * Total amount of the token in Saving account
     * @param _token token address
     */
    function getTotalDepositStore(address _token) public view returns(uint) {
        address cToken = globalConfig.tokenInfoRegistry().getCToken(_token);
        // totalLoans[_token] = U   totalReserve[_token] = R
        return totalCompound[cToken].add(totalLoans[_token]).add(totalReserve[_token]); // return totalAmount = C + U + R
    }

    /**
     * Update total amount of token in Compound as the cToken price changed
     * @param _token token address
     */
    function updateTotalCompound(address _token) internal {
        address cToken = globalConfig.tokenInfoRegistry().getCToken(_token);
        if(cToken != address(0)) {
            totalCompound[cToken] = ICToken(cToken).balanceOfUnderlying(address(globalConfig.savingAccount()));
        }
    }

    /**
     * Update the total reservation. Before run this function, make sure that totalCompound has been updated
     * by calling updateTotalCompound. Otherwise, totalCompound may not equal to the exact amount of the
     * token in Compound.
     * @param _token token address
     * @param _action indicate if user's operation is deposit or withdraw, and borrow or repay.
     * @return the actuall amount deposit/withdraw from the saving pool
     */
    function updateTotalReserve(address _token, uint _amount, ActionType _action) internal returns(uint256 compoundAmount){
        address cToken = globalConfig.tokenInfoRegistry().getCToken(_token);
        uint totalAmount = getTotalDepositStore(_token);
        if (_action == ActionType.DepositAction || _action == ActionType.RepayAction) {
            // Total amount of token after deposit or repay
            if (_action == ActionType.DepositAction)
                totalAmount = totalAmount.add(_amount);
            else
                totalLoans[_token] = totalLoans[_token].sub(_amount);

            // Expected total amount of token in reservation after deposit or repay
            uint totalReserveBeforeAdjust = totalReserve[_token].add(_amount);

            if (cToken != address(0) &&
            totalReserveBeforeAdjust > totalAmount.mul(globalConfig.maxReserveRatio()).div(100)) {
                uint toCompoundAmount = totalReserveBeforeAdjust.sub(totalAmount.mul(globalConfig.midReserveRatio()).div(100));
                //toCompound(_token, toCompoundAmount);
                compoundAmount = toCompoundAmount;
                totalCompound[cToken] = totalCompound[cToken].add(toCompoundAmount);
                totalReserve[_token] = totalReserve[_token].add(_amount).sub(toCompoundAmount);
            }
            else {
                totalReserve[_token] = totalReserve[_token].add(_amount);
            }
        } else {
            // The lack of liquidity exception happens when the pool doesn't have enough tokens for borrow/withdraw
            // It happens when part of the token has lended to the other accounts.
            // However in case of withdrawAll, even if the token has no loan, this requirment may still false because
            // of the precision loss in the rate calcuation. So we put a logic here to deal with this case: in case
            // of withdrawAll and there is no loans for the token, we just adjust the balance in bank contract to the
            // to the balance of that individual account.
            if(_action == ActionType.WithdrawAction) {
                if(totalLoans[_token] != 0)
                    require(getPoolAmount(_token) >= _amount, "Lack of liquidity when withdraw.");
                else if (getPoolAmount(_token) < _amount)
                    totalReserve[_token] = _amount.sub(totalCompound[cToken]);
                totalAmount = getTotalDepositStore(_token);
            }
            else
                require(getPoolAmount(_token) >= _amount, "Lack of liquidity when borrow.");

            // Total amount of token after withdraw or borrow
            if (_action == ActionType.WithdrawAction)
                totalAmount = totalAmount.sub(_amount);
            else
                totalLoans[_token] = totalLoans[_token].add(_amount);

            // Expected total amount of token in reservation after deposit or repay
            uint totalReserveBeforeAdjust = totalReserve[_token] > _amount ? totalReserve[_token].sub(_amount) : 0;

            // Trigger fromCompound if the new reservation ratio is less than 10%
            if(cToken != address(0) &&
            (totalAmount == 0 || totalReserveBeforeAdjust < totalAmount.mul(globalConfig.minReserveRatio()).div(100))) {

                uint totalAvailable = totalReserve[_token].add(totalCompound[cToken]).sub(_amount);
                if (totalAvailable < totalAmount.mul(globalConfig.midReserveRatio()).div(100)){
                    // Withdraw all the tokens from Compound
                    compoundAmount = totalCompound[cToken];
                    totalCompound[cToken] = 0;
                    totalReserve[_token] = totalAvailable;
                } else {
                    // Withdraw partial tokens from Compound
                    uint totalInCompound = totalAvailable.sub(totalAmount.mul(globalConfig.midReserveRatio()).div(100));
                    compoundAmount = totalCompound[cToken].sub(totalInCompound);
                    totalCompound[cToken] = totalInCompound;
                    totalReserve[_token] = totalAvailable.sub(totalInCompound);
                }
            }
            else {
                totalReserve[_token] = totalReserve[_token].sub(_amount);
            }
        }
        return compoundAmount;
    }

     function update(address _token, uint _amount, ActionType _action) public onlyAuthorized returns(uint256 compoundAmount) {
        updateTotalCompound(_token);
        // updateTotalLoan(_token);
        compoundAmount = updateTotalReserve(_token, _amount, _action);
        return compoundAmount;
    }

    function updateDepositFINIndex(address _token) public onlyAuthorized{
        uint currentBlock = getBlockNumber();
        uint deltaBlock;
        // sichaoy: newRateIndexCheckpoint should never be called before this line, so the total deposit
        // derived here is the total deposit in the last checkpoint without latest interests.
        deltaBlock = lastDepositeFINRateCheckpoint[_token] == 0 ? 0 : currentBlock.sub(lastDepositeFINRateCheckpoint[_token]);
        // sichaoy: How to deal with the case that totalDeposit = 0?
        depositFINRateIndex[_token][currentBlock] = getTotalDepositStore(_token) == 0 ?
            0 : depositFINRateIndex[_token][lastDepositeFINRateCheckpoint[_token]]
                .add(depositeRateIndex[_token][lastCheckpoint[_token]]
                    .mul(deltaBlock)
                    .mul(globalConfig.tokenInfoRegistry().depositeMiningSpeeds(_token))
                    .div(getTotalDepositStore(_token))
                );
        lastDepositeFINRateCheckpoint[_token] = currentBlock;

        emit UpdateDepositFINIndex(_token, depositFINRateIndex[_token][currentBlock]);
    }

    function updateBorrowFINIndex(address _token) public onlyAuthorized{
        uint currentBlock = getBlockNumber();
        uint deltaBlock;
        deltaBlock = lastBorrowFINRateCheckpoint[_token] == 0 ? 0 : currentBlock.sub(lastBorrowFINRateCheckpoint[_token]);
        borrowFINRateIndex[_token][currentBlock] = totalLoans[_token] == 0 ?
            0 : borrowFINRateIndex[_token][lastBorrowFINRateCheckpoint[_token]]
                .add(depositeRateIndex[_token][lastCheckpoint[_token]]
                    .mul(deltaBlock)
                    .mul(globalConfig.tokenInfoRegistry().borrowMiningSpeeds(_token))
                    .div(totalLoans[_token]));
        lastBorrowFINRateCheckpoint[_token] = currentBlock;

        emit UpdateBorrowFINIndex(_token, borrowFINRateIndex[_token][currentBlock]);
    }

    function updateMining(address _token) public onlyAuthorized{
        newRateIndexCheckpoint(_token);
        updateTotalCompound(_token);
    }

    /**
     * Get the borrowing interest rate Borrowing interest rate.
     * @param _token token address
     * @return the borrow rate for the current block
     */
    function getBorrowRatePerBlock(address _token) public view returns(uint) {
        if(!globalConfig.tokenInfoRegistry().isSupportedOnCompound(_token))
        // If the token is NOT supported by the third party, borrowing rate = 3% + U * 15%.
            return getCapitalUtilizationRatio(_token).mul(globalConfig.rateCurveSlope()).div(INT_UNIT).add(globalConfig.rateCurveConstant()).div(BLOCKS_PER_YEAR);

        // if the token is suppored in third party, borrowing rate = Compound Supply Rate * 0.4 + Compound Borrow Rate * 0.6
        return (compoundPool[_token].depositRatePerBlock).mul(globalConfig.compoundSupplyRateWeights()).
            add((compoundPool[_token].borrowRatePerBlock).mul(globalConfig.compoundBorrowRateWeights())).div(10);
    }

    /**
    * Get Deposit Rate.  Deposit APR = (Borrow APR * Utilization Rate (U) +  Compound Supply Rate *
    * Capital Compound Ratio (C) )* (1- DeFiner Community Fund Ratio (D)). The scaling is 10 ** 18
    * sichaoy: make sure the ratePerBlock is zero if both U and C are zero.
    * @param _token token address
    * @return deposite rate of blocks before the current block
    */
    function getDepositRatePerBlock(address _token) public view returns(uint) {
        uint256 borrowRatePerBlock = getBorrowRatePerBlock(_token);
        uint256 capitalUtilRatio = getCapitalUtilizationRatio(_token);
        if(!globalConfig.tokenInfoRegistry().isSupportedOnCompound(_token))
            return borrowRatePerBlock.mul(capitalUtilRatio).div(INT_UNIT);

        return borrowRatePerBlock.mul(capitalUtilRatio).add(compoundPool[_token].depositRatePerBlock
            .mul(compoundPool[_token].capitalRatio)).div(INT_UNIT);
    }

    /**
     * Get capital utilization. Capital Utilization Rate (U )= total loan outstanding / Total market deposit
     * @param _token token address
     */
    function getCapitalUtilizationRatio(address _token) public view returns(uint) {
        uint256 totalDepositsNow = getTotalDepositStore(_token);
        if(totalDepositsNow == 0) {
            return 0;
        } else {
            return totalLoans[_token].mul(INT_UNIT).div(totalDepositsNow);
        }
    }

    /**
     * Ratio of the capital in Compound
     * @param _token token address
     */
    function getCapitalCompoundRatio(address _token) public view returns(uint) {
        address cToken = globalConfig.tokenInfoRegistry().getCToken(_token);
        if(totalCompound[cToken] == 0 ) {
            return 0;
        } else {
            return uint(totalCompound[cToken].mul(INT_UNIT).div(getTotalDepositStore(_token)));
        }
    }

    /**
     * It's a utility function. Get the cummulative deposit rate in a block interval ending in current block
     * @param _token token address
     * @param _depositRateRecordStart the start block of the interval
     * @dev This function should always be called after current block is set as a new rateIndex point.
     */
    // sichaoy: this function could be more general to have an end checkpoit as a parameter.
    // sichaoy: require:what if a index point doesn't exist?
    function getDepositAccruedRate(address _token, uint _depositRateRecordStart) external view returns (uint256) {
        uint256 depositRate = depositeRateIndex[_token][_depositRateRecordStart];
        require(depositRate != 0, "_depositRateRecordStart is not a check point on index curve.");
        return depositRateIndexNow(_token).mul(INT_UNIT).div(depositRate);
    }

    /**
     * Get the cummulative borrow rate in a block interval ending in current block
     * @param _token token address
     * @param _borrowRateRecordStart the start block of the interval
     * @dev This function should always be called after current block is set as a new rateIndex point.
     */
    // sichaoy: actually the rate + 1, add a require statement here to make sure
    // the checkpoint for current block exists.
    function getBorrowAccruedRate(address _token, uint _borrowRateRecordStart) external view returns (uint256) {
        uint256 borrowRate = borrowRateIndex[_token][_borrowRateRecordStart];
        require(borrowRate != 0, "_borrowRateRecordStart is not a check point on index curve.");
        return borrowRateIndexNow(_token).mul(INT_UNIT).div(borrowRate);
    }

    /**
     * Set a new rate index checkpoint.
     * @param _token token address
     * @dev The rate set at the checkpoint is the rate from the last checkpoint to this checkpoint
     */
    function newRateIndexCheckpoint(address _token) public onlyAuthorized {

        // return if the rate check point already exists
        uint blockNumber = getBlockNumber();
        if (blockNumber == lastCheckpoint[_token])
            return;

        uint256 UNIT = INT_UNIT;
        address cToken = globalConfig.tokenInfoRegistry().getCToken(_token);

        // If it is the first check point, initialize the rate index
        uint256 previousCheckpoint = lastCheckpoint[_token];
        if (lastCheckpoint[_token] == 0) {
            if(cToken == address(0)) {
                compoundPool[_token].supported = false;
                borrowRateIndex[_token][blockNumber] = UNIT;
                depositeRateIndex[_token][blockNumber] = UNIT;
                // Update the last checkpoint
                lastCheckpoint[_token] = blockNumber;
            }
            else {
                compoundPool[_token].supported = true;
                uint cTokenExchangeRate = ICToken(cToken).exchangeRateCurrent();
                // Get the curretn cToken exchange rate in Compound, which is need to calculate DeFiner's rate
                // sichaoy: How to deal with the issue capitalRatio is zero if looking forward (An estimation)
                compoundPool[_token].capitalRatio = getCapitalCompoundRatio(_token);
                compoundPool[_token].borrowRatePerBlock = ICToken(cToken).borrowRatePerBlock();  // initial value
                compoundPool[_token].depositRatePerBlock = ICToken(cToken).supplyRatePerBlock(); // initial value
                borrowRateIndex[_token][blockNumber] = UNIT;
                depositeRateIndex[_token][blockNumber] = UNIT;
                // Update the last checkpoint
                lastCheckpoint[_token] = blockNumber;
                lastCTokenExchangeRate[cToken] = cTokenExchangeRate;
            }

        } else {
            if(cToken == address(0)) {
                compoundPool[_token].supported = false;
                borrowRateIndex[_token][blockNumber] = borrowRateIndexNow(_token);
                depositeRateIndex[_token][blockNumber] = depositRateIndexNow(_token);
                // Update the last checkpoint
                lastCheckpoint[_token] = blockNumber;
            } else {
                compoundPool[_token].supported = true;
                uint cTokenExchangeRate = ICToken(cToken).exchangeRateCurrent();
                // Get the curretn cToken exchange rate in Compound, which is need to calculate DeFiner's rate
                compoundPool[_token].capitalRatio = getCapitalCompoundRatio(_token);
                compoundPool[_token].borrowRatePerBlock = ICToken(cToken).borrowRatePerBlock();
                compoundPool[_token].depositRatePerBlock = cTokenExchangeRate.mul(UNIT).div(lastCTokenExchangeRate[cToken])
                    .sub(UNIT).div(blockNumber.sub(lastCheckpoint[_token]));
                borrowRateIndex[_token][blockNumber] = borrowRateIndexNow(_token);
                depositeRateIndex[_token][blockNumber] = depositRateIndexNow(_token);
                // Update the last checkpoint
                lastCheckpoint[_token] = blockNumber;
                lastCTokenExchangeRate[cToken] = cTokenExchangeRate;
            }
        }

        // Update the total loan
        if(borrowRateIndex[_token][blockNumber] != UNIT) {
            totalLoans[_token] = totalLoans[_token].mul(borrowRateIndex[_token][blockNumber])
                .div(borrowRateIndex[_token][previousCheckpoint]);
        }

        emit UpdateIndex(_token, depositeRateIndex[_token][getBlockNumber()], borrowRateIndex[_token][getBlockNumber()]);
    }

    /**
     * Calculate a token deposite rate of current block
     * @param _token token address
     * @dev This is an looking forward estimation from last checkpoint and not the exactly rate that the user will pay or earn.
     * sichaoy: to make the notation consistent, change the name from depositRateIndexNow to depositRateIndexCurrent
     */
    function depositRateIndexNow(address _token) public view returns(uint) {
        uint256 lcp = lastCheckpoint[_token];
        // If this is the first checkpoint, set the index be 1.
        if(lcp == 0)
            return INT_UNIT;

        uint256 lastDepositeRateIndex = depositeRateIndex[_token][lcp];
        uint256 depositRatePerBlock = getDepositRatePerBlock(_token);
        // newIndex = oldIndex*(1+r*delta_block). If delta_block = 0, i.e. the last checkpoint is current block, index doesn't change.
        return lastDepositeRateIndex.mul(getBlockNumber().sub(lcp).mul(depositRatePerBlock).add(INT_UNIT)).div(INT_UNIT);
    }

    /**
     * Calculate a token borrow rate of current block
     * @param _token token address
     */
    function borrowRateIndexNow(address _token) public view returns(uint) {
        uint256 lcp = lastCheckpoint[_token];
        // If this is the first checkpoint, set the index be 1.
        if(lcp == 0)
            return INT_UNIT;
        uint256 lastBorrowRateIndex = borrowRateIndex[_token][lcp];
        uint256 borrowRatePerBlock = getBorrowRatePerBlock(_token);
        return lastBorrowRateIndex.mul(getBlockNumber().sub(lcp).mul(borrowRatePerBlock).add(INT_UNIT)).div(INT_UNIT);
    }

    /**
	 * Get the state of the given token
     * @param _token token address
	 */
    function getTokenState(address _token) public view returns (uint256 deposits, uint256 loans, uint256 reserveBalance, uint256 remainingAssets){
        return (
        getTotalDepositStore(_token),
        totalLoans[_token],
        totalReserve[_token],
        totalReserve[_token].add(totalCompound[globalConfig.tokenInfoRegistry().getCToken(_token)])
        );
    }

    function getPoolAmount(address _token) public view returns(uint) {
        return totalReserve[_token].add(totalCompound[globalConfig.tokenInfoRegistry().getCToken(_token)]);
    }

 // sichaoy: should not be public, why cannot we find _tokenIndex from token address?
    function deposit(address _to, address _token, uint256 _amount) external onlyAuthorized {

        require(_amount != 0, "Amount is zero");

        // Add a new checkpoint on the index curve.
        newRateIndexCheckpoint(_token);
        updateDepositFINIndex(_token);

        // Update tokenInfo. Add the _amount to principal, and update the last deposit block in tokenInfo
        globalConfig.accounts().deposit(_to, _token, _amount);

        // Update the amount of tokens in compound and loans, i.e. derive the new values
        // of C (Compound Ratio) and U (Utilization Ratio).
        uint compoundAmount = update(_token, _amount, ActionType.DepositAction);

        if(compoundAmount > 0) {
            globalConfig.savingAccount().toCompound(_token, compoundAmount);
        }
    }

    function borrow(address _from, address _token, uint256 _amount) external onlyAuthorized {

        // Add a new checkpoint on the index curve.
        newRateIndexCheckpoint(_token);
        updateBorrowFINIndex(_token);

        // Update tokenInfo for the user
        globalConfig.accounts().borrow(_from, _token, _amount);

        // Update pool balance
        // Update the amount of tokens in compound and loans, i.e. derive the new values
        // of C (Compound Ratio) and U (Utilization Ratio).
        uint compoundAmount = update(_token, _amount, ActionType.BorrowAction);

        if(compoundAmount > 0) {
            globalConfig.savingAccount().fromCompound(_token, compoundAmount);
        }
    }

    function repay(address _to, address _token, uint256 _amount) external onlyAuthorized returns(uint) {

        // Add a new checkpoint on the index curve.
        newRateIndexCheckpoint(_token);
        updateBorrowFINIndex(_token);

        // Sanity check
        require(globalConfig.accounts().getBorrowPrincipal(_to, _token) > 0,
            "Token BorrowPrincipal must be greater than 0. To deposit balance, please use deposit button."
        );

        // Update tokenInfo
        uint256 remain = globalConfig.accounts().repay(_to, _token, _amount);

        // Update the amount of tokens in compound and loans, i.e. derive the new values
        // of C (Compound Ratio) and U (Utilization Ratio).
        uint compoundAmount = update(_token, _amount.sub(remain), ActionType.RepayAction);
        if(compoundAmount > 0) {
           globalConfig.savingAccount().toCompound(_token, compoundAmount);
        }

        // Return actual amount repaid
        return _amount.sub(remain);
    }

    /**
     * Withdraw a token from an address
     * @param _from address to be withdrawn from
     * @param _token token address
     * @param _amount amount to be withdrawn
     * @return The actually amount withdrawed, which will be the amount requested minus the commission fee.
     */
    function withdraw(address _from, address _token, uint256 _amount) external onlyAuthorized returns(uint) {

        require(_amount != 0, "Amount is zero");

        // Add a new checkpoint on the index curve.
        newRateIndexCheckpoint(_token);
        updateDepositFINIndex(_token);

        // Withdraw from the account
        uint amount = globalConfig.accounts().withdraw(_from, _token, _amount);

        // Update pool balance
        // Update the amount of tokens in compound and loans, i.e. derive the new values
        // of C (Compound Ratio) and U (Utilization Ratio).
        uint compoundAmount = update(_token, amount, ActionType.WithdrawAction);

        // Check if there are enough tokens in the pool.
        if(compoundAmount > 0) {
            globalConfig.savingAccount().fromCompound(_token, compoundAmount);
        }

        return amount;
    }

    /**
     * Get current block number
     * @return the current block number
     */
    function getBlockNumber() private view returns (uint) {
        return block.number;
    }
}
