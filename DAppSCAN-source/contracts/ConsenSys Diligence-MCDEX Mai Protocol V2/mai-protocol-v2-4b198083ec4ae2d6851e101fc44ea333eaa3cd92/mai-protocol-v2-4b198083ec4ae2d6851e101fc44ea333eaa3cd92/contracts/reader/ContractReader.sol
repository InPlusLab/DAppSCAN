pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2; // to enable structure-type parameter

import "../lib/LibTypes.sol";
import "../interface/IPerpetual.sol";
import "../interface/IGlobalConfig.sol";


contract ContractReader {
    struct GovParams {
        uint256 withdrawalLockBlockCount;
        uint256 brokerLockBlockCount;
        LibTypes.PerpGovernanceConfig perpGovernanceConfig;
        LibTypes.AMMGovernanceConfig ammGovernanceConfig;
        address amm; // AMM contract address
        address poolAccount; // AMM account address
    }

    struct PerpetualStorage {
        address collateralTokenAddress;
        address shareTokenAddress;
        uint256 totalSize;
        int256 insuranceFundBalance;
        int256 longSocialLossPerContract;
        int256 shortSocialLossPerContract;
        bool isEmergency;
        bool isGlobalSettled;
        uint256 globalSettlePrice;
        LibTypes.FundingState fundingParams;
    }

    struct AccountStorage {
        LibTypes.CollateralAccount collateral;
        LibTypes.PositionAccount position;
        LibTypes.Broker broker;
    }

    function getGovParams(address perpetualAddress) public view returns (GovParams memory params) {
        IPerpetual perpetual = IPerpetual(perpetualAddress);
        IGlobalConfig globalConfig = IGlobalConfig(perpetual.globalConfig());
        params.withdrawalLockBlockCount = globalConfig.withdrawalLockBlockCount();
        params.brokerLockBlockCount = globalConfig.brokerLockBlockCount();
        params.perpGovernanceConfig = perpetual.getGovernance();
        params.ammGovernanceConfig = perpetual.amm().getGovernance();
        params.amm = address(perpetual.amm());
        params.poolAccount = address(perpetual.amm().perpetualProxy());
    }

    function getPerpetualStorage(address perpetualAddress) public view returns (PerpetualStorage memory params) {
        IPerpetual perpetual = IPerpetual(perpetualAddress);
        params.collateralTokenAddress = address(perpetual.collateral());
        params.shareTokenAddress = address(perpetual.amm().shareTokenAddress());

        params.totalSize = perpetual.totalSize(LibTypes.Side.LONG);
        params.longSocialLossPerContract = perpetual.socialLossPerContract(LibTypes.Side.LONG);
        params.shortSocialLossPerContract = perpetual.socialLossPerContract(LibTypes.Side.SHORT);
        params.insuranceFundBalance = perpetual.insuranceFundBalance();

        params.isEmergency = perpetual.status() == LibTypes.Status.SETTLING;
        params.isGlobalSettled = perpetual.status() == LibTypes.Status.SETTLED;
        params.globalSettlePrice = perpetual.settlementPrice();

        params.fundingParams = perpetual.amm().lastFundingState();
    }

    function getAccountStorage(address perpetualAddress, address guy)
        public
        view
        returns (AccountStorage memory params)
    {
        IPerpetual perpetual = IPerpetual(perpetualAddress);
        params.collateral = perpetual.getCashBalance(guy);
        params.position = perpetual.getPosition(guy);
        params.broker = perpetual.getBroker(guy);
    }
}
