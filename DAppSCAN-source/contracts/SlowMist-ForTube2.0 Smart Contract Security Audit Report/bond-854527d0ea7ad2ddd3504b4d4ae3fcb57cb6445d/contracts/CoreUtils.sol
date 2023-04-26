pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./ERC20lib.sol";
import "./IRouter.sol";
import "./StageDefine.sol";
import "./IBondData.sol";

/**
 * @title ERC20 interface
 * @dev see https://eips.ethereum.org/EIPS/eip-20
 */
interface IERC20Detailed {
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
}

interface IOracle {
    function get(address t) external view returns (uint, bool);
}

contract CoreUtils {
    using SafeMath for uint256;

    address public router;
    address public oracle;

    constructor (address _router, address _oracle) public {
        router = _router;
        oracle = _oracle;
    }

    function d(uint256 id) public view returns (address) {
        return IRouter(router).defaultDataContract(id);
    }

    function bondData(uint256 id) public view returns (IBondData) {
        return IBondData(d(id));
    }

    //principal + interest = principal * (1 + couponRate);
    function calcPrincipalAndInterest(uint256 principal, uint256 couponRate)
        public
        pure
        returns (uint256)
    {
        uint256 _1 = 1 ether;
        return principal.mul(_1.add(couponRate)).div(_1);
    }

    //可转出金额,募集到的总资金减去给所有投票人的手续费
    function transferableAmount(uint256 id) external view returns (uint256) {
        IBondData b = bondData(id);
        uint256 baseDec = 18;
        uint256 delta = baseDec.sub(
            uint256(ERC20Detailed(b.crowdToken()).decimals())
        );
        uint256 _1 = 1 ether;
        //principal * (1-0.05) * 1e18/(10** (18 - 6))
        return
            b.actualBondIssuance().mul(b.par()).mul((_1).sub(b.issueFee())).div(
                10**delta
            );
    }

    //总的募集资金量
    function debt(uint256 id) external view returns (uint256) {
        IBondData b = bondData(id);
        uint256 crowdDec = ERC20Detailed(b.crowdToken()).decimals();
        return b.actualBondIssuance().mul(b.par()).mul(10**crowdDec);
    }

    //总的募集资金量
    function totalInterest(uint256 id) external view returns (uint256) {
        IBondData b = bondData(id);
        uint256 crowdDec = ERC20Detailed(b.crowdToken()).decimals();
        return
            b
                .actualBondIssuance()
                .mul(b.par())
                .mul(10**crowdDec)
                .mul(b.couponRate())
                .div(1e18);
    }

    function debtPlusTotalInterest(uint256 id) public view returns (uint256) {
        IBondData b = bondData(id);
        uint256 crowdDec = ERC20Detailed(b.crowdToken()).decimals();
        uint256 _1 = 1 ether;
        return
            b
                .actualBondIssuance()
                .mul(b.par())
                .mul(10**crowdDec)
                .mul(_1.add(b.couponRate()))
                .div(1e18);
    }

    //可投资的剩余份数
    function remainInvestAmount(uint256 id) external view returns (uint256) {
        IBondData b = bondData(id);

        uint256 crowdDec = ERC20Detailed(b.crowdToken()).decimals();
        return
            b.totalBondIssuance().div(10**crowdDec).div(b.par()).sub(
                b.actualBondIssuance()
            );
    }

        function calcMinCollateralTokenAmount(uint256 id)
        external
        view
        returns (uint256)
    {
        IBondData b = bondData(id);

        uint256 CollateralDec = ERC20Detailed(b.collateralToken()).decimals();
        uint256 crowdDec = ERC20Detailed(b.crowdToken()).decimals();

        uint256 unitCollateral = 10**CollateralDec;
        uint256 unitCrowd = 10**crowdDec;

        return
            b
                .totalBondIssuance()
                .mul(b.depositMultiple())
                .mul(crowdPrice(id))
                .mul(unitCollateral)
                .div(pawnPrice(id))
                .div(unitCrowd);
    }

    function pawnBalanceInUsd(uint256 id) public view returns (uint256) {
        IBondData b = bondData(id);

        uint256 unitPawn = 10 **
            uint256(ERC20Detailed(b.collateralToken()).decimals());
        uint256 pawnUsd = pawnPrice(id).mul(b.getBorrowAmountGive()).div(unitPawn); //1e18
        return pawnUsd;
    }

    function disCountPawnBalanceInUsd(uint256 id)
        public
        view
        returns (uint256)
    {
        uint256 _1 = 1 ether;
        IBondData b = bondData(id);

        return pawnBalanceInUsd(id).mul(b.discount()).div(_1);
    }

    function crowdBalanceInUsd(uint256 id) public view returns (uint256) {
        IBondData b = bondData(id);

        uint256 unitCrowd = 10 **
            uint256(ERC20Detailed(b.crowdToken()).decimals());
        return crowdPrice(id).mul(b.liability()).div(unitCrowd);
    }

    //资不抵债判断，资不抵债时，为true，否则为false
    function isInsolvency(uint256 id) public view returns (bool) {
        return disCountPawnBalanceInUsd(id) < crowdBalanceInUsd(id);
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a <= b ? a : b;
    }

    //获取质押的代币价格
    function pawnPrice(uint256 id) public view returns (uint256) {
        IBondData b = bondData(id);

        (uint256 price, bool pawnPriceOk) = IOracle(oracle).get(b.collateralToken());
        require(pawnPriceOk, "invalid pawn price");
        return price;
    }

    //获取募资的代币价格
    function crowdPrice(uint256 id) public view returns (uint256) {
        IBondData b = bondData(id);

        (uint256 price, bool crowdPriceOk) = IOracle(oracle).get(b.crowdToken());
        require(crowdPriceOk, "invalid crowd price");
        return price;
    }

    //要清算的质押物数量
    //X = (AC*price - PCR*PD)/(price*(1-PCR*Discount))
    //X = (PCR*PD - AC*price)/(price*(PCR*Discount-1))
    function X(uint256 id) public view returns (uint256 res) {
        IBondData b = bondData(id);

        if (!isUnsafe(id)) {
            return 0;
        }

        //若质押资产不能清偿债务,全额清算
        if (isInsolvency(id)) {
            return b.getBorrowAmountGive();
        }

        //逾期未还款
        if (now >= b.bondExpired().add(b.gracePeriod())) {
            return calcLiquidatePawnAmount(id);
        }

        uint256 _1 = 1 ether;
        uint256 price = pawnPrice(id); //1e18
        uint256 pawnUsd = pawnBalanceInUsd(id);
        uint256 debtUsd = crowdBalanceInUsd(id).mul(b.depositMultiple());

        uint256 gap = pawnUsd >= debtUsd
            ? pawnUsd.sub(debtUsd)
            : debtUsd.sub(pawnUsd);
        uint256 pcrXdis = b.depositMultiple().mul(b.discount()); //1e18
        require(pcrXdis != _1, "PCR*Discout == 1 error");
        pcrXdis = pawnUsd >= debtUsd ? _1.sub(pcrXdis) : pcrXdis.sub(_1);
        uint256 denominator = price.mul(pcrXdis).div(_1); //1e18
        uint256 unitPawn = 10 **
            uint256(ERC20Detailed(b.collateralToken()).decimals());
        res = gap.mul(unitPawn).div(denominator); //1e18/1e18*1e18 == 1e18

        res = min(res, b.getBorrowAmountGive());
    }

    //清算额，减少的债务
    //X*price(collater)*Discount/price(crowd)
    function Y(uint256 id) public view returns (uint256 res) {
        IBondData b = bondData(id);

        if (!isUnsafe(id)) {
            return 0;
        }

        uint256 _1 = 1 ether;
        uint256 unitPawn = 10 **
            uint256(ERC20Detailed(b.collateralToken()).decimals());
        uint256 xp = X(id).mul(pawnPrice(id)).div(unitPawn);
        xp = xp.mul(b.discount()).div(_1);

        uint256 unitCrowd = 10 **
            uint256(ERC20Detailed(b.crowdToken()).decimals());
        res = xp.mul(unitCrowd).div(crowdPrice(id));

        res = min(res, b.liability());
    }

    //到期后，由系统债务算出需要清算的抵押物数量
    function calcLiquidatePawnAmount(uint256 id) public view returns (uint256) {
        IBondData b = bondData(id);
        return calcLiquidatePawnAmount(id, b.liability());
    }
    
    //return ((a + m - 1) / m) * m;
    function ceil(uint256 a, uint256 m) public pure returns (uint256) {
        return (a.add(m).sub(1)).div(m).mul(m);
    }
    
    function precision(uint256 id) public view returns (uint256) {
        IBondData b = bondData(id);

        uint256 decCrowd = uint256(ERC20Detailed(b.crowdToken()).decimals());
        uint256 decPawn = uint256(ERC20Detailed(b.collateralToken()).decimals());

        if (decPawn != decCrowd) {
            return 10 ** (abs(decPawn, decCrowd).add(1));
        }

        return 10;
    }
    
    function ceilPawn(uint256 id, uint256 a) public view returns (uint256) {
        IBondData b = bondData(id);
        
        uint256 decCrowd = uint256(ERC20Detailed(b.crowdToken()).decimals());
        uint256 decPawn = uint256(ERC20Detailed(b.collateralToken()).decimals());
        
        if (decPawn != decCrowd) {
            a = ceil(a, 10 ** abs(decPawn, decCrowd).sub(1));
        } else {
            a = ceil(a, 10);
        }
        return a;
    }
    
    //到期后，由系统债务算出需要清算的抵押物数量
    function calcLiquidatePawnAmount(uint256 id, uint256 liability) public view returns (uint256) {
        IBondData b = bondData(id);

        uint256 _crowdPrice = crowdPrice(id);
        uint256 _pawnPrice = pawnPrice(id);
        uint256 x = liability
            .mul(_crowdPrice)
            .mul(1 ether)
            .mul(10**uint256(ERC20Detailed(b.collateralToken()).decimals()))
            .div(10**uint256(ERC20Detailed(b.crowdToken()).decimals()))
            .div(_pawnPrice.mul(b.discount()));
        
        uint256 decCrowd = uint256(ERC20Detailed(b.crowdToken()).decimals());
        uint256 decPawn = uint256(ERC20Detailed(b.collateralToken()).decimals());
        
        if (decPawn != decCrowd) {
            x = ceil(x, 10 ** abs(decPawn, decCrowd).sub(1));
        } else {
            x = ceil(x, 10);
        }
        
        x = min(x, b.getBorrowAmountGive());

        if (x < b.getBorrowAmountGive()) {
            if (abs(x, b.getBorrowAmountGive()) <= precision(id)) {
                x = b.getBorrowAmountGive();//资不抵债情况
            }
        }

        return x;
    }

    function investPrincipalWithInterest(uint256 id, address who)
        external
        view
        returns (uint256)
    {
        require(d(id) != address(0), "invalid address");

        IBondData bond = bondData(id);
        address give = bond.crowdToken();

        (uint256 supplyGive, uint256 _) = bond.getSupplyAmount(who);
        uint256 bondAmount = convert2BondAmount(
            address(bond),
            give,
            supplyGive
        );

        uint256 crowdDec = IERC20Detailed(bond.crowdToken()).decimals();

        uint256 unrepayAmount = bond.liability(); //未还的债务
        uint256 actualRepay;

        if (unrepayAmount == 0) {
            actualRepay = calcPrincipalAndInterest(
                bondAmount.mul(1e18),
                bond.couponRate()
            );
            actualRepay = actualRepay.mul(bond.par()).mul(10**crowdDec).div(
                1e18
            );
        } else {
            //计算投资占比分之一,投资人亏损情况，从已还款（总债务-未还债务）中按比例分
            uint256 debtTotal = debtPlusTotalInterest(id);
            require(
                debtTotal >= unrepayAmount,
                "debtPlusTotalInterest < borrowGet, overflow"
            );
            actualRepay = debtTotal
                .sub(unrepayAmount)
                .mul(bondAmount)
                .div(bond.actualBondIssuance());
        }

        return actualRepay;
    }

    //bond:
    function convert2BondAmount(address b, address t, uint256 amount)
        public
        view
        returns (uint256)
    {
        IERC20Detailed erc20 = IERC20Detailed(t);
        uint256 dec = uint256(erc20.decimals());
        uint256 _par = IBondData(b).par();
        uint256 minAmount = _par.mul(10**dec);
        require(amount.mod(minAmount) == 0, "invalid amount"); //投资时，必须按份买

        return amount.div(minAmount);
    }

    function abs(uint256 a, uint256 b) internal pure returns (uint256 c) {
        c = a >= b ? a.sub(b) : b.sub(a);
    }

    //bond:
    function convert2GiveAmount(uint256 id, uint256 bondAmount)
        external
        view
        returns (uint256)
    {
        IBondData b = bondData(id);

        ERC20Detailed erc20 = ERC20Detailed(b.crowdToken());
        uint256 dec = uint256(erc20.decimals());
        return bondAmount.mul(b.par()).mul(10**dec);
    }

    //判断是否回到原始质押率(400%),回到后，设置为false，否则为true
    function isDepositMultipleUnsafe(uint256 id) external view returns (bool unsafe) {
        IBondData b = bondData(id);

        if (b.liability() == 0 || b.getBorrowAmountGive() == 0) {
            return false;
        }

        if (b.bondStage() == uint(BondStage.CrowdFundingSuccess)
            || b.bondStage() == uint(BondStage.UnRepay)
            || b.bondStage() == uint(BondStage.Overdue)) {

            if (now >= b.bondExpired().add(b.gracePeriod())) {
                return true;
            }

            uint256 _1 = 1 ether;
            uint256 crowdUsdxLeverage = crowdBalanceInUsd(id)
                .mul(b.depositMultiple())
                .div(_1);

            //CCR < 4
            //pawnUsd/crowdUsd < 4
            //unsafe = pawnBalanceInUsd(id) < crowdUsdxLeverage;
            
            uint256 _ceilPawn = ceilPawn(id, pawnBalanceInUsd(id));
            
            uint256 _crowdPrice = crowdPrice(id);
            uint256 decCrowd = uint256(ERC20Detailed(b.crowdToken()).decimals());
            uint256 minCrowdInUsd = _crowdPrice.div(10 ** decCrowd);
            
            unsafe = _ceilPawn < crowdUsdxLeverage;
            if (abs(_ceilPawn, crowdUsdxLeverage) <= minCrowdInUsd && _ceilPawn < crowdUsdxLeverage) {
                unsafe = false;
            }
            return unsafe;
        }
        
        return false;
    }
    
    function isUnsafe(uint256 id) public view returns (bool unsafe) {
        IBondData b = bondData(id);
        uint256 decCrowd = uint256(ERC20Detailed(b.crowdToken()).decimals());
        uint256 _crowdPrice = crowdPrice(id);
        //1e15 is 0.001$
        if (b.liability().mul(_crowdPrice).div(10 ** decCrowd) <= 1e15 || b.getBorrowAmountGive() == 0) {
            return false;
        }

        if (b.liquidating()) {
            return true;
        }

        if (b.bondStage() == uint(BondStage.CrowdFundingSuccess)
            || b.bondStage() == uint(BondStage.UnRepay)
            || b.bondStage() == uint(BondStage.Overdue)) {

            if (now >= b.bondExpired().add(b.gracePeriod())) {
                return true;
            }

            uint256 _1 = 1 ether;
            uint256 crowdUsdxLeverage = crowdBalanceInUsd(id)
                .mul(b.depositMultiple())
                .mul(b.liquidateLine())
                .div(_1);

            //CCR < 0.7 * 4
            //pawnUsd/crowdUsd < 0.7*4
            //unsafe = pawnBalanceInUsd(id) < crowdUsdxLeverage;
            
            uint256 _ceilPawn = ceilPawn(id, pawnBalanceInUsd(id));
            


            uint256 minCrowdInUsd = _crowdPrice.div(10 ** decCrowd);
            
            unsafe = _ceilPawn < crowdUsdxLeverage;
            if (abs(_ceilPawn, crowdUsdxLeverage) <= minCrowdInUsd && _ceilPawn < crowdUsdxLeverage) {
                unsafe = false;
            }
            return unsafe;
        }
        
        return false;
    }

    //获取实际需要的清算数量
    function getLiquidateAmount(uint id, uint y1) external view returns (uint256, uint256) {
        uint256 y2 = y1;//y2为实际清算额度
        uint256 y = Y(id);//y为剩余清算额度
        require(y1 <= y, "exceed max liquidate amount");

        //剩余额度小于一次清算量，将剩余额度全部清算
        IBondData b = bondData(id);

        uint decUnit = 10 ** uint(IERC20Detailed(b.crowdToken()).decimals());
        if (y <= b.partialLiquidateAmount()) {
            y2 = y;
        } else {
           require(y1 >= decUnit, "below min liquidate amount");//设置最小清算额度为1单位
        }
        uint256 x = calcLiquidatePawnAmount(id, y2);
        return (y2, x);
    }
}