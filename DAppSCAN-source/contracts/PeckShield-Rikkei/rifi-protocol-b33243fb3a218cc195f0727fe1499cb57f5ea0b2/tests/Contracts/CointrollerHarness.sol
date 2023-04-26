pragma solidity ^0.5.16;

import "../../contracts/Cointroller.sol";
import "../../contracts/PriceOracle.sol";

contract CointrollerKovan is Cointroller {
  function getRifiAddress() public view returns (address) {
    return 0x61460874a7196d6a22D1eE4922473664b3E95270;
  }
}

contract CointrollerRopsten is Cointroller {
  function getRifiAddress() public view returns (address) {
    return 0x1Fe16De955718CFAb7A44605458AB023838C2793;
  }
}

contract CointrollerHarness is Cointroller {
    address rifiAddress;
    uint public blockNumber;

    constructor() Cointroller() public {}

    function setPauseGuardian(address harnessedPauseGuardian) public {
        pauseGuardian = harnessedPauseGuardian;
    }

    function setRifiSupplyState(address rToken, uint224 index, uint32 blockNumber_) public {
        rifiSupplyState[rToken].index = index;
        rifiSupplyState[rToken].block = blockNumber_;
    }

    function setRifiBorrowState(address rToken, uint224 index, uint32 blockNumber_) public {
        rifiBorrowState[rToken].index = index;
        rifiBorrowState[rToken].block = blockNumber_;
    }

    function setRifiAccrued(address user, uint userAccrued) public {
        rifiAccrued[user] = userAccrued;
    }

    function setRifiAddress(address rifiAddress_) public {
        rifiAddress = rifiAddress_;
    }

    function getRifiAddress() public view returns (address) {
        return rifiAddress;
    }

    /**
     * @notice Set the amount of RIFI distributed per block
     * @param rifiRate_ The amount of RIFI wei per block to distribute
     */
    function harnessSetRifiRate(uint rifiRate_) public {
        rifiRate = rifiRate_;
    }

    /**
     * @notice Recalculate and update RIFI speeds for all RIFI markets
     */
    function harnessRefreshRifiSpeeds() public {
        RToken[] memory allMarkets_ = allMarkets;

        for (uint i = 0; i < allMarkets_.length; i++) {
            RToken rToken = allMarkets_[i];
            Exp memory borrowIndex = Exp({mantissa: rToken.borrowIndex()});
            updateRifiSupplyIndex(address(rToken));
            updateRifiBorrowIndex(address(rToken), borrowIndex);
        }

        Exp memory totalUtility = Exp({mantissa: 0});
        Exp[] memory utilities = new Exp[](allMarkets_.length);
        for (uint i = 0; i < allMarkets_.length; i++) {
            RToken rToken = allMarkets_[i];
            if (rifiSpeeds[address(rToken)] > 0) {
                Exp memory assetPrice = Exp({mantissa: oracle.getUnderlyingPrice(rToken)});
                Exp memory utility = mul_(assetPrice, rToken.totalBorrows());
                utilities[i] = utility;
                totalUtility = add_(totalUtility, utility);
            }
        }

        for (uint i = 0; i < allMarkets_.length; i++) {
            RToken rToken = allMarkets[i];
            uint newSpeed = totalUtility.mantissa > 0 ? mul_(rifiRate, div_(utilities[i], totalUtility)) : 0;
            setRifiSpeedInternal(rToken, newSpeed);
        }
    }

    function setRifiBorrowerIndex(address rToken, address borrower, uint index) public {
        rifiBorrowerIndex[rToken][borrower] = index;
    }

    function setRifiSupplierIndex(address rToken, address supplier, uint index) public {
        rifiSupplierIndex[rToken][supplier] = index;
    }

    function harnessDistributeAllBorrowerRifi(address rToken, address borrower, uint marketBorrowIndexMantissa) public {
        distributeBorrowerRifi(rToken, borrower, Exp({mantissa: marketBorrowIndexMantissa}));
        rifiAccrued[borrower] = grantRifiInternal(borrower, rifiAccrued[borrower]);
    }

    function harnessDistributeAllSupplierRifi(address rToken, address supplier) public {
        distributeSupplierRifi(rToken, supplier);
        rifiAccrued[supplier] = grantRifiInternal(supplier, rifiAccrued[supplier]);
    }

    function harnessUpdateRifiBorrowIndex(address rToken, uint marketBorrowIndexMantissa) public {
        updateRifiBorrowIndex(rToken, Exp({mantissa: marketBorrowIndexMantissa}));
    }

    function harnessUpdateRifiSupplyIndex(address rToken) public {
        updateRifiSupplyIndex(rToken);
    }

    function harnessDistributeBorrowerRifi(address rToken, address borrower, uint marketBorrowIndexMantissa) public {
        distributeBorrowerRifi(rToken, borrower, Exp({mantissa: marketBorrowIndexMantissa}));
    }

    function harnessDistributeSupplierRifi(address rToken, address supplier) public {
        distributeSupplierRifi(rToken, supplier);
    }

    function harnessTransferRifi(address user, uint userAccrued, uint threshold) public returns (uint) {
        if (userAccrued > 0 && userAccrued >= threshold) {
            return grantRifiInternal(user, userAccrued);
        }
        return userAccrued;
    }

    function harnessAddRifiMarkets(address[] memory rTokens) public {
        for (uint i = 0; i < rTokens.length; i++) {
            // temporarily set rifiSpeed to 1 (will be fixed by `harnessRefreshRifiSpeeds`)
            setRifiSpeedInternal(RToken(rTokens[i]), 1);
        }
    }

    function harnessFastForward(uint blocks) public returns (uint) {
        blockNumber += blocks;
        return blockNumber;
    }

    function setBlockNumber(uint number) public {
        blockNumber = number;
    }

    function getBlockNumber() public view returns (uint) {
        return blockNumber;
    }

    function getRifiMarkets() public view returns (address[] memory) {
        uint m = allMarkets.length;
        uint n = 0;
        for (uint i = 0; i < m; i++) {
            if (rifiSpeeds[address(allMarkets[i])] > 0) {
                n++;
            }
        }

        address[] memory rifiMarkets = new address[](n);
        uint k = 0;
        for (uint i = 0; i < m; i++) {
            if (rifiSpeeds[address(allMarkets[i])] > 0) {
                rifiMarkets[k++] = address(allMarkets[i]);
            }
        }
        return rifiMarkets;
    }
}

contract CointrollerBorked {
    function _become(Unitroller unitroller, PriceOracle _oracle, uint _closeFactorMantissa, uint _maxAssets, bool _reinitializing) public {
        _oracle;
        _closeFactorMantissa;
        _maxAssets;
        _reinitializing;

        require(msg.sender == unitroller.admin(), "only unitroller admin can change brains");
        unitroller._acceptImplementation();
    }
}

contract BoolCointroller is CointrollerInterface {
    bool allowMint = true;
    bool allowRedeem = true;
    bool allowBorrow = true;
    bool allowRepayBorrow = true;
    bool allowLiquidateBorrow = true;
    bool allowSeize = true;
    bool allowTransfer = true;

    bool verifyMint = true;
    bool verifyRedeem = true;
    bool verifyBorrow = true;
    bool verifyRepayBorrow = true;
    bool verifyLiquidateBorrow = true;
    bool verifySeize = true;
    bool verifyTransfer = true;

    bool failCalculateSeizeTokens;
    uint calculatedSeizeTokens;

    uint noError = 0;
    uint opaqueError = noError + 11; // an arbitrary, opaque error code

    /*** Assets You Are In ***/

    function enterMarkets(address[] calldata _rTokens) external returns (uint[] memory) {
        _rTokens;
        uint[] memory ret;
        return ret;
    }

    function exitMarket(address _rToken) external returns (uint) {
        _rToken;
        return noError;
    }

    /*** Policy Hooks ***/

    function mintAllowed(address _rToken, address _minter, uint _mintAmount) public returns (uint) {
        _rToken;
        _minter;
        _mintAmount;
        return allowMint ? noError : opaqueError;
    }

    function mintVerify(address _rToken, address _minter, uint _mintAmount, uint _mintTokens) external {
        _rToken;
        _minter;
        _mintAmount;
        _mintTokens;
        require(verifyMint, "mintVerify rejected mint");
    }

    function redeemAllowed(address _rToken, address _redeemer, uint _redeemTokens) public returns (uint) {
        _rToken;
        _redeemer;
        _redeemTokens;
        return allowRedeem ? noError : opaqueError;
    }

    function redeemVerify(address _rToken, address _redeemer, uint _redeemAmount, uint _redeemTokens) external {
        _rToken;
        _redeemer;
        _redeemAmount;
        _redeemTokens;
        require(verifyRedeem, "redeemVerify rejected redeem");
    }

    function borrowAllowed(address _rToken, address _borrower, uint _borrowAmount) public returns (uint) {
        _rToken;
        _borrower;
        _borrowAmount;
        return allowBorrow ? noError : opaqueError;
    }

    function borrowVerify(address _rToken, address _borrower, uint _borrowAmount) external {
        _rToken;
        _borrower;
        _borrowAmount;
        require(verifyBorrow, "borrowVerify rejected borrow");
    }

    function repayBorrowAllowed(
        address _rToken,
        address _payer,
        address _borrower,
        uint _repayAmount) public returns (uint) {
        _rToken;
        _payer;
        _borrower;
        _repayAmount;
        return allowRepayBorrow ? noError : opaqueError;
    }

    function repayBorrowVerify(
        address _rToken,
        address _payer,
        address _borrower,
        uint _repayAmount,
        uint _borrowerIndex) external {
        _rToken;
        _payer;
        _borrower;
        _repayAmount;
        _borrowerIndex;
        require(verifyRepayBorrow, "repayBorrowVerify rejected repayBorrow");
    }

    function liquidateBorrowAllowed(
        address _rTokenBorrowed,
        address _rTokenCollateral,
        address _liquidator,
        address _borrower,
        uint _repayAmount) public returns (uint) {
        _rTokenBorrowed;
        _rTokenCollateral;
        _liquidator;
        _borrower;
        _repayAmount;
        return allowLiquidateBorrow ? noError : opaqueError;
    }

    function liquidateBorrowVerify(
        address _rTokenBorrowed,
        address _rTokenCollateral,
        address _liquidator,
        address _borrower,
        uint _repayAmount,
        uint _seizeTokens) external {
        _rTokenBorrowed;
        _rTokenCollateral;
        _liquidator;
        _borrower;
        _repayAmount;
        _seizeTokens;
        require(verifyLiquidateBorrow, "liquidateBorrowVerify rejected liquidateBorrow");
    }

    function seizeAllowed(
        address _rTokenCollateral,
        address _rTokenBorrowed,
        address _borrower,
        address _liquidator,
        uint _seizeTokens) public returns (uint) {
        _rTokenCollateral;
        _rTokenBorrowed;
        _liquidator;
        _borrower;
        _seizeTokens;
        return allowSeize ? noError : opaqueError;
    }

    function seizeVerify(
        address _rTokenCollateral,
        address _rTokenBorrowed,
        address _liquidator,
        address _borrower,
        uint _seizeTokens) external {
        _rTokenCollateral;
        _rTokenBorrowed;
        _liquidator;
        _borrower;
        _seizeTokens;
        require(verifySeize, "seizeVerify rejected seize");
    }

    function transferAllowed(
        address _rToken,
        address _src,
        address _dst,
        uint _transferTokens) public returns (uint) {
        _rToken;
        _src;
        _dst;
        _transferTokens;
        return allowTransfer ? noError : opaqueError;
    }

    function transferVerify(
        address _rToken,
        address _src,
        address _dst,
        uint _transferTokens) external {
        _rToken;
        _src;
        _dst;
        _transferTokens;
        require(verifyTransfer, "transferVerify rejected transfer");
    }

    /*** Special Liquidation Calculation ***/

    function liquidateCalculateSeizeTokens(
        address _rTokenBorrowed,
        address _rTokenCollateral,
        uint _repayAmount) public view returns (uint, uint) {
        _rTokenBorrowed;
        _rTokenCollateral;
        _repayAmount;
        return failCalculateSeizeTokens ? (opaqueError, 0) : (noError, calculatedSeizeTokens);
    }

    /**** Mock Settors ****/

    /*** Policy Hooks ***/

    function setMintAllowed(bool allowMint_) public {
        allowMint = allowMint_;
    }

    function setMintVerify(bool verifyMint_) public {
        verifyMint = verifyMint_;
    }

    function setRedeemAllowed(bool allowRedeem_) public {
        allowRedeem = allowRedeem_;
    }

    function setRedeemVerify(bool verifyRedeem_) public {
        verifyRedeem = verifyRedeem_;
    }

    function setBorrowAllowed(bool allowBorrow_) public {
        allowBorrow = allowBorrow_;
    }

    function setBorrowVerify(bool verifyBorrow_) public {
        verifyBorrow = verifyBorrow_;
    }

    function setRepayBorrowAllowed(bool allowRepayBorrow_) public {
        allowRepayBorrow = allowRepayBorrow_;
    }

    function setRepayBorrowVerify(bool verifyRepayBorrow_) public {
        verifyRepayBorrow = verifyRepayBorrow_;
    }

    function setLiquidateBorrowAllowed(bool allowLiquidateBorrow_) public {
        allowLiquidateBorrow = allowLiquidateBorrow_;
    }

    function setLiquidateBorrowVerify(bool verifyLiquidateBorrow_) public {
        verifyLiquidateBorrow = verifyLiquidateBorrow_;
    }

    function setSeizeAllowed(bool allowSeize_) public {
        allowSeize = allowSeize_;
    }

    function setSeizeVerify(bool verifySeize_) public {
        verifySeize = verifySeize_;
    }

    function setTransferAllowed(bool allowTransfer_) public {
        allowTransfer = allowTransfer_;
    }

    function setTransferVerify(bool verifyTransfer_) public {
        verifyTransfer = verifyTransfer_;
    }

    /*** Liquidity/Liquidation Calculations ***/

    function setCalculatedSeizeTokens(uint seizeTokens_) public {
        calculatedSeizeTokens = seizeTokens_;
    }

    function setFailCalculateSeizeTokens(bool shouldFail) public {
        failCalculateSeizeTokens = shouldFail;
    }
}

contract EchoTypesCointroller is UnitrollerAdminStorage {
    function stringy(string memory s) public pure returns(string memory) {
        return s;
    }

    function addresses(address a) public pure returns(address) {
        return a;
    }

    function booly(bool b) public pure returns(bool) {
        return b;
    }

    function listOInts(uint[] memory u) public pure returns(uint[] memory) {
        return u;
    }

    function reverty() public pure {
        require(false, "gotcha sucka");
    }

    function becomeBrains(address payable unitroller) public {
        Unitroller(unitroller)._acceptImplementation();
    }
}
