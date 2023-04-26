pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;


interface IBondData {
    struct what {
        address proposal;
        uint256 weight;
    }

    struct prwhat {
        address who;
        address proposal;
        uint256 reason;
    }

    struct Balance {
        //发行者：
        //amountGive: 质押的token数量，项目方代币
        //amountGet: 募集的token数量，USDT，USDC

        //投资者：
        //amountGive: 投资的token数量，USDT，USDC
        //amountGet: 债券凭证数量
        uint256 amountGive;
        uint256 amountGet;
    }

    function issuer() external view returns (address);

    function collateralToken() external view returns (address);

    function crowdToken() external view returns (address);

    function getBorrowAmountGive() external view returns (uint256);



    function getSupplyAmount(address who) external view returns (uint256, uint256);

    function setSupplyAmountGet(address who, uint256) external;

    function par() external view returns (uint256);

    function mintBond(address who, uint256 amount) external;

    function burnBond(address who, uint256 amount) external;


    function transferableAmount() external view returns (uint256);

    function debt() external view returns (uint256);

    function actualBondIssuance() external view returns (uint256);

    function couponRate() external view returns (uint256);

    function depositMultiple() external view returns (uint256);

    function discount() external view returns (uint256);


    function voteExpired() external view returns (uint256);


    function investExpired() external view returns (uint256);

    function totalBondIssuance() external view returns (uint256);

    function maturity() external view returns (uint256);

    function config() external view returns (address);

    function weightOf(address who) external view returns (uint256);

    function totalWeight() external view returns (uint256);

    function bondExpired() external view returns (uint256);

    function interestBearingPeriod() external;


    function bondStage() external view returns (uint256);

    function issuerStage() external view returns (uint256);

    function issueFee() external view returns (uint256);


    function totalInterest() external view returns (uint256);

    function gracePeriod() external view returns (uint256);

    function liability() external view returns (uint256);

    function remainInvestAmount() external view returns (uint256);

    function supplyMap(address) external view returns (Balance memory);

    function setSupply(address who, uint256 amountGive, uint256 amountGet)
        external;

    function balanceOf(address account) external view returns (uint256);

    function setPar(uint256) external;

    function liquidateLine() external view returns (uint256);

    function setBondParam(bytes32 k, uint256 v) external;

    function setBondParamAddress(bytes32 k, address v) external;

    function minIssueRatio() external view returns (uint256);

    function partialLiquidateAmount() external view returns (uint256);

    function votes(address who) external view returns (what memory);

    function setVotes(address who, address proposal, uint256 amount) external;

    function weights(address proposal) external view returns (uint256);

    function setBondParamMapping(bytes32 name, address k, uint256 v) external;

    function top() external view returns (address);


    function voteLedger(address who) external view returns (uint256);

    function totalWeights() external view returns (uint256);


    function setPr(address who, address proposal, uint256 reason) external;

    function pr() external view returns (prwhat memory);

    function fee() external view returns (uint256);

    function profits(address who) external view returns (uint256);



    function totalProfits() external view returns (uint256);

    function originLiability() external view returns (uint256);

    function liquidating() external view returns (bool);
    function setLiquidating(bool _liquidating) external;

    function sysProfit() external view returns (uint256);
}
