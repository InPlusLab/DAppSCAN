/*
 * Copyright (c) The Force Protocol Development Team
 */
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./IRouter.sol";
import "./StageDefine.sol";
import "./ERC20lib.sol";
import "./IBondData.sol";

interface ICoreUtils {
    function d(uint256 id) external view returns (address);

    function bondData(uint256 id) external view returns (IBondData);

    //principal + interest = principal * (1 + couponRate);
    function calcPrincipalAndInterest(uint256 principal, uint256 couponRate)
        external
        pure
        returns (uint256);

    //可转出金额,募集到的总资金减去给所有投票人的手续费
    function transferableAmount(uint256 id) external view returns (uint256);

    //总的募集资金量
    function debt(uint256 id) external view returns (uint256);

    //总的募集资金量
    function totalInterest(uint256 id) external view returns (uint256);

    function debtPlusTotalInterest(uint256 id) external view returns (uint256);

    //可投资的剩余份数
    function remainInvestAmount(uint256 id) external view returns (uint256);

        function calcMinCollateralTokenAmount(uint256 id)
        external
        view
        returns (uint256);
    function pawnBalanceInUsd(uint256 id) external view returns (uint256);

    function disCountPawnBalanceInUsd(uint256 id)
        external
        view
        returns (uint256);

    function crowdBalanceInUsd(uint256 id) external view returns (uint256);

    //资不抵债判断，资不抵债时，为true，否则为false
    function isInsolvency(uint256 id) external view returns (bool);

    //获取质押的代币价格
    function pawnPrice(uint256 id) external view returns (uint256);

    //获取募资的代币价格
    function crowdPrice(uint256 id) external view returns (uint256);

    //要清算的质押物数量
    //X = (AC*price - PCR*PD)/(price*(1-PCR*Discount))
    //X = (PCR*PD - AC*price)/(price*(PCR*Discount-1))
    function X(uint256 id) external view returns (uint256 res);
    //清算额，减少的债务
    //X*price(collater)*Discount/price(crowd)
    function Y(uint256 id) external view returns (uint256 res);

    //到期后，由系统债务算出需要清算的抵押物数量
    function calcLiquidatePawnAmount(uint256 id) external view returns (uint256);
    function calcLiquidatePawnAmount(uint256 id, uint256 liability) external view returns (uint256);

    function investPrincipalWithInterest(uint256 id, address who)
        external
        view
        returns (uint256);

        //bond:
    function convert2BondAmount(address b, address t, uint256 amount)
        external
        view
        returns (uint256);

    //bond:
    function convert2GiveAmount(uint256 id, uint256 bondAmount)
        external
        view
        returns (uint256);
    
    function isUnsafe(uint256 id) external view returns (bool unsafe);
    function isDepositMultipleUnsafe(uint256 id) external view returns (bool unsafe);
    function getLiquidateAmount(uint id, uint y1) external view returns (uint256, uint256);
    function precision(uint256 id) external view returns (uint256);
}


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

interface IConfig {
    function voteDuration() external view returns (uint256);

    function investDuration() external view returns (uint256);
    function depositDuration() external view returns (uint256);

    function discount(address token) external view returns (uint256);
    function depositMultiple(address token) external view returns (uint256);
    function liquidateLine(address token) external view returns (uint256);

    function gracePeriod() external view returns (uint256);
    function partialLiquidateAmount(address token) external view returns (uint256);
    function gov() external view returns(address);
    function ratingFeeRatio() external view returns (uint256);
}

interface IACL {
    function accessible(address from, address to, bytes4 sig)
        external
        view
        returns (bool);
}

contract Core {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public ACL;
    address public router;
    address public config;
    address public oracle;
    ICoreUtils public coreUtils;
    address public nameGen;

    modifier auth {
        IACL _ACL = IACL(ACL);
        require(_ACL.accessible(msg.sender, address(this), msg.sig), "core: access unauthorized");
        _;
    }

    constructor(
        address _ACL,
        address _router,
        address _config,
        address _coreUtils,
        address _oracle,
	    address _nameGen
    ) public {
        ACL = _ACL;
        router = _router;
        config = _config;
        coreUtils = ICoreUtils(_coreUtils);
        oracle = _oracle;
	    nameGen = _nameGen;
    }

    function setCoreParamAddress(bytes32 k, address v) external auth {
        if (k == bytes32("router")) {
            router = v;
        }
        if (k == bytes32("config")) {
            config = v;
        }
        if (k == bytes32("coreUtils")) {
            coreUtils = ICoreUtils(v);
        }
        if (k == bytes32("oracle")) {
            oracle = v;
        }
    }

    function setACL(
        address _ACL) external {
        require(msg.sender == ACL, "require ACL");
        ACL = _ACL;
    }

    function f(uint256 id, bytes32 k) public view returns (address) {
        return IRouter(router).f(id, k);
    }

    function d(uint256 id) public view returns (address) {
        return IRouter(router).defaultDataContract(id);
    }

    function bondData(uint256 id) public view returns (IBondData) {
        return IBondData(d(id));
    }

    event MonitorEvent(address indexed who, address indexed bond, bytes32 indexed funcName, bytes);

    function MonitorEventCallback(address who, address bond, bytes32 funcName, bytes calldata payload) external {
        emit MonitorEvent(who, bond, funcName, payload);
    }

    function initialDepositCb(uint256 id, uint256 amount) external auth {
        IBondData b = bondData(id);
        b.setBondParam("depositMultiple", IConfig(config).depositMultiple(b.collateralToken()));

        require(amount >= ICoreUtils(coreUtils).calcMinCollateralTokenAmount(id), "invalid deposit amount");

        b.setBondParam("bondStage", uint256(BondStage.RiskRating));
        b.setBondParamAddress("gov", IConfig(config).gov());

        uint256 voteDuration = IConfig(config).voteDuration(); //s
        b.setBondParam("voteExpired", now + voteDuration);
        b.setBondParam("gracePeriod", IConfig(config).gracePeriod());

        b.setBondParam("discount", IConfig(config).discount(b.collateralToken()));
        b.setBondParam("liquidateLine", IConfig(config).liquidateLine(b.collateralToken()));
        b.setBondParam("partialLiquidateAmount", IConfig(config).partialLiquidateAmount(b.crowdToken()));


        b.setBondParam("borrowAmountGive", b.getBorrowAmountGive().add(amount));
               

    }

    //发债方追加资金, amount为需要转入的token数
    function depositCb(address who, uint256 id, uint256 amount)
        external
        auth
        returns (bool)
    {
        require(d(id) != address(0) && bondData(id).issuer() == who, "invalid address or issuer");

        IBondData b = bondData(id);
        // //充值amount token到合约中，充值之前需要approve
        // safeTransferFrom(b.collateralToken(), msg.sender, address(this), address(this), amount);

        b.setBondParam("borrowAmountGive",b.getBorrowAmountGive().add(amount));

        return true;
    }

    //投资债券接口
    //id: 发行的债券id，唯一标志债券
    //amount： 投资的数量
    function investCb(address who, uint256 id, uint256 amount)
        external
        auth
        returns (bool)
    {
        IBondData b = bondData(id);
        require(d(id) != address(0) 
            && who != b.issuer() 
            && now <= b.investExpired()
            && b.bondStage() == uint(BondStage.CrowdFunding), "forbidden self invest, or invest is expired");
        address give = b.crowdToken();

        uint256 bondAmount = coreUtils.convert2BondAmount(address(b), give, amount);
        //投资不能超过剩余可投份数
        require(
            bondAmount > 0 && bondAmount <= coreUtils.remainInvestAmount(id),
            "invalid bondAmount"
        );
        b.mintBond(who, bondAmount);

        // //充值amount token到合约中，充值之前需要approve
        // safeTransferFrom(give, msg.sender, address(this), address(this), amount);
        (uint256 _amountGive, uint256 _amountGet) =  b.getSupplyAmount(who);
        b.setSupply(who, 
            _amountGive.add(amount),
            _amountGet.add(bondAmount)
        );

        require(coreUtils.remainInvestAmount(id) >= 0, "bond overflow");


        return true;
    }

    //停止融资, 开始计息
    function interestBearingPeriod(uint256 id) external {
        IBondData b = bondData(id);

        //设置众筹状态, 调用的前置条件必须满足债券投票完成并且通过.
        //@auth 仅允许 @Core 合约调用.
        require(d(id) != address(0)
            && b.bondStage() == uint256(BondStage.CrowdFunding)
            && (now > b.investExpired() || coreUtils.remainInvestAmount(id) == 0), "already closed invest");
        //计算融资进度.
        if (
            b.totalBondIssuance().mul(b.minIssueRatio()).div(1e18) <= coreUtils.debt(id)
        ) {
            uint sysDebt = coreUtils.debtPlusTotalInterest(id);
            b.setBondParam("liability", sysDebt);
            b.setBondParam("originLiability", sysDebt);

            uint256 _1 = 1 ether;
            uint256 crowdUsdxLeverage = coreUtils.crowdBalanceInUsd(id)
                .mul(b.depositMultiple())
                .mul(b.liquidateLine())
                .div(_1);

            //CCR < 0.7 * 4
            //pawnUsd/crowdUsd < 0.7*4
            bool unsafe = coreUtils.pawnBalanceInUsd(id) < crowdUsdxLeverage;
            if (unsafe) {
                b.setBondParam("bondStage", uint256(BondStage.CrowdFundingFail));
                b.setBondParam("issuerStage", uint256(IssuerStage.UnWithdrawPawn));
            } else {
                b.setBondParam("bondExpired", now + b.maturity());

                b.setBondParam("bondStage", uint256(BondStage.CrowdFundingSuccess));
                b.setBondParam("issuerStage", uint256(IssuerStage.UnWithdrawCrowd));

                //根据当前融资额度获取投票手续费.
                uint256 baseDec = 18;
                uint256 delta = baseDec.sub(
                    uint256(ERC20Detailed(b.crowdToken()).decimals())
                );
                uint256 denominator = 10**delta;
                uint256 principal = b.actualBondIssuance().mul(b.par());
                //principal * (0.05) * 1e18/(10** (18 - 6))
                uint256 totalFee = principal.mul(b.issueFee()).div(denominator);
                uint256 voteFee = totalFee.mul(IConfig(config).ratingFeeRatio()).div(_1);
                b.setBondParam("fee", voteFee);
                b.setBondParam("sysProfit", totalFee.sub(voteFee));
            }
        } else {
            b.setBondParam("bondStage", uint256(BondStage.CrowdFundingFail));
            b.setBondParam("issuerStage", uint256(IssuerStage.UnWithdrawPawn));
        }

        emit MonitorEvent(msg.sender, address(b), "interestBearingPeriod", abi.encodePacked());
    }

    //转出募集到的资金,只有债券发行者可以转出资金
    function txOutCrowdCb(address who, uint256 id) external auth returns (uint) {
        IBondData b = IBondData(bondData(id));
        require(d(id) != address(0) && b.issuerStage() == uint(IssuerStage.UnWithdrawCrowd) && b.issuer() == who, "only txout crowd once or require issuer");


        uint256 balance = coreUtils.transferableAmount(id);
        // safeTransferFrom(crowd, address(this), address(this), msg.sender, balance);

        b.setBondParam("issuerStage", uint256(IssuerStage.WithdrawCrowdSuccess));
        b.setBondParam("bondStage", uint256(BondStage.UnRepay));

        return balance;
    }

    function overdueCb(uint256 id) external auth {
        IBondData b = IBondData(bondData(id));
        require(now >= b.bondExpired().add(b.gracePeriod()) 
            && (b.bondStage() == uint(BondStage.UnRepay) || b.bondStage() == uint(BondStage.CrowdFundingSuccess) ), "invalid overdue call state");
        b.setBondParam("bondStage", uint256(BondStage.Overdue));
        emit MonitorEvent(msg.sender, address(b), "overdue", abi.encodePacked());
    }

    //发债方还款
    //id: 发行的债券id，唯一标志债券
    //get: 募集的token地址
    //amount: 还款数量
    function repayCb(address who, uint256 id) external auth returns (uint) {
        require(d(id) != address(0) && bondData(id).issuer() == who, "invalid address or issuer");
        IBondData b = bondData(id);
        //募资成功，起息后即可还款,只有未还款或者逾期中可以还款，债务被关闭或者抵押物被清算完，不用还款
        require(
            b.bondStage() == uint(BondStage.UnRepay) || b.bondStage() == uint(BondStage.Overdue),
            "invalid state"
        );

        //充值repayAmount token到合约中，充值之前需要approve
        //使用amountGet进行计算
        uint256 repayAmount = b.liability();
        b.setBondParam("liability", 0);

        //safeTransferFrom(crowd, msg.sender, address(this), address(this), repayAmount);

        b.setBondParam("bondStage", uint256(BondStage.RepaySuccess));
        b.setBondParam("issuerStage", uint256(IssuerStage.UnWithdrawPawn));

        //清算一部分后,正常还款，需要设置清算中为false
        if (b.liquidating()) {
            b.setLiquidating(false);
        }

        return repayAmount;
    }

    //发债方取回质押token,在发债方已还清贷款的情况下，可以取回质押品
    //id: 发行的债券id，唯一标志债券
    //pawn: 抵押的token地址
    //amount: 取回数量
    function withdrawPawnCb(address who, uint256 id) external auth returns (uint) {
        IBondData b = bondData(id);
        require(d(id) != address(0) 
            && b.issuer() == who
            && b.issuerStage() == uint256(IssuerStage.UnWithdrawPawn), "invalid issuer, txout state or address");

        b.setBondParam("issuerStage", uint256(IssuerStage.WithdrawPawnSuccess));
        uint256 borrowGive = b.getBorrowAmountGive();
        //刚好结清债务和抵押物均为0（b.issuerStage() == uint256(IssuerStage.DebtClosed)）时，不能取回抵押物
        require(borrowGive > 0, "invalid give amount");
        b.setBondParam("borrowAmountGive", 0);//更新抵押品数量为0

        return borrowGive;
    }

    //募资失败，投资人凭借"债券"取回本金
    function withdrawPrincipalCb(address who, uint256 id)
        external
        auth
        returns (uint256)
    {
        IBondData b = bondData(id);
        address give = b.crowdToken();

        //募资完成, 但是未募资成功.
        require(d(id) != address(0) && 
            b.bondStage() == uint(BondStage.CrowdFundingFail),
            "must crowdfunding failure"
        );

        (uint256 supplyGive, uint256 _) = b.getSupplyAmount(who);
        b.setSupply(who, 0, 0);
        //safeTransferFrom(give, address(this), address(this), msg.sender, supplyGive);

        uint256 bondAmount = coreUtils.convert2BondAmount(
            address(b),
            give,
            supplyGive
        );
        b.burnBond(who, bondAmount);


        return supplyGive;
    }

    //债券到期, 投资人取回本金和收益
    function withdrawPrincipalAndInterestCb(address who, uint256 id)
        external
        auth
        returns (uint256)
    {
        require(d(id) != address(0), "invalid address");

        IBondData b = bondData(id);
        //募资成功，并且债券到期
        require(
            b.bondStage() == uint(BondStage.RepaySuccess)
            || b.bondStage() == uint(BondStage.DebtClosed),
            "unrepay or unliquidate"
        );

        address give = b.crowdToken();

        (uint256 supplyGive, uint256 _) = b.getSupplyAmount(who);
        uint256 bondAmount = coreUtils.convert2BondAmount(
            address(b),
            give,
            supplyGive
        );

        uint256 actualRepay = coreUtils.investPrincipalWithInterest(id, who);

        b.setSupply(who, 0, 0);
        //safeTransferFrom(give, address(this), address(this), msg.sender, actualRepay);

        b.burnBond(who, bondAmount);


        return actualRepay;
    }

    function abs(uint256 a, uint256 b) internal pure returns (uint c) {
        c = a >= b ? a.sub(b) : b.sub(a);
    }

    function liquidateInternal(address who, uint256 id, uint y1, uint x1) internal returns (uint256, uint256, uint256, uint256) {
        IBondData b = bondData(id);
        require(b.issuer() != who, "can't self-liquidate");

        //当前已经处于清算中状态
        if (b.liquidating()) {
            bool depositMultipleUnsafe = coreUtils.isDepositMultipleUnsafe(id);
            require(depositMultipleUnsafe, "in depositMultiple safe state");
        } else {
            require(coreUtils.isUnsafe(id), "in safe state");

            //设置为清算中状态
            b.setLiquidating(true);
        }

        uint256 balance = IERC20(b.crowdToken()).balanceOf(who);
        uint256 y = coreUtils.Y(id);
        uint256 x = coreUtils.X(id);

        require(balance >= y1 && y1 <= y, "insufficient y1 or balance");

        if (y1 == b.liability() || abs(y1, b.liability()) <= uint256(1) 
        || x1 == b.getBorrowAmountGive() 
        || abs(x1, b.getBorrowAmountGive()) <= coreUtils.precision(id)) {
            b.setBondParam("bondStage", uint(BondStage.DebtClosed));
            b.setLiquidating(false);
        }

        if (y1 == b.liability() || abs(y1, b.liability()) <= uint256(1)) {
            if (!(x1 == b.getBorrowAmountGive() || abs(x1, b.getBorrowAmountGive()) <= coreUtils.precision(id))) {
                b.setBondParam("issuerStage", uint(IssuerStage.UnWithdrawPawn));
            }
        }

        //对债务误差为1的处理
        if (abs(y1, b.liability()) <= uint256(1)) {
            b.setBondParam("liability", 0);
        } else {
            b.setBondParam("liability", b.liability().sub(y1));
        }

        if (abs(x1, b.getBorrowAmountGive()) <= coreUtils.precision(id)) {
            b.setBondParam("borrowAmountGive", 0);
        } else {
            b.setBondParam("borrowAmountGive", b.getBorrowAmountGive().sub(x1));
        }


        if (!coreUtils.isDepositMultipleUnsafe(id)) {
            b.setLiquidating(false);
        }

        return (y1, x1, y, x);
    }

    //分批清算债券接口
    //id: 债券发行id，同上
    function liquidateCb(address who, uint256 id, uint256 y1)
        external
        auth
        returns (uint256, uint256, uint256, uint256)
    {
        (uint y, uint x) = coreUtils.getLiquidateAmount(id, y1);

        return liquidateInternal(who, id, y, x);
    }

    function updateBalance(
        uint256 id,
        address sender,
        address recipient,
        uint256 bondAmount
    ) external auth {
        IBondData b = bondData(id);

        uint256 txAmount = coreUtils.convert2GiveAmount(id, bondAmount);
        require(b.balanceOf(sender) >= bondAmount && bondAmount > 0, "invalid tx amount");

        (uint256 _amoutSenderGive, uint256 _amountSenderGet) = b.getSupplyAmount(sender);
        (uint256 _amoutRecipientGive, uint256 _amountRecipientGet) = b.getSupplyAmount(recipient);
        b.setSupply(sender, _amoutSenderGive.sub(txAmount), _amountSenderGet.sub(bondAmount));
        b.setSupply(recipient, _amoutRecipientGive.add(txAmount), _amountRecipientGet.add(bondAmount));
    }

    //取回系统盈利
    function withdrawSysProfitCb(address who, uint256 id) external auth returns (uint256) {
        IBondData b = bondData(id);
        uint256 _sysProfit = b.sysProfit();
        require(_sysProfit > 0, "no withdrawable sysProfit");
        b.setBondParam("sysProfit", 0);
        return _sysProfit;
    }
}
