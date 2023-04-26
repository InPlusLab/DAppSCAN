pragma solidity ^0.4.0;

/**
 * @title Interface contract to handle calls on different contracts
 * @author Nikola Madjarevic
 */
contract IHandleCampaignDeployment {

    /**
     * @notice Function which will be used as simulation for constructor under TwoKeyAcquisitionCampaign contract
     * @dev This is just an interface of the function, the actual logic
     * is implemented under TwoKeyAcquisitionCampaignERC20.sol contract
     * This function can be called only once per proxy address
     */
    function setInitialParamsCampaign(
        address _twoKeySingletonesRegistry,
        address _twoKeyAcquisitionLogicHandler,
        address _conversionHandler,
        address _moderator,
        address _assetContractERC20,
        address _contractor,
        uint [] values
    ) public;

    /**
     * @notice Function which will be used as simulation for constructor under TwoKeyAcquisitionLogicHandler contract
     * @dev This is just an interface of the function, the actual logic
     * is implemented under TwoKeyAcquisitionLogicHandler.sol contract
     * This function can be called only once per proxy address
     */
    function setInitialParamsLogicHandler(
        uint [] values,
        string _currency,
        address _assetContractERC20,
        address _moderator,
        address _contractor,
        address _acquisitionCampaignAddress,
        address _twoKeySingletoneRegistry,
        address _twoKeyConversionHandler
    ) public;

    /**
     * @notice Function which will be used as simulation for constructor under TwoKeyConversionHandler contract
     * @dev This is just an interface of the function, the actual logic
     * is implemented under TwoKeyConversionHandler.sol contract
     * This function can be called only once per proxy address
     */
    function setInitialParamsConversionHandler(
        uint [] values,
        address _twoKeyAcquisitionCampaignERC20,
        address _twoKeyPurchasesHandler,
        address _contractor,
        address _assetContractERC20,
        address _twoKeyEventSource,
        address _twoKeyBaseReputationRegistry
    ) public;


    /**
     * @notice Function which will be used as simulation for constructor under TwoKeyPurchasesHandler contract
     * @dev This is just an interface of the function, the actual logic
     * is implemented under TwoKeyPurchasesHandler.sol contract
     * This function can be called only once per proxy address
     */
    function setInitialParamsPurchasesHandler(
        uint[] values,
        address _contractor,
        address _assetContractERC20,
        address _twoKeyEventSource,
        address _proxyConversionHandler
    ) public;


    /**
     * @notice Function which will be used as simulation for constructor under TwoKeyDonationCampaign contract
     * @dev This is just an interface of the function, the actual logic
     * is implemented under TwoKeyDonationCampaign.sol contract
     * This function can be called only once per proxy address
     */
    function setInitialParamsDonationCampaign(
        address _contractor,
        address _moderator,
        address _twoKeySingletonRegistry,
        address _twoKeyDonationConversionHandler,
        address _twoKeyDonationLogicHandler,
        uint [] numberValues,
        bool [] booleanValues
    ) public;

    /**
     * @notice Function which will be used as simulation for constructor under TwoKeyDonationConversionHandler contract
     * @dev This is just an interface of the function, the actual logic
     * is implemented under TwoKeyDonationConversionHandler.sol contract
     * This function can be called only once per proxy address
     */
    function setInitialParamsDonationConversionHandler(
        string tokenName,
        string tokenSymbol,
        string _currency,
        address _contractor,
        address _twoKeyDonationCampaign,
        address _twoKeySingletonRegistry
    ) public;


    function setInitialParamsDonationLogicHandler(
        uint[] numberValues,
        string currency,
        address contractor,
        address moderator,
        address twoKeySingletonRegistry,
        address twoKeyDonationCampaign,
        address twoKeyDonationLogicHandler
    ) public;
}

