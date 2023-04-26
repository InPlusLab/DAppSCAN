pragma solidity ^0.4.0;


import "../interfaces/ITwoKeySingletoneRegistryFetchAddress.sol";
import "../interfaces/IHandleCampaignDeployment.sol";
import "../interfaces/ITwoKeyCampaignValidator.sol";
import "../upgradable-pattern-campaigns/ProxyCampaign.sol";
import "../upgradable-pattern-campaigns/UpgradeableCampaign.sol";
import "../acquisition-campaign-contracts/TwoKeyPurchasesHandler.sol";
import "../acquisition-campaign-contracts/TwoKeyAcquisitionLogicHandler.sol";
import "../upgradability/Upgradeable.sol";
import "./ITwoKeySingletonUtils.sol";
import "../interfaces/storage-contracts/ITwoKeyFactoryStorage.sol";


/**
 * @author Nikola Madjarevic
 * @title Contract used to deploy proxies for other non-singleton contracts
 */
contract TwoKeyFactory is Upgradeable, ITwoKeySingletonUtils {

    bool initialized;

    ITwoKeyFactoryStorage PROXY_STORAGE_CONTRACT;

    event ProxyForCampaign(
        address proxyLogicHandler,
        address proxyConversionHandler,
        address proxyAcquisitionCampaign,
        address proxyPurchasesHandler,
        address contractor
    );

    event ProxyForDonationCampaign(
        address proxyDonationCampaign,
        address proxyDonationConversionHandler,
        address proxyDonationLogicHandler,
        address contractor
    );


    /**
     * @notice Function to set initial parameters for the contract
     * @param _twoKeySingletonRegistry is the address of singleton registry contract
     */
    function setInitialParams(
        address _twoKeySingletonRegistry,
        address _proxyStorage
    )
    public
    {
        require(initialized == false);

        TWO_KEY_SINGLETON_REGISTRY = ITwoKeySingletoneRegistryFetchAddress(_twoKeySingletonRegistry);
        PROXY_STORAGE_CONTRACT = ITwoKeyFactoryStorage(_proxyStorage);
        initialized = true;
    }

    function getLatestContractVersion(string contractName) internal view returns (string) {
        return ITwoKeySingletoneRegistryFetchAddress(TWO_KEY_SINGLETON_REGISTRY).getLatestContractVersion(contractName);
    }


    /**
     * @notice Function used to deploy all necessary proxy contracts in order to use the campaign.
     * @dev This function will handle all necessary actions which should be done on the contract
     * in order to make them ready to work. Also, we've been unfortunately forced to use arrays
     * as arguments since the stack is not deep enough to handle this amount of input information
     * since this method handles kick-start of 3 contracts
     * @param addresses is array of addresses needed [assetContractERC20,moderator]
     * @param valuesConversion is array containing necessary values to start conversion handler contract
     * @param valuesLogicHandler is array of values necessary to start logic handler contract
     * @param values is array containing values necessary to start campaign contract
     * @param _currency is the main currency token price is set
     * @param _nonSingletonHash is the hash of non-singleton contracts active with responding
     * 2key-protocol version at the moment
     */
    function createProxiesForAcquisitions(
        address[] addresses,
        uint[] valuesConversion,
        uint[] valuesLogicHandler,
        uint[] values,
        string _currency,
        string _nonSingletonHash
    )
    public
    payable
    {

        //Deploy proxy for Acquisition contract
        ProxyCampaign proxyAcquisition = new ProxyCampaign(
            "TwoKeyAcquisitionCampaignERC20",
            getLatestContractVersion("TwoKeyAcquisitionCampaignERC20"),
            address(TWO_KEY_SINGLETON_REGISTRY)
        );

        //Deploy proxy for ConversionHandler contract
        ProxyCampaign proxyConversions = new ProxyCampaign(
            "TwoKeyConversionHandler",
            getLatestContractVersion("TwoKeyConversionHandler"),
            address(TWO_KEY_SINGLETON_REGISTRY)
        );

        //Deploy proxy for TwoKeyAcquisitionLogicHandler contract
        ProxyCampaign proxyLogicHandler = new ProxyCampaign(
            "TwoKeyAcquisitionLogicHandler",
            getLatestContractVersion("TwoKeyAcquisitionLogicHandler"),
            address(TWO_KEY_SINGLETON_REGISTRY)
        );


        //Deploy proxy for TwoKeyPurchasesHandler contract
        ProxyCampaign proxyPurchasesHandler = new ProxyCampaign(
            "TwoKeyPurchasesHandler",
            getLatestContractVersion("TwoKeyAcquisitionLogicHandler"),
            address(TWO_KEY_SINGLETON_REGISTRY)
        );


        //        UpgradeableCampaign(proxyPurchasesHandler).initialize.value(msg.value)(msg.sender);
        //        UpgradeableCampaign(proxyLogicHandler).initialize.value(msg.value)(msg.sender);
        //        UpgradeableCampaign(proxyConversions).initialize.value(msg.value)(msg.sender);
        //        UpgradeableCampaign(proxyAcquisition).initialize.value(msg.value)(msg.sender);

        IHandleCampaignDeployment(proxyPurchasesHandler).setInitialParamsPurchasesHandler(
            valuesConversion,
            msg.sender,
            addresses[0],
            getAddressFromTwoKeySingletonRegistry("TwoKeyEventSource"),
            proxyConversions
        );

        // Set initial arguments inside Conversion Handler contract
        IHandleCampaignDeployment(proxyConversions).setInitialParamsConversionHandler(
            valuesConversion,
            proxyAcquisition,
            proxyPurchasesHandler,
            msg.sender,
            addresses[0], //ERC20 address
            getAddressFromTwoKeySingletonRegistry("TwoKeyEventSource"),
            getAddressFromTwoKeySingletonRegistry("TwoKeyBaseReputationRegistry")
        );

        // Set initial arguments inside Logic Handler contract
        IHandleCampaignDeployment(proxyLogicHandler).setInitialParamsLogicHandler(
            valuesLogicHandler,
            _currency,
            addresses[0], //asset contract erc20
            addresses[1], // moderator
            msg.sender,
            proxyAcquisition,
            address(TWO_KEY_SINGLETON_REGISTRY),
            proxyConversions
        );

        // Set initial arguments inside AcquisitionCampaign contract
        IHandleCampaignDeployment(proxyAcquisition).setInitialParamsCampaign(
            address(TWO_KEY_SINGLETON_REGISTRY),
            address(proxyLogicHandler),
            address(proxyConversions),
            addresses[1], //moderator
            addresses[0], //asset contract
            msg.sender, //contractor
            values
        );

        // Validate campaign so it will be approved to interact (and write) to/with our singleton contracts
        ITwoKeyCampaignValidator(getAddressFromTwoKeySingletonRegistry("TwoKeyCampaignValidator"))
        .validateAcquisitionCampaign(proxyAcquisition, _nonSingletonHash);

        setAddressToCampaignType(proxyAcquisition, "TOKEN_SELL");
        // Emit an event with proxies for Acquisition campaign
        emit ProxyForCampaign(
            proxyLogicHandler,
            proxyConversions,
            proxyAcquisition,
            proxyPurchasesHandler,
            msg.sender
        );
    }


    /**
     * @notice Function to deploy proxy contracts for donation campaigns
     */
    function createProxiesForDonationCampaign(
        address _moderator,
        uint [] numberValues,
        bool [] booleanValues,
        string _currency,
        string tokenName,
        string tokenSymbol,
        string nonSingletonHash
    )
    public
    {

        // Deploying a proxy contract for donations
        ProxyCampaign proxyDonationCampaign = new ProxyCampaign(
            "TwoKeyDonationCampaign",
            getLatestContractVersion("TwoKeyDonationCampaign"),
            TWO_KEY_SINGLETON_REGISTRY
        );

        //Deploying a proxy contract for donation conversion handler
        ProxyCampaign proxyDonationConversionHandler = new ProxyCampaign(
            "TwoKeyDonationConversionHandler",
            getLatestContractVersion("TwoKeyDonationConversionHandler"),
            TWO_KEY_SINGLETON_REGISTRY
        );

        //Deploying a proxy contract for donation logic handler
        ProxyCampaign proxyDonationLogicHandler = new ProxyCampaign(
            "TwoKeyDonationLogicHandler",
            getLatestContractVersion("TwoKeyDonationLogicHandler"),
            TWO_KEY_SINGLETON_REGISTRY
        );

        IHandleCampaignDeployment(proxyDonationLogicHandler).setInitialParamsDonationLogicHandler(
            numberValues,
            _currency,
            msg.sender,
            _moderator,
            TWO_KEY_SINGLETON_REGISTRY,
            proxyDonationCampaign,
            proxyDonationConversionHandler
        );

        // Set initial parameters under Donation conversion handler
        IHandleCampaignDeployment(proxyDonationConversionHandler).setInitialParamsDonationConversionHandler(
            tokenName,
            tokenSymbol,
            _currency,
            msg.sender, //contractor
            proxyDonationCampaign,
            address(TWO_KEY_SINGLETON_REGISTRY)
        );

        // Set initial parameters under Donation campaign contract
        IHandleCampaignDeployment(proxyDonationCampaign).setInitialParamsDonationCampaign(
            msg.sender, //contractor
            _moderator, //moderator address
            TWO_KEY_SINGLETON_REGISTRY,
            proxyDonationConversionHandler,
            proxyDonationLogicHandler,
            numberValues,
            booleanValues
        );

        // Validate campaign
        ITwoKeyCampaignValidator(getAddressFromTwoKeySingletonRegistry("TwoKeyCampaignValidator"))
        .validateDonationCampaign(
            proxyDonationCampaign,
            proxyDonationConversionHandler,
            nonSingletonHash
        );

        setAddressToCampaignType(proxyDonationCampaign, "DONATION_CAMPAIGN");

//         Emit an event
        emit ProxyForDonationCampaign(
            proxyDonationCampaign,
            proxyDonationConversionHandler,
            proxyDonationLogicHandler,
            msg.sender
        );
    }

    /**
     * @notice internal function to set address to campaign type
     * @param _campaignAddress is the address of campaign
     * @param _campaignType is the type of campaign (String)
     */
    function setAddressToCampaignType(address _campaignAddress, string _campaignType) internal {
        bytes32 keyHash = keccak256("addressToCampaignType",_campaignAddress);
        PROXY_STORAGE_CONTRACT.setString(keyHash, _campaignType);
    }

    /**
     * @notice Function working as a getter
     * @param _key is the address of campaign
     */
    function addressToCampaignType(address _key) public view returns (string) {
        return PROXY_STORAGE_CONTRACT.getString(keccak256("addressToCampaignType", _key));
    }

}
