pragma solidity ^0.4.24;

import "../libraries/GetCode.sol";

import "../interfaces/ITwoKeyAcquisitionCampaignStateVariables.sol";
import "../interfaces/ITwoKeyEventSourceEvents.sol";
import "../interfaces/ITwoKeyCampaignPublicAddresses.sol";
import "../interfaces/ITwoKeyDonationCampaign.sol";
import "../interfaces/ITwoKeyDonationCampaignFetchAddresses.sol";
import "../interfaces/IGetImplementation.sol";
import "../interfaces/IStructuredStorage.sol";
import "../interfaces/storage-contracts/ITwoKeyCampaignValidatorStorage.sol";

import "../upgradability/Upgradeable.sol";
import "./ITwoKeySingletonUtils.sol";


/*******************************************************************************************************************
 *       General purpose of this contract is to validate the layer we can't control,
 *
 *
 *            *****************************************
 *            *  Contracts which are deployed by user *
 *            *  - TwoKeyAcquisitionCampaign          *
 *            *  - TwoKeyAcquisitionLogicHandler      *
 *            *  - TwoKeyConversionHandler            *
              *  - TwoKeyDonationCampaign             *
              *  - TwoKeyDonationConversionHandler    *
 *            *****************************************
 *                               |
 *                               |
 *                               |
 *            *****************************************
 *            *   Contract that validates everything  *      Permits        ************************************
 *            *   in the contracts deployed above     * ------------------> * Interaction with our singletones *
 *            *****************************************                     ************************************
 *
 ******************************************************************************************************************/


/**
 * @author Nikola Madjarevic
 * Created at 2/12/19
 */
contract TwoKeyCampaignValidator is Upgradeable, ITwoKeySingletonUtils {

    bool initialized;

    ITwoKeyCampaignValidatorStorage public PROXY_STORAGE_CONTRACT;

    /**
     * @notice Function to set initial parameters in this contract
     * @param _twoKeySingletoneRegistry is the address of TwoKeySingletoneRegistry contract
     */
    function setInitialParams(
        address _twoKeySingletoneRegistry,
        address _proxyStorage
    )
    public
    {
        require(initialized == false);

        TWO_KEY_SINGLETON_REGISTRY = _twoKeySingletoneRegistry;
        PROXY_STORAGE_CONTRACT = ITwoKeyCampaignValidatorStorage(_proxyStorage);

        initialized = true;
    }

    modifier onlyTwoKeyFactory {
        address twoKeyFactory = getAddressFromTwoKeySingletonRegistry("TwoKeyFactory");
        require(msg.sender == twoKeyFactory);
        _;
    }

    /**
     * @notice Function which is in charge to validate if the campaign contract is ready
     * It should be called by contractor after he finish all the stuff necessary for campaign to work
     * @param campaign is the address of the campaign, in this particular case it's acquisition
     * @dev Validates all the required stuff, if the campaign is not validated, it can't update our singletones
     */
    function validateAcquisitionCampaign(
        address campaign,
        string nonSingletonHash
    )
    public
    onlyTwoKeyFactory
    {
        address conversionHandler = ITwoKeyAcquisitionCampaignStateVariables(campaign).conversionHandler();
        address logicHandler = ITwoKeyAcquisitionCampaignStateVariables(campaign).twoKeyAcquisitionLogicHandler();

        PROXY_STORAGE_CONTRACT.setBool(keccak256("isCampaignValidated", conversionHandler), true);
        PROXY_STORAGE_CONTRACT.setBool(keccak256("isCampaignValidated", logicHandler), true);
        PROXY_STORAGE_CONTRACT.setBool(keccak256("isCampaignValidated",campaign), true);
        PROXY_STORAGE_CONTRACT.setString(keccak256("campaign2NonSingletonHash",campaign), nonSingletonHash);

        emitCreatedEvent(campaign);
    }

    /**
     * @notice Function to validate Donation campaign if it is ready
     * @param campaign is the campaign address
     * @dev Validates all the required stuff, if the campaign is not validated, it can't update our singletones
     */
    function validateDonationCampaign(
        address campaign,
        address donationConversionHandler,
        string nonSingletonHash
    )
    public
    onlyTwoKeyFactory
    {
        PROXY_STORAGE_CONTRACT.setBool(keccak256("isCampaignValidated",campaign), true);
        PROXY_STORAGE_CONTRACT.setString(keccak256("campaign2NonSingletonHash",campaign), nonSingletonHash);

        emitCreatedEvent(campaign);
    }


    /**
     * @notice Function to validate if specific conversion handler code is valid
     * @param _conversionHandler is the address of already deployed conversion handler
     * @return true if code is valid and responds to conversion handler contract
     */
    function isConversionHandlerCodeValid(
        address _conversionHandler
    )
    public
    view
    returns (bool)
    {
        require(PROXY_STORAGE_CONTRACT.getBool(keccak256("isCampaignValidated",_conversionHandler)) == true);
        return true;
    }


    /**
     * @notice Pure function to convert input string to hex
     * @param source is the input string
     */
    function stringToBytes32(
        string memory source
    )
    internal
    pure
    returns (bytes32 result)
    {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }
        assembly {
            result := mload(add(source, 32))
        }
    }

    function isCampaignValidated(address campaign) public view returns (bool) {
        bytes32 hashKey = keccak256("isCampaignValidated", campaign);
        return PROXY_STORAGE_CONTRACT.getBool(hashKey);
    }

    function campaign2NonSingletonHash(address campaign) public view returns (string) {
        return PROXY_STORAGE_CONTRACT.getString(keccak256("campaign2NonSingletonHash", campaign));
    }


    function emitCreatedEvent(address campaign) internal {
        address contractor = ITwoKeyAcquisitionCampaignStateVariables(campaign).contractor();
        address moderator = ITwoKeyAcquisitionCampaignStateVariables(campaign).moderator();

        //Get the event source address
        address twoKeyEventSource = getAddressFromTwoKeySingletonRegistry("TwoKeyEventSource");
        // Emit event
        ITwoKeyEventSourceEvents(twoKeyEventSource).created(campaign,contractor,moderator);
    }
}
