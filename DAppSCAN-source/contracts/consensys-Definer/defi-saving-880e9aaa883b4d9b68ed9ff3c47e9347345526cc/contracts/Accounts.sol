pragma solidity 0.5.14;

import "./lib/AccountTokenLib.sol";
import "./lib/BitmapLib.sol";
import "./lib/Utils.sol";
import "./config/Constant.sol";
import "./config/GlobalConfig.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "@openzeppelin/upgrades/contracts/Initializable.sol";
import "@nomiclabs/buidler/console.sol";

contract Accounts is Constant, Initializable{
    using AccountTokenLib for AccountTokenLib.TokenInfo;
    using BitmapLib for uint128;
    using SafeMath for uint256;

    mapping(address => Account) public accounts;
    GlobalConfig globalConfig;
    mapping(address => uint) public FINAmount;

    modifier onlyAuthorized() {
        require(msg.sender == address(globalConfig.savingAccount()) || msg.sender == address(globalConfig.bank()),
            "Only authorized to call from DeFiner internal contracts.");
        _;
    }

    struct Account {
        // Note, it's best practice to use functions minusAmount, addAmount, totalAmount
        // to operate tokenInfos instead of changing it directly.
        mapping(address => AccountTokenLib.TokenInfo) tokenInfos;
        uint128 depositBitmap;
        uint128 borrowBitmap;
    }

    /**
     * Initialize the Accounts
     * @param _globalConfig the global configuration contract
     */
    function initialize(
        GlobalConfig _globalConfig
    ) public initializer {
        globalConfig = _globalConfig;
    }

    /**
     * Check if the user has deposit for any tokens
     * @param _account address of the user
     * @return true if the user has positive deposit balance
     */
    function isUserHasAnyDeposits(address _account) public view returns (bool) {
        Account storage account = accounts[_account];
        return account.depositBitmap > 0;
    }

    /**
     * Check if the user has deposit for a token
     * @param _account address of the user
     * @param _index index of the token
     * @return true if the user has positive deposit balance for the token
     */
    function isUserHasDeposits(address _account, uint8 _index) public view returns (bool) {
        Account storage account = accounts[_account];
        return account.depositBitmap.isBitSet(_index);
    }

    /**
     * Check if the user has borrowed a token
     * @param _account address of the user
     * @param _index index of the token
     * @return true if the user has borrowed the token
     */
    function isUserHasBorrows(address _account, uint8 _index) public view returns (bool) {
        Account storage account = accounts[_account];
        return account.borrowBitmap.isBitSet(_index);
    }

    /**
     * Set the deposit bitmap for a token.
     * @param _account address of the user
     * @param _index index of the token
     */
    function setInDepositBitmap(address _account, uint8 _index) internal {
        Account storage account = accounts[_account];
        account.depositBitmap = account.depositBitmap.setBit(_index);
    }

    /**
     * Unset the deposit bitmap for a token
     * @param _account address of the user
     * @param _index index of the token
     */
    function unsetFromDepositBitmap(address _account, uint8 _index) internal {
        Account storage account = accounts[_account];
        account.depositBitmap = account.depositBitmap.unsetBit(_index);
    }

    /**
     * Set the borrow bitmap for a token.
     * @param _account address of the user
     * @param _index index of the token
     */
    function setInBorrowBitmap(address _account, uint8 _index) internal {
        Account storage account = accounts[_account];
        account.borrowBitmap = account.borrowBitmap.setBit(_index);
    }

    /**
     * Unset the borrow bitmap for a token
     * @param _account address of the user
     * @param _index index of the token
     */
    function unsetFromBorrowBitmap(address _account, uint8 _index) internal {
        Account storage account = accounts[_account];
        account.borrowBitmap = account.borrowBitmap.unsetBit(_index);
    }

    function getDepositPrincipal(address _accountAddr, address _token) public view returns(uint256) {
        AccountTokenLib.TokenInfo storage tokenInfo = accounts[_accountAddr].tokenInfos[_token];
        return tokenInfo.getDepositPrincipal();
    }

    function getBorrowPrincipal(address _accountAddr, address _token) public view returns(uint256) {
        AccountTokenLib.TokenInfo storage tokenInfo = accounts[_accountAddr].tokenInfos[_token];
        return tokenInfo.getBorrowPrincipal();
    }

    function getLastDepositBlock(address _accountAddr, address _token) public view returns(uint256) {
        AccountTokenLib.TokenInfo storage tokenInfo = accounts[_accountAddr].tokenInfos[_token];
        return tokenInfo.getLastDepositBlock();
    }

    function getLastBorrowBlock(address _accountAddr, address _token) public view returns(uint256) {
        AccountTokenLib.TokenInfo storage tokenInfo = accounts[_accountAddr].tokenInfos[_token];
        return tokenInfo.getLastBorrowBlock();
    }

    /**
     * Get deposit interest of an account for a specific token
     * @param _account account address
     * @param _token token address
     * @dev The deposit interest may not have been updated in AccountTokenLib, so we need to explicited calcuate it.
     */
    function getDepositInterest(address _account, address _token) public view returns(uint256) {
        AccountTokenLib.TokenInfo storage tokenInfo = accounts[_account].tokenInfos[_token];
        // If the account has never deposited the token, return 0.
        if (tokenInfo.getLastDepositBlock() == 0)
            return 0;
        else {
            // As the last deposit block exists, the block is also a check point on index curve.
            uint256 accruedRate = globalConfig.bank().getDepositAccruedRate(_token, tokenInfo.getLastDepositBlock());
            return tokenInfo.calculateDepositInterest(accruedRate);
        }
    }

    function getBorrowInterest(address _accountAddr, address _token) public view returns(uint256) {
        AccountTokenLib.TokenInfo storage tokenInfo = accounts[_accountAddr].tokenInfos[_token];
        // If the account has never borrowed the token, return 0
        if (tokenInfo.getLastBorrowBlock() == 0)
            return 0;
        else {
            // As the last borrow block exists, the block is also a check point on index curve.
            uint256 accruedRate = globalConfig.bank().getBorrowAccruedRate(_token, tokenInfo.getLastBorrowBlock());
            return tokenInfo.calculateBorrowInterest(accruedRate);
        }
    }

    function borrow(address _accountAddr, address _token, uint256 _amount) external onlyAuthorized {
        require(_amount != 0, "Borrow zero amount of token is not allowed.");
        require(isUserHasAnyDeposits(_accountAddr), "The user doesn't have any deposits.");
        require(
            getBorrowETH(_accountAddr).add(
                _amount.mul(globalConfig.tokenInfoRegistry().priceFromAddress(_token))
                .div(Utils.getDivisor(address(globalConfig), _token))
            )
            <= getBorrowPower(_accountAddr), "Insufficient collateral when borrow.");

        AccountTokenLib.TokenInfo storage tokenInfo = accounts[_accountAddr].tokenInfos[_token];

        if(tokenInfo.getLastBorrowBlock() == 0)
            tokenInfo.borrow(_amount, INT_UNIT, getBlockNumber());
        else {
            calculateBorrowFIN(tokenInfo.getLastBorrowBlock(), _token, _accountAddr, getBlockNumber());
            uint256 accruedRate = globalConfig.bank().getBorrowAccruedRate(_token, tokenInfo.getLastBorrowBlock());
            // Update the token principla and interest
            tokenInfo.borrow(_amount, accruedRate, getBlockNumber());
        }

        // Since we have checked that borrow amount is larget than zero. We can set the borrow
        // map directly without checking the borrow balance.
        uint8 tokenIndex = globalConfig.tokenInfoRegistry().getTokenIndex(_token);
        setInBorrowBitmap(_accountAddr, tokenIndex);
    }

    /**
     * Update token info for withdraw. The interest will be withdrawn with higher priority.
     */
    function withdraw(address _accountAddr, address _token, uint256 _amount) external onlyAuthorized returns(uint256) {

        // Check if withdraw amount is less than user's balance
        require(_amount <= getDepositBalanceCurrent(_token, _accountAddr), "Insufficient balance.");
        uint256 borrowLTV = globalConfig.tokenInfoRegistry().getBorrowLTV(_token);

        // This if condition is to deal with the withdraw of collateral token in liquidation.
        // As the amount if borrowed asset is already large than the borrow power, we don't
        // have to check the condition here.
        if(getBorrowETH(_accountAddr) <= getBorrowPower(_accountAddr))
            require(
                getBorrowETH(_accountAddr) <= getBorrowPower(_accountAddr).sub(
                    _amount.mul(globalConfig.tokenInfoRegistry().priceFromAddress(_token))
                    .mul(borrowLTV).div(Utils.getDivisor(address(globalConfig), _token)).div(100)
                ), "Insufficient collateral when withdraw.");

        AccountTokenLib.TokenInfo storage tokenInfo = accounts[_accountAddr].tokenInfos[_token];
        uint lastBlock = tokenInfo.getLastDepositBlock();
        uint currentBlock = getBlockNumber();
        calculateDepositFIN(lastBlock, _token, _accountAddr, currentBlock);

        uint256 principalBeforeWithdraw = tokenInfo.getDepositPrincipal();

        if (tokenInfo.getLastDepositBlock() == 0)
            tokenInfo.withdraw(_amount, INT_UNIT, getBlockNumber());
        else {
            // As the last deposit block exists, the block is also a check point on index curve.
            uint256 accruedRate = globalConfig.bank().getDepositAccruedRate(_token, tokenInfo.getLastDepositBlock());
            tokenInfo.withdraw(_amount, accruedRate, getBlockNumber());
        }

        uint256 principalAfterWithdraw = tokenInfo.getDepositPrincipal();
        if(tokenInfo.getDepositPrincipal() == 0) {
            uint8 tokenIndex = globalConfig.tokenInfoRegistry().getTokenIndex(_token);
            unsetFromDepositBitmap(_accountAddr, tokenIndex);
        }

        uint commission = 0;
        if (_accountAddr != globalConfig.deFinerCommunityFund()) {
            // DeFiner takes 10% commission on the interest a user earn
            commission = _amount.sub(principalBeforeWithdraw.sub(principalAfterWithdraw)).mul(globalConfig.deFinerRate()).div(100);
            deposit(globalConfig.deFinerCommunityFund(), _token, commission);
        }

        return _amount.sub(commission);
    }

    /**
     * Update token info for deposit
     */
    function deposit(address _accountAddr, address _token, uint256 _amount) public onlyAuthorized {
        AccountTokenLib.TokenInfo storage tokenInfo = accounts[_accountAddr].tokenInfos[_token];
        if(tokenInfo.getDepositPrincipal() == 0) {
            uint8 tokenIndex = globalConfig.tokenInfoRegistry().getTokenIndex(_token);
            setInDepositBitmap(_accountAddr, tokenIndex);
        }

        if(tokenInfo.getLastDepositBlock() == 0)
            tokenInfo.deposit(_amount, INT_UNIT, getBlockNumber());
        else {
            calculateDepositFIN(tokenInfo.getLastDepositBlock(), _token, _accountAddr, getBlockNumber());
            uint accruedRate = globalConfig.bank().getDepositAccruedRate(_token, tokenInfo.getLastDepositBlock());
            tokenInfo.deposit(_amount, accruedRate, getBlockNumber());
        }
    }

    function repay(address _accountAddr, address _token, uint256 _amount) external onlyAuthorized returns(uint256){
        // Update tokenInfo
        uint256 amountOwedWithInterest = getBorrowBalanceCurrent(_token, _accountAddr);
        uint amount = _amount > amountOwedWithInterest ? amountOwedWithInterest : _amount;
        uint256 remain =  _amount > amountOwedWithInterest ? _amount.sub(amountOwedWithInterest) : 0;
        AccountTokenLib.TokenInfo storage tokenInfo = accounts[_accountAddr].tokenInfos[_token];
        // Sanity check
        require(tokenInfo.getBorrowPrincipal() > 0, "Token BorrowPrincipal must be greater than 0. To deposit balance, please use deposit button.");
        if(tokenInfo.getLastBorrowBlock() == 0)
            tokenInfo.repay(amount, INT_UNIT, getBlockNumber());
        else {
            calculateBorrowFIN(tokenInfo.getLastBorrowBlock(), _token, _accountAddr, getBlockNumber());
            uint accruedRate = globalConfig.bank().getBorrowAccruedRate(_token, tokenInfo.getLastBorrowBlock());
            tokenInfo.repay(amount, accruedRate, getBlockNumber());
        }

        if(tokenInfo.getBorrowPrincipal() == 0) {
            uint8 tokenIndex = globalConfig.tokenInfoRegistry().getTokenIndex(_token);
            unsetFromBorrowBitmap(_accountAddr, tokenIndex);
        }
        return remain;
    }

    // sichaoy: switch the order of the parameters
    function getDepositBalanceCurrent(
        address _token,
        address _accountAddr
    ) public view returns (uint256 depositBalance) {
        AccountTokenLib.TokenInfo storage tokenInfo = accounts[_accountAddr].tokenInfos[_token];
        uint accruedRate;
        if(tokenInfo.getDepositPrincipal() == 0) {
            return 0;
        } else {
            if(globalConfig.bank().depositeRateIndex(_token, tokenInfo.getLastDepositBlock()) == 0) {
                accruedRate = INT_UNIT;
            } else {
                accruedRate = globalConfig.bank().depositRateIndexNow(_token)
                .mul(INT_UNIT)
                .div(globalConfig.bank().depositeRateIndex(_token, tokenInfo.getLastDepositBlock()));
            }
            return tokenInfo.getDepositBalance(accruedRate);
        }
    }

    /**
     * Get current borrow balance of a token
     * @param _token token address
     * @dev This is an estimation. Add a new checkpoint first, if you want to derive the exact balance.
     */
    // sichaoy: What's the diff of getBorrowBalance with getBorrowAcruedRate?
    function getBorrowBalanceCurrent(
        address _token,
        address _accountAddr
    ) public view returns (uint256 borrowBalance) {
        AccountTokenLib.TokenInfo storage tokenInfo = accounts[_accountAddr].tokenInfos[_token];
        uint accruedRate;
        if(tokenInfo.getBorrowPrincipal() == 0) {
            return 0;
        } else {
            if(globalConfig.bank().borrowRateIndex(_token, tokenInfo.getLastBorrowBlock()) == 0) {
                accruedRate = INT_UNIT;
            } else {
                accruedRate = globalConfig.bank().borrowRateIndexNow(_token)
                .mul(INT_UNIT)
                .div(globalConfig.bank().borrowRateIndex(_token, tokenInfo.getLastBorrowBlock()));
            }
            return tokenInfo.getBorrowBalance(accruedRate);
        }
    }

    /**
     * Calculate an account's borrow power based on token's LTV
     */
    function getBorrowPower(address _borrower) public view returns (uint256 power) {
        for(uint8 i = 0; i < globalConfig.tokenInfoRegistry().getCoinLength(); i++) {
            if (isUserHasDeposits(_borrower, i)) {
                address token = globalConfig.tokenInfoRegistry().addressFromIndex(i);
                uint divisor = INT_UNIT;
                if(token != ETH_ADDR) {
                    divisor = 10**uint256(globalConfig.tokenInfoRegistry().getTokenDecimals(token));
                }
                // globalConfig.bank().newRateIndexCheckpoint(token);
                power = power.add(getDepositBalanceCurrent(token, _borrower)
                    .mul(globalConfig.tokenInfoRegistry().priceFromIndex(i))
                    .mul(globalConfig.tokenInfoRegistry().getBorrowLTV(token)).div(100)
                    .div(divisor)
                );
            }
        }
        return power;
    }

    /**
     * Get current deposit balance of a token
     * @dev This is an estimation. Add a new checkpoint first, if you want to derive the exact balance.
     */
    function getDepositETH(
        address _accountAddr
    ) public view returns (uint256 depositETH) {
        uint tokenNum = globalConfig.tokenInfoRegistry().getCoinLength();
        //console.log("tokenNum", tokenNum);
        for(uint i = 0; i < tokenNum; i++) {
            if(isUserHasDeposits(_accountAddr, uint8(i))) {
                address tokenAddress = globalConfig.tokenInfoRegistry().addressFromIndex(i);
                uint divisor = INT_UNIT;
                if(tokenAddress != ETH_ADDR) {
                    divisor = 10**uint256(globalConfig.tokenInfoRegistry().getTokenDecimals(tokenAddress));
                }
                depositETH = depositETH.add(getDepositBalanceCurrent(tokenAddress, _accountAddr).mul(globalConfig.tokenInfoRegistry().priceFromIndex(i)).div(divisor));
            }
        }
        return depositETH;
    }

    /**
     * Get borrowed balance of a token in the uint of Wei
     */
    // sichaoy: change name to getTotalBorrowInETH()
    function getBorrowETH(
        address _accountAddr
    ) public view returns (uint256 borrowETH) {
        uint tokenNum = globalConfig.tokenInfoRegistry().getCoinLength();
        //console.log("tokenNum", tokenNum);
        // SWC-128-DoS With Block Gas Limit: L387
        for(uint i = 0; i < tokenNum; i++) {
            if(isUserHasBorrows(_accountAddr, uint8(i))) {
                address tokenAddress = globalConfig.tokenInfoRegistry().addressFromIndex(i);
                uint divisor = INT_UNIT;
                if(tokenAddress != ETH_ADDR) {
                    divisor = 10 ** uint256(globalConfig.tokenInfoRegistry().getTokenDecimals(tokenAddress));
                }
                borrowETH = borrowETH.add(getBorrowBalanceCurrent(tokenAddress, _accountAddr).mul(globalConfig.tokenInfoRegistry().priceFromIndex(i)).div(divisor));
            }
        }
        return borrowETH;
    }

    /**
	 * Check if the account is liquidatable
     * @param _borrower borrower's account
     * @return true if the account is liquidatable
	 */
    function isAccountLiquidatable(address _borrower) external returns (bool) {

        // Add new rate check points for all the collateral tokens from borrower in order to
        // have accurate calculation of liquidation oppotunites.
        uint tokenNum = globalConfig.tokenInfoRegistry().getCoinLength();
        //console.log("tokenNum", tokenNum);
        for(uint8 i = 0; i < tokenNum; i++) {
            if (isUserHasDeposits(_borrower, i) || isUserHasBorrows(_borrower, i)) {
                address token = globalConfig.tokenInfoRegistry().addressFromIndex(i);
                globalConfig.bank().newRateIndexCheckpoint(token);
            }
        }

        uint256 liquidationThreshold = globalConfig.liquidationThreshold();
        uint256 liquidationDiscountRatio = globalConfig.liquidationDiscountRatio();

        uint256 totalBorrow = getBorrowETH(_borrower);
        uint256 totalCollateral = getDepositETH(_borrower);

        // The value of discounted collateral should be never less than the borrow amount.
        // We assume this will never happen as the market will not drop extreamly fast so that
        // the LTV changes from 85% to 95%, an 10% drop within one block.
        // require(
        //     totalBorrow.mul(100) <= totalCollateral.mul(liquidationDiscountRatio),
        //     "Collateral is not sufficient to be liquidated."
        // );

        // It is required that LTV is larger than LIQUIDATE_THREADHOLD for liquidation
        // return totalBorrow.mul(100) > totalCollateral.mul(liquidationThreshold);
        return totalBorrow.mul(100) > totalCollateral.mul(liquidationThreshold) && totalBorrow.mul(100) <= totalCollateral.mul(liquidationDiscountRatio);
    }

    struct LiquidationVars {
        uint256 totalBorrow;
        uint256 totalCollateral;
        uint256 msgTotalBorrow;
        uint256 msgTotalCollateral;

        uint256 targetTokenBalance;
        uint256 liquidationDebtValue;
        uint256 liquidationThreshold;
        uint256 liquidationDiscountRatio;
        uint256 borrowLTV;
        uint256 paymentOfLiquidationValue;
    }
    /**
     * Get current block number
     * @return the current block number
     */
    function getBlockNumber() private view returns (uint) {
        return block.number;
    }

    /**
     * An account claim all mined FIN token.
     * @dev If the FIN mining index point doesn't exist, we have to calculate the FIN amount 
     * accurately. So the user can withdraw all available FIN tokens.
     */
    function claim(address _account) public onlyAuthorized returns(uint){
        uint256 coinLength = globalConfig.tokenInfoRegistry().getCoinLength();
        for(uint8 i = 0; i < coinLength; i++) {
            if (isUserHasDeposits(_account, i) || isUserHasBorrows(_account, i)) {
                address token = globalConfig.tokenInfoRegistry().addressFromIndex(i);
                AccountTokenLib.TokenInfo storage tokenInfo = accounts[_account].tokenInfos[token];
                uint256 currentBlock = getBlockNumber();
                globalConfig.bank().updateMining(token);

                if (isUserHasDeposits(_account, i)) {
                    globalConfig.bank().updateDepositFINIndex(token);
                    uint256 accruedRate = globalConfig.bank().getDepositAccruedRate(token, tokenInfo.getLastDepositBlock());
                    calculateDepositFIN(tokenInfo.getLastDepositBlock(), token, _account, currentBlock);
                    tokenInfo.deposit(0, accruedRate, currentBlock);
                }

                if (isUserHasBorrows(_account, i)) {
                    globalConfig.bank().updateBorrowFINIndex(token);
                    uint256 accruedRate = globalConfig.bank().getBorrowAccruedRate(token, tokenInfo.getLastBorrowBlock());
                    calculateBorrowFIN(tokenInfo.getLastBorrowBlock(), token, _account, currentBlock);
                    tokenInfo.borrow(0, accruedRate, currentBlock);
                }
            }
        }
        uint _FINAmount = FINAmount[_account];
        FINAmount[_account] = 0;
        return _FINAmount;
    }

    /**
     * Accumulate the amount FIN mined by depositing between _lastBlock and _currentBlock
     */
    function calculateDepositFIN(uint256 _lastBlock, address _token, address _accountAddr, uint _currentBlock) internal {
        uint indexDifference = globalConfig.bank().depositFINRateIndex(_token, _currentBlock)
                                .sub(globalConfig.bank().depositFINRateIndex(_token, _lastBlock));
        uint getFIN = getDepositBalanceCurrent(_token, _accountAddr)
                        .mul(indexDifference)
                        .div(globalConfig.bank().depositeRateIndex(_token, getBlockNumber()));
        FINAmount[_accountAddr] = FINAmount[_accountAddr].add(getFIN);
    }

    /**
     * Accumulate the amount FIN mined by borrowing between _lastBlock and _currentBlock
     */
    function calculateBorrowFIN(uint256 _lastBlock, address _token, address _accountAddr, uint _currentBlock) internal {
        uint indexDifference = globalConfig.bank().borrowFINRateIndex(_token, _currentBlock)
                                .sub(globalConfig.bank().borrowFINRateIndex(_token, _lastBlock));
        uint getFIN = getBorrowBalanceCurrent(_token, _accountAddr)
                        .mul(indexDifference)
                        .div(globalConfig.bank().borrowRateIndex(_token, getBlockNumber()));
        FINAmount[_accountAddr] = FINAmount[_accountAddr].add(getFIN);
    }
}
