pragma solidity ^0.4.24;

import "../interfaces/ITwoKeyReg.sol";
import "../interfaces/ITwoKeyAdmin.sol";
import "../interfaces/ITwoKeyCampaignValidator.sol";
import "../interfaces/ITwoKeySingletoneRegistryFetchAddress.sol";
import "../interfaces/ITwoKeyMaintainersRegistry.sol";
import "../upgradability/Upgradeable.sol";
import "./ITwoKeySingletonUtils.sol";
import "../interfaces/storage-contracts/ITwoKeyEventSourceStorage.sol";


contract TwoKeyEventSource is Upgradeable, ITwoKeySingletonUtils {

    bool initialized;

    ITwoKeyEventSourceStorage public PROXY_STORAGE_CONTRACT;

    event Created(
        address _campaign,
        address _owner,
        address _moderator
    );

    event Joined(
        address _campaign,
        address _from,
        address _to
    );

    event Converted(
        address _campaign,
        address _converter,
        uint256 _amount
    );

    event Rewarded(
        address _campaign,
        address _to,
        uint256 _amount
    );

    event Cancelled(
        address _campaign,
        address _converter,
        uint256 _indexOrAmount
    );

    event Rejected(
        address _campaign,
        address _converter
    );

    event UpdatedPublicMetaHash(
        uint timestamp,
        string value
    );

    event UpdatedData(
        uint timestamp,
        uint value,
        string action
    );

    event ReceivedEther(
        address _sender,
        uint value
    );

    /**
     * Modifier which will allow only completely verified and validated contracts to emit the events
     */
    modifier onlyAllowedContracts {
        address twoKeyCampaignValidator = getAddressFromTwoKeySingletonRegistry("TwoKeyCampaignValidator");
        require(ITwoKeyCampaignValidator(twoKeyCampaignValidator).isCampaignValidated(msg.sender) == true);
        _;
    }

    modifier onlyValidator {
        address twoKeyCampaignValidator = getAddressFromTwoKeySingletonRegistry("TwoKeyCampaignValidator");
        require(msg.sender == twoKeyCampaignValidator);
        _;
    }

    /**
     * @notice Function to set initial params in the contract
     */
    function setInitialParams(
        address _twoKeySingletonesRegistry,
        address _proxyStorage
    )
    external
    {
        require(initialized == false);

        TWO_KEY_SINGLETON_REGISTRY = _twoKeySingletonesRegistry;
        PROXY_STORAGE_CONTRACT = ITwoKeyEventSourceStorage(_proxyStorage);

        initialized = true;
    }

    /**
     * @notice Function to emit created event every time campaign is created
     * @param _campaign is the address of the deployed campaign
     * @param _owner is the contractor address of the campaign
     * @param _moderator is the address of the moderator in campaign
     * @dev this function updates values in TwoKeyRegistry contract
     */
    function created(
        address _campaign,
        address _owner,
        address _moderator
    )
    external
    onlyValidator
    {
//        address twoKeyRegistry = getAddressFromTwoKeySingletonRegistry("TwoKeyRegistry");
//        ITwoKeyReg(twoKeyRegistry).addWhereContractor(_owner, _campaign);
//        ITwoKeyReg(twoKeyRegistry).addWhereModerator(_moderator, _campaign);
        emit Created(_campaign, _owner, _moderator);
    }

    /**
     * @notice Function to emit created event every time someone has joined to campaign
     * @param _campaign is the address of the deployed campaign
     * @param _from is the address of the referrer
     * @param _to is the address of person who has joined
     * @dev this function updates values in TwoKeyRegistry contract
     */
    function joined(
        address _campaign,
        address _from,
        address _to
    )
    external
    onlyAllowedContracts
    {
//        address twoKeyRegistry = getAddressFromTwoKeySingletonRegistry("TwoKeyRegistry");
//        ITwoKeyReg(twoKeyRegistry).addWhereReferrer(_campaign, _from);
        emit Joined(_campaign, _from, _to);
    }

    /**
     * @notice Function to emit created event every time conversion happened
     * @param _campaign is the address of the deployed campaign
     * @param _converter is the converter address
     * @param _amountETHWei is the conversion amount
     * @dev this function updates values in TwoKeyRegistry contract
     */
    function converted(
        address _campaign,
        address _converter,
        uint256 _amountETHWei
    )
    external
    onlyAllowedContracts
    {
//        address twoKeyRegistry = getAddressFromTwoKeySingletonRegistry("TwoKeyRegistry");
//        ITwoKeyReg(twoKeyRegistry).addWhereConverter(_converter, _campaign);
        emit Converted(_campaign, _converter, _amountETHWei);
    }

    /**
     * @notice Function to emit created event every time reward happened
     * @param _campaign is the address of the deployed campaign
     * @param _to is the reward receiver
     * @param _amount is the reward amount
     */
    function rewarded(
        address _campaign,
        address _to,
        uint256 _amount
    )
    external
    onlyAllowedContracts
    {
        emit Rewarded(_campaign, _to, _amount);
    }

    /**
     * @notice Function to emit created event every time campaign is cancelled
     * @param _campaign is the address of the cancelled campaign
     * @param _converter is the address of the converter
     * @param _indexOrAmount is the amount of campaign
     */
    function cancelled(
        address  _campaign,
        address _converter,
        uint256 _indexOrAmount
    )
    external
    onlyAllowedContracts
    {
        emit Cancelled(_campaign, _converter, _indexOrAmount);
    }


    function plasmaOf(
        address me
    )
    public
    view
    returns (address)
    {
        address twoKeyRegistry = getAddressFromTwoKeySingletonRegistry("TwoKeyRegistry");
        address plasma = ITwoKeyReg(twoKeyRegistry).getEthereumToPlasma(me);
        if (plasma != address(0)) {
            return plasma;
        }
        return me;
    }

    /**
     * @notice Function to determine ethereum address of plasma address
     * @param me is the plasma address of the user
     * @return ethereum address
     */
    function ethereumOf(
        address me
    )
    public
    view
    returns (address)
    {
        address twoKeyRegistry = getAddressFromTwoKeySingletonRegistry("TwoKeyRegistry");
        address ethereum = ITwoKeyReg(twoKeyRegistry).getPlasmaToEthereum(me);
        if (ethereum != address(0)) {
            return ethereum;
        }
        return me;
    }

    /**
     * @notice Address to check if an address is maintainer in registry
     * @param _maintainer is the address we're checking this for
     */
    function isAddressMaintainer(
        address _maintainer
    )
    public
    view
    returns (bool)
    {
        address twoKeyMaintainersRegistry = getAddressFromTwoKeySingletonRegistry("TwoKeyMaintainersRegistry");
        bool _isMaintainer = ITwoKeyMaintainersRegistry(twoKeyMaintainersRegistry).onlyMaintainer(_maintainer);
        return _isMaintainer;
    }

    /**
     * @notice In default TwoKeyAdmin will be moderator and his fee percentage per conversion is predefined
     */
    function getTwoKeyDefaultIntegratorFeeFromAdmin()
    public
    view
    returns (uint)
    {
        address twoKeyAdmin = getAddressFromTwoKeySingletonRegistry("TwoKeyAdmin");
        uint integratorFeePercentage = ITwoKeyAdmin(twoKeyAdmin).getDefaultIntegratorFeePercent();
        return integratorFeePercentage;
    }

    /**
     * @notice Function to get default network tax percentage
     */
    function getTwoKeyDefaultNetworkTaxPercent()
    public
    view
    returns (uint)
    {
        address twoKeyAdmin = getAddressFromTwoKeySingletonRegistry("TwoKeyAdmin");
        uint networkTaxPercent = ITwoKeyAdmin(twoKeyAdmin).getDefaultNetworkTaxPercent();
        return networkTaxPercent;
    }
}
