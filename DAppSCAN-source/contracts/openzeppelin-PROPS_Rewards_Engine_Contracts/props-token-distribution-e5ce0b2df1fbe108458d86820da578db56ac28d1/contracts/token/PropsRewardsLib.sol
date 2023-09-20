pragma solidity ^0.4.24;

import "openzeppelin-eth/contracts/math/SafeMath.sol";

/**
 * @title Props Rewards Library
 * @dev Library to manage application and validators and parameters
 **/
library PropsRewardsLib {
    using SafeMath for uint256;
    /*
    *  Events
    */

    /*
    *  Storage
    */

    // The various parameters used by the contract
    enum ParameterName { ApplicationRewardsPercent, ApplicationRewardsMaxVariationPercent, ValidatorMajorityPercent, ValidatorRewardsPercent}
    enum RewardedEntityType { Application, Validator }

    // Represents a parameter current, previous and time of change
    struct Parameter {
        uint256 currentValue;                   // current value in Pphm valid after timestamp
        uint256 previousValue;                  // previous value in Pphm for use before timestamp
        uint256 rewardsDay;                     // timestamp of when the value was updated
    }
    // Represents application details
    struct RewardedEntity {
        bytes32 name;                           // Application name
        address rewardsAddress;                 // address where rewards will be minted to
        address sidechainAddress;               // address used on the sidechain
        bool isInitializedState;                // A way to check if there's something in the map and whether it is already added to the list
        RewardedEntityType entityType;          // Type of rewarded entity
    }

    // Represents validators current and previous lists
    struct RewardedEntityList {
        mapping (address => bool) current;
        mapping (address => bool) previous;
        //SWC-135-Code With No Effects: L43-L44
        address[] currentList;
        address[] previousList;
        uint256 rewardsDay;
    }

    // Represents daily rewards submissions and confirmations
    struct DailyRewards {
        mapping (bytes32 => Submission) submissions;
        bytes32[] submittedRewardsHashes;
        uint256 totalSupply;
        bytes32 lastConfirmedRewardsHash;
        uint256 lastRewardsDay;
    }

    struct Submission {
        mapping (address => bool) validators;
        address[] validatorsList;
        uint256 confirmations;
        uint256 finalized;
        bool isInitializedState;               // A way to check if there's something in the map and whether it is already added to the list
    }


    // represent the storage structures
    struct Data {
        // applications data
        mapping (address => RewardedEntity) applications;
        address[] applicationsList;
        // validators data
        mapping (address => RewardedEntity) validators;
        address[] validatorsList;
        // adjustable parameters data
        mapping (uint256 => Parameter) parameters; // uint256 is the parameter enum index
        // the participating validators
        RewardedEntityList selectedValidators;
        // the participating applications
        RewardedEntityList selectedApplications;
        // daily rewards submission data
        DailyRewards dailyRewards;
        uint256 minSecondsBetweenDays;
        uint256 rewardsStartTimestamp;
        uint256 maxTotalSupply;
        uint256 lastRewardsDay;
    }
    /*
    *  Modifiers
    */
    modifier onlyOneRewardsHashPerValidator(Data storage _self, bytes32 _rewardsHash) {
        require(
            !_self.dailyRewards.submissions[_rewardsHash].validators[msg.sender],
            "Must be one submission per validator"
        );
         _;
    }

    modifier onlyExistingApplications(Data storage _self, address[] _entities) {
        for (uint256 i = 0; i < _entities.length; i++) {
            require(
                _self.applications[_entities[i]].isInitializedState,
                "Application must exist"
            );
        }
        _;
    }

    modifier onlyExistingValidators(Data storage _self, address[] _entities) {
        for (uint256 i = 0; i < _entities.length; i++) {
            require(
                _self.validators[_entities[i]].isInitializedState,
                "Validator must exist"
            );
        }
        _;
    }

    modifier onlySelectedValidators(Data storage _self, uint256 _rewardsDay) {
        if (_getSelectedRewardedEntityListType(_self.selectedValidators, _rewardsDay) == 0) {
            require (
                _self.selectedValidators.current[msg.sender],
                "Must be a current selected validator"
            );
        } else {
            require (
                _self.selectedValidators.previous[msg.sender],
                "Must be a previous selected validator"
            );
        }
        _;
    }

    modifier onlyValidRewardsDay(Data storage _self, uint256 _rewardsDay) {
        require(
            _currentRewardsDay(_self) > _rewardsDay && _rewardsDay > _self.lastRewardsDay,
            "Must be for a previous day but after the last rewards day"
        );
         _;
    }

    modifier onlyValidFutureRewardsDay(Data storage _self, uint256 _rewardsDay) {
        require(
            _rewardsDay >= _currentRewardsDay(_self),
            "Must be future rewardsDay"
        );
         _;
    }

    modifier onlyValidAddresses(address _rewardsAddress, address _sidechainAddress) {
        require(
            _rewardsAddress != address(0) &&
            _sidechainAddress != address(0),
            "Must have valid rewards and sidechain addresses"
        );
        _;
    }

    /**
    * @dev The function is called by validators with the calculation of the daily rewards
    * @param _self Data pointer to storage
    * @param _rewardsDay uint256 the rewards day
    * @param _rewardsHash bytes32 hash of the rewards data
    * @param _allValidators bool should the calculation be based on all the validators or just those which submitted
    */
    function calculateValidatorRewards(
        Data storage _self,
        uint256 _rewardsDay,
        bytes32 _rewardsHash,
        bool _allValidators
    )
        public
        view
        returns (uint256)
    {
        uint256 numOfValidators;
        if (_self.dailyRewards.submissions[_rewardsHash].finalized == 1)
        {
            if (_allValidators) {
                numOfValidators = _requiredValidatorsForValidatorsRewards(_self, _rewardsDay);
                if (numOfValidators > _self.dailyRewards.submissions[_rewardsHash].confirmations) return 0;
            } else {
                numOfValidators = _self.dailyRewards.submissions[_rewardsHash].confirmations;
            }
            uint256 rewardsPerValidator = _getValidatorRewardsDailyAmountPerValidator(_self, _rewardsDay, numOfValidators);
            return rewardsPerValidator;
        }
        return 0;
    }

    /**
    * @dev The function is called by validators with the calculation of the daily rewards
    * @param _self Data pointer to storage
    * @param _rewardsDay uint256 the rewards day
    * @param _rewardsHash bytes32 hash of the rewards data
    * @param _applications address[] array of application addresses getting the daily reward
    * @param _amounts uint256[] array of amounts each app should get
    * @param _currentTotalSupply uint256 current total supply
    */
    function calculateApplicationRewards(
        Data storage _self,
        uint256 _rewardsDay,
        bytes32 _rewardsHash,
        address[] _applications,
        uint256[] _amounts,
        uint256 _currentTotalSupply
    )
        public
        onlyValidRewardsDay(_self, _rewardsDay)
        onlyOneRewardsHashPerValidator(_self, _rewardsHash)
        onlySelectedValidators(_self, _rewardsDay)
        returns (uint256)
    {
        require(
                _rewardsHashIsValid(_rewardsDay, _rewardsHash, _applications, _amounts),
                "Rewards Hash is invalid"
        );
        if (!_self.dailyRewards.submissions[_rewardsHash].isInitializedState) {
            _self.dailyRewards.submissions[_rewardsHash].isInitializedState = true;
            _self.dailyRewards.submittedRewardsHashes.push(_rewardsHash);
        }
        _self.dailyRewards.submissions[_rewardsHash].validators[msg.sender] = true;
        _self.dailyRewards.submissions[_rewardsHash].validatorsList.push(msg.sender);
        _self.dailyRewards.submissions[_rewardsHash].confirmations++;

        if (_self.dailyRewards.submissions[_rewardsHash].confirmations == _requiredValidatorsForAppRewards(_self, _rewardsDay)) {
            uint256 sum = _validateSubmittedData(_self, _applications, _amounts);
            require(
                sum <= _getMaxAppRewardsDailyAmount(_self, _rewardsDay, _currentTotalSupply),
                "Rewards data is invalid - exceed daily variation"
            );
            _finalizeDailyApplicationRewards(_self, _rewardsDay, _rewardsHash, _currentTotalSupply);
            return sum;
        }
        return 0;
    }

    /**
    * @dev Finalizes the state, rewards Hash, total supply and block timestamp for the day
    * @param _self Data pointer to storage
    * @param _rewardsDay uint256 the rewards day
    * @param _rewardsHash bytes32 the daily rewards hash
    * @param _currentTotalSupply uint256 the current total supply
    */
    function _finalizeDailyApplicationRewards(Data storage _self, uint256 _rewardsDay, bytes32 _rewardsHash, uint256 _currentTotalSupply)
        public
        returns (bool)
    {
        _self.dailyRewards.totalSupply = _currentTotalSupply;
        _self.dailyRewards.lastConfirmedRewardsHash = _rewardsHash;
        _self.dailyRewards.lastRewardsDay = _rewardsDay;
        _self.dailyRewards.submissions[_rewardsHash].finalized = 1;
        return true;
    }

    /**
    * @dev Get parameter's value
    * @param _self Data pointer to storage
    * @param _name ParameterName name of the parameter
    * @param _rewardsDay uint256 the rewards day
    */
    function getParameterValue(
        Data storage _self,
        ParameterName _name,
        uint256 _rewardsDay
    )
        public
        view
        returns (uint256)
    {
        if (_rewardsDay >= _self.parameters[uint256(_name)].rewardsDay) {
            return _self.parameters[uint256(_name)].currentValue;
        } else {
            return _self.parameters[uint256(_name)].previousValue;
        }
    }

    /**
    * @dev Allows the controller/owner to update rewards parameters
    * @param _self Data pointer to storage
    * @param _name ParameterName name of the parameter
    * @param _value uint256 new value for the parameter
    * @param _rewardsDay uint256 the rewards day
    */
    function updateParameter(
        Data storage _self,
        ParameterName _name,
        uint256 _value,
        uint256 _rewardsDay
    )
        public
        onlyValidFutureRewardsDay(_self, _rewardsDay)
        returns (bool)
    {
        if (_rewardsDay <= _self.parameters[uint256(_name)].rewardsDay) {
           _self.parameters[uint256(_name)].currentValue = _value;
           _self.parameters[uint256(_name)].rewardsDay = _rewardsDay;
        } else {
            _self.parameters[uint256(_name)].previousValue = _self.parameters[uint256(_name)].currentValue;
            _self.parameters[uint256(_name)].currentValue = _value;
           _self.parameters[uint256(_name)].rewardsDay = _rewardsDay;
        }
        return true;
    }

    /**
    * @dev Allows an application to add/update its details
    * @param _self Data pointer to storage
    * @param _entityType RewardedEntityType either application (0) or validator (1)
    * @param _name bytes32 name of the app
    * @param _rewardsAddress address an address for the app to receive the rewards
    * @param _sidechainAddress address the address used for using the sidechain
    */
    function updateEntity(
        Data storage _self,
        RewardedEntityType _entityType,
        bytes32 _name,
        address _rewardsAddress,
        address _sidechainAddress
    )
        public
        onlyValidAddresses(_rewardsAddress, _sidechainAddress)
        returns (bool)
    {
        if (_entityType == RewardedEntityType.Application) {
            updateApplication(_self, _name, _rewardsAddress, _sidechainAddress);
        } else {
            updateValidator(_self, _name, _rewardsAddress, _sidechainAddress);
        }
        return true;
    }

    /**
    * @dev Allows an application to add/update its details
    * @param _self Data pointer to storage
    * @param _name bytes32 name of the app
    * @param _rewardsAddress address an address for the app to receive the rewards
    * @param _sidechainAddress address the address used for using the sidechain
    */
    function updateApplication(
        Data storage _self,
        bytes32 _name,
        address _rewardsAddress,
        address _sidechainAddress
    )
        public
        returns (uint256)
    {
        _self.applications[msg.sender].name = _name;
        _self.applications[msg.sender].rewardsAddress = _rewardsAddress;
        _self.applications[msg.sender].sidechainAddress = _sidechainAddress;
        if (!_self.applications[msg.sender].isInitializedState) {
            _self.applicationsList.push(msg.sender);
            _self.applications[msg.sender].isInitializedState = true;
            _self.applications[msg.sender].entityType = RewardedEntityType.Application;
        }
        return uint256(RewardedEntityType.Application);
    }

    /**
    * @dev Allows a validator to add/update its details
    * @param _self Data pointer to storage
    * @param _name bytes32 name of the validator
    * @param _rewardsAddress address an address for the validator to receive the rewards
    * @param _sidechainAddress address the address used for using the sidechain
    */
    function updateValidator(
        Data storage _self,
        bytes32 _name,
        address _rewardsAddress,
        address _sidechainAddress
    )
        public
        returns (uint256)
    {
        _self.validators[msg.sender].name = _name;
        _self.validators[msg.sender].rewardsAddress = _rewardsAddress;
        _self.validators[msg.sender].sidechainAddress = _sidechainAddress;
        if (!_self.validators[msg.sender].isInitializedState) {
            _self.validatorsList.push(msg.sender);
            _self.validators[msg.sender].isInitializedState = true;
            _self.validators[msg.sender].entityType = RewardedEntityType.Validator;
        }
        return uint256(RewardedEntityType.Validator);
    }

    /**
    * @dev Set new validators list
    * @param _self Data pointer to storage
    * @param _rewardsDay uint256 the rewards day from which the list should be active
    * @param _validators address[] array of validators
    */
    function setValidators(
        Data storage _self,
        uint256 _rewardsDay,
        address[] _validators
    )
        public
        onlyValidFutureRewardsDay(_self, _rewardsDay)
        onlyExistingValidators(_self, _validators)
        returns (bool)
    {
        // no need to update the previous if its' the first time or second update in the same day
        if (_rewardsDay > _self.selectedValidators.rewardsDay && _self.selectedValidators.currentList.length > 0)
            _updatePreviousEntityList(_self.selectedValidators);

        _updateCurrentEntityList(_self.selectedValidators, _validators);
        _self.selectedValidators.rewardsDay = _rewardsDay;
        return true;
    }

   /**
    * @dev Set new applications list
    * @param _self Data pointer to storage
    * @param _rewardsDay uint256 the rewards day from which the list should be active
    * @param _applications address[] array of applications
    */
    function setApplications(
        Data storage _self,
        uint256 _rewardsDay,
        address[] _applications
    )
        public
        onlyValidFutureRewardsDay(_self, _rewardsDay)
        onlyExistingApplications(_self, _applications)
        returns (bool)
    {

        if (_rewardsDay > _self.selectedApplications.rewardsDay && _self.selectedApplications.currentList.length > 0)
                _updatePreviousEntityList(_self.selectedApplications);
        _updateCurrentEntityList(_self.selectedApplications, _applications);
        _self.selectedApplications.rewardsDay = _rewardsDay;
        return true;
    }

    /**
    * @dev Get applications or validators list
    * @param _self Data pointer to storage
    * @param _entityType RewardedEntityType either application (0) or validator (1)
    * @param _rewardsDay uint256 the rewards day to determine which list to get
    */
    function getEntities(
        Data storage _self,
        RewardedEntityType _entityType,
        uint256 _rewardsDay
    )
        public
        view
        returns (address[])
    {
        if (_entityType == RewardedEntityType.Application) {
            if (_getSelectedRewardedEntityListType(_self.selectedApplications, _rewardsDay) == 0) {
                return _self.selectedApplications.currentList;
            } else {
                return _self.selectedApplications.previousList;
            }
        } else {
            if (_getSelectedRewardedEntityListType(_self.selectedValidators, _rewardsDay) == 0) {
                return _self.selectedValidators.currentList;
            } else {
                return _self.selectedValidators.previousList;
            }
        }
    }

    /**
    * @dev Get which entity list to use. Current = 0, previous = 1
    * @param _rewardedEntitylist RewardedEntityList pointer to storage
    * @param _rewardsDay uint256 the rewards day to determine which list to get
    */
    function _getSelectedRewardedEntityListType(RewardedEntityList _rewardedEntitylist, uint256 _rewardsDay)
        internal
        pure
        returns (uint256)
    {
        if (_rewardsDay >= _rewardedEntitylist.rewardsDay) {
            return 0;
        } else {
            return 1;
        }
    }

    /**
    * @dev Checks how many validators are needed for app rewards
    * @param _self Data pointer to storage
    * @param _rewardsDay uint256 the rewards day
    * @param _currentTotalSupply uint256 current total supply
    */
    function _getMaxAppRewardsDailyAmount(
        Data storage _self,
        uint256 _rewardsDay,
        uint256 _currentTotalSupply
    )
        public
        view
        returns (uint256)
    {
        return ((_self.maxTotalSupply.sub(_currentTotalSupply)).mul(
        getParameterValue(_self, ParameterName.ApplicationRewardsPercent, _rewardsDay)).mul(
        getParameterValue(_self, ParameterName.ApplicationRewardsMaxVariationPercent, _rewardsDay))).div(1e16);
    }


    /**
    * @dev Checks how many validators are needed for app rewards
    * @param _self Data pointer to storage
    * @param _rewardsDay uint256 the rewards day
    * @param _numOfValidators uint256 number of validators
    */
    function _getValidatorRewardsDailyAmountPerValidator(
        Data storage _self,
        uint256 _rewardsDay,
        uint256 _numOfValidators
    )
        public
        view
        returns (uint256)
    {
        return (((_self.maxTotalSupply.sub(_self.dailyRewards.totalSupply)).mul(
        getParameterValue(_self, ParameterName.ValidatorRewardsPercent, _rewardsDay))).div(1e8)).div(_numOfValidators);
    }

    /**
    * @dev Checks if app daily rewards amount is valid
    * @param _self Data pointer to storage
    * @param _applications address[] array of application addresses getting the daily rewards
    * @param _amounts uint256[] array of amounts each app should get
    */
    function _validateSubmittedData(
        Data storage _self,
        address[] _applications,
        uint256[] _amounts
    )
        public
        view
        returns (uint256)
    {
        uint256 sum;
        bool valid = true;
        for (uint256 i = 0; i < _amounts.length; i++) {
            sum = sum.add(_amounts[i]);
            if (!_self.applications[_applications[i]].isInitializedState) valid = false;
        }
        require(
                sum > 0 && valid,
                "Sum zero or none existing app submitted"
        );
        return sum;
    }

    /**
    * @dev Checks if submitted data matches rewards hash
    * @param _rewardsDay uint256 the rewards day
    * @param _rewardsHash bytes32 hash of the rewards data
    * @param _applications address[] array of application addresses getting the daily rewards
    * @param _amounts uint256[] array of amounts each app should get
    */
    function _rewardsHashIsValid(
        uint256 _rewardsDay,
        bytes32 _rewardsHash,
        address[] _applications,
        uint256[] _amounts
    )
        public
        pure
        returns (bool)
    {
        return
            _applications.length > 0 &&
            _applications.length == _amounts.length &&
            keccak256(abi.encodePacked(_rewardsDay, _applications.length, _amounts.length, _applications, _amounts)) == _rewardsHash;
    }

    /**
    * @dev Checks how many validators are needed for app rewards
    * @param _self Data pointer to storage
    * @param _rewardsDay uint256 the rewards day
    */
    function _requiredValidatorsForValidatorsRewards(Data storage _self, uint256 _rewardsDay)
        public
        view
        returns (uint256)
    {
        if (_getSelectedRewardedEntityListType(_self.selectedValidators, _rewardsDay) == 0) {
            return _self.selectedValidators.currentList.length;
        } else {
            return _self.selectedValidators.previousList.length;
        }
    }

    /**
    * @dev Checks how many validators are needed for app rewards
    * @param _self Data pointer to storage
    * @param _rewardsDay uint256 the rewards day
    */
    function _requiredValidatorsForAppRewards(Data storage _self, uint256 _rewardsDay)
        public
        view
        returns (uint256)
    {
        if (_getSelectedRewardedEntityListType(_self.selectedValidators, _rewardsDay) == 0) {
            return ((_self.selectedValidators.currentList.length.mul(getParameterValue(_self, ParameterName.ValidatorMajorityPercent, _rewardsDay))).div(1e8)).add(1);
        } else {
            return ((_self.selectedValidators.previousList.length.mul(getParameterValue(_self, ParameterName.ValidatorMajorityPercent, _rewardsDay))).div(1e8)).add(1);
        }
    }

    /**
    * @dev Get rewards day from block.timestamp
    * @param _self Data pointer to storage
    */
    function _currentRewardsDay(Data storage _self)
        public
        view
        returns (uint256)
    {
        //the the start time - floor timestamp to previous midnight divided by seconds in a day will give the rewards day number
       if (_self.minSecondsBetweenDays > 0) {
            return (block.timestamp.sub(_self.rewardsStartTimestamp)).div(_self.minSecondsBetweenDays).add(1);
        } else {
            return 0;
        }
    }

    /**
    * @dev Update current daily applications list.
    * If new, push.
    * If same size, replace
    * If different size, delete, and then push.
    * @param _rewardedEntitylist RewardedEntityList pointer to storage
    * @param _entities address[] array of entities
    */
    //_updateCurrentEntityList(_rewardedEntitylist, _entities,_rewardedEntityType),
    function _updateCurrentEntityList(
        RewardedEntityList storage _rewardedEntitylist,
        address[] _entities
    )
        internal
        returns (bool)
    {
        bool emptyCurrentList = _rewardedEntitylist.currentList.length == 0;
        if (!emptyCurrentList && _rewardedEntitylist.currentList.length != _entities.length) {
            _deleteCurrentEntityList(_rewardedEntitylist);
            emptyCurrentList = true;
        }

        for (uint256 i = 0; i < _entities.length; i++) {
            if (emptyCurrentList) {
                _rewardedEntitylist.currentList.push(_entities[i]);
            } else {
                _rewardedEntitylist.currentList[i] = _entities[i];
            }
            _rewardedEntitylist.current[_entities[i]] = true;
        }
        return true;
    }

    /**
    * @dev Update previous daily list
    * @param _rewardedEntitylist RewardedEntityList pointer to storage
    */
    function _updatePreviousEntityList(RewardedEntityList storage _rewardedEntitylist)
        internal
        returns (bool)
    {
        bool emptyPreviousList = _rewardedEntitylist.previousList.length == 0;
        if (
            !emptyPreviousList &&
            _rewardedEntitylist.previousList.length != _rewardedEntitylist.currentList.length
        ) {
            _deletePreviousEntityList(_rewardedEntitylist);
            emptyPreviousList = true;
        }
        for (uint256 i = 0; i < _rewardedEntitylist.currentList.length; i++) {
            if (emptyPreviousList) {
                _rewardedEntitylist.previousList.push(_rewardedEntitylist.currentList[i]);
            } else {
                _rewardedEntitylist.previousList[i] = _rewardedEntitylist.currentList[i];
            }
            _rewardedEntitylist.previous[_rewardedEntitylist.currentList[i]] = true;
        }
        return true;
    }

    /**
    * @dev Delete existing values from the current list
    * @param _rewardedEntitylist RewardedEntityList pointer to storage
    */
    function _deleteCurrentEntityList(RewardedEntityList storage _rewardedEntitylist)
        internal
        returns (bool)
    {
        for (uint256 i = 0; i < _rewardedEntitylist.currentList.length ; i++) {
             delete _rewardedEntitylist.current[_rewardedEntitylist.currentList[i]];
        }
        delete  _rewardedEntitylist.currentList;
        return true;
    }

    /**
    * @dev Delete existing values from the previous applications list
    * @param _rewardedEntitylist RewardedEntityList pointer to storage
    */
    function _deletePreviousEntityList(RewardedEntityList storage _rewardedEntitylist)
        internal
        returns (bool)
    {
        for (uint256 i = 0; i < _rewardedEntitylist.previousList.length ; i++) {
            delete _rewardedEntitylist.previous[_rewardedEntitylist.previousList[i]];
        }
        delete _rewardedEntitylist.previousList;
        return true;
    }

    /**
    * @dev Deletes rewards day submission data
    * @param _self Data pointer to storage
    */
    function _resetDailyRewards(
        Data storage _self
    )
        public
        returns (bool)
    {
         _self.lastRewardsDay = _self.dailyRewards.lastRewardsDay;
        bytes32[] memory rewardsHashes = _self.dailyRewards.submittedRewardsHashes;
        for (uint256 i = 0; i < rewardsHashes.length; i++) {
            for (uint256 j = 0; j < _self.dailyRewards.submissions[rewardsHashes[i]].validatorsList.length; j++) {
                delete(
                    _self.dailyRewards.submissions[rewardsHashes[i]].validators[_self.dailyRewards.submissions[rewardsHashes[i]].validatorsList[j]]
                );
            }
            delete _self.dailyRewards.submissions[rewardsHashes[i]].validatorsList;
            _self.dailyRewards.submissions[rewardsHashes[i]].confirmations = 0;
            _self.dailyRewards.submissions[rewardsHashes[i]].finalized = 0;
            _self.dailyRewards.submissions[rewardsHashes[i]].isInitializedState = false;
        }
        delete _self.dailyRewards.submittedRewardsHashes;
    }
}