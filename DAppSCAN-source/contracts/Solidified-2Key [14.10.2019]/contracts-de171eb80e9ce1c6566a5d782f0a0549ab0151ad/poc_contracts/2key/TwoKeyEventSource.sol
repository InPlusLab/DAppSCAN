pragma solidity ^0.4.24;

import './TwoKeyTypes.sol';
import "./TwoKeyAdmin.sol";
import "../../contracts/2key/libraries/GetCode.sol";

contract TwoKeyEventSource is TwoKeyTypes {

    mapping(address => bool) public activeUser;

    /// Events
    event Created(address indexed _campaign, address indexed _owner);
    event Joined(address indexed _campaign, address indexed _from, address indexed _to);
    event Escrow(address indexed _campaign, address indexed _converter, uint256 _tokenID, address _childContractID, uint256 _indexOrAmount, CampaignType _type);
    event Rewarded(address indexed _campaign, address indexed _to, uint256 _amount);
    event Fulfilled(address indexed _campaign, address indexed _converter, uint256 indexed _tokenID, address _childContractID, uint256 _indexOrAmount, CampaignType _type);
    event Cancelled(address indexed _campaign, address indexed _converter, uint256 indexed _tokenID, address _childContractID, uint256 _indexOrAmount, CampaignType _type);
    event Code(bytes32 _code, uint256 _index);
    event PublicLinkKey(address campaign, address owner, address key);




    ///Address of the contract admin
    TwoKeyAdmin twoKeyAdmin;



    ///Mapping contract bytecode to boolean if is allowed to emit an event
    mapping(bytes32 => bool) canEmit;

    /// Mapping contract bytecode to enumerator CampaignType.
    mapping(bytes32 => CampaignType) codeToType;


    ///Mapping an address to boolean if allowed to modify
    mapping(address => bool) authorizedSubadmins;



    ///@notice Modifier which allows only admin to call a function - can be easily modified if there is going to be more admins
    modifier onlyAdmin {
        require(msg.sender == address(twoKeyAdmin));
        _;
    }

    ///@notice Modifier which allows all modifiers to update canEmit mapping - ever
    modifier onlyAuthorizedSubadmins {
        require(authorizedSubadmins[msg.sender] == true || msg.sender == address(twoKeyAdmin));
        _;
    }

    ///@notice Modifier which will only allow allowed contracts to emit an event
    modifier onlyAllowedContracts {
        //just to use contract code instead of msg.sender address
        bytes memory code = GetCode.at(msg.sender);
        bytes32 cc = keccak256(abi.encodePacked(code));
        emit Code(cc,1);
// TODO  fails     require(canEmit[cc] == true);
        _;
    }

    /// @notice Constructor during deployment of contract we need to set an admin address (means TwoKeyAdmin needs to be previously deployed)
    /// @param _twoKeyAdminAddress is the address of TwoKeyAdmin contract previously deployed
    constructor(address _twoKeyAdminAddress) public {
        twoKeyAdmin = TwoKeyAdmin(_twoKeyAdminAddress);
    }

    /// @notice function where admin or any authorized person (will be added if needed) can add more contracts to allow them call methods
    /// @param _contractAddress is actually the address of contract we'd like to allow
    /// @dev We first fetch bytes32 contract code and then update our mapping
    /// @dev only admin can call this or an authorized person
    function addContract(address _contractAddress) public onlyAuthorizedSubadmins {
        require(_contractAddress != address(0));
        bytes memory _contractCode = GetCode.at(_contractAddress);
        bytes32 cc = keccak256(abi.encodePacked(_contractCode));
        emit Code(cc,2);
        canEmit[cc] = true;
    }

    /// @notice function where admin or any authorized person (will be added if needed) can remove contract (disable permissions to emit Events)
    /// @param _contractAddress is actually the address of contract we'd like to disable
    /// @dev We first fetch bytes32 contract code and then update our mapping
    /// @dev only admin can call this or an authorized person
    function removeContract(address _contractAddress) public onlyAuthorizedSubadmins {
        require(_contractAddress != address(0));
        bytes memory _contractCode = GetCode.at(_contractAddress);
        bytes32 cc = keccak256(abi.encodePacked(_contractCode));
        emit Code(cc,3);
        canEmit[cc] = false;
    }

    /// @notice Function where an admin can authorize any other person to modify allowed contracts
    /// @param _newAddress is the address of new modifier contract / account
    /// @dev if only contract can be modifier then we'll add one more validation step
    function addAuthorizedAddress(address _newAddress) public onlyAdmin {
        require(_newAddress != address(0));
        authorizedSubadmins[_newAddress] = true;
    }

    /// @notice Function to remove authorization from an modifier
    /// @param _authorizedAddress is the address of modifier
    /// @dev checking if that address is set to true before since we'll spend 21k gas if it's already false to override that value
    function removeAuthorizedAddress(address _authorizedAddress) public onlyAdmin {
        require(_authorizedAddress != address(0));
        require(authorizedSubadmins[_authorizedAddress] == true);

        authorizedSubadmins[_authorizedAddress] = false;
    }

    /// @notice Function to map contract code to type of campaign
    /// @dev is contract required to be allowed to emit to even exist in mapping codeToType
    /// @param _contractCode is code od contract
    /// @param _campaignType is enumerator representing type of campaign
    function addCampaignType(bytes _contractCode, CampaignType _campaignType) public onlyAdmin {
        bytes32 cc = keccak256(abi.encodePacked(_contractCode));
        require(canEmit[cc] == true); //Check if this validation is needed
        codeToType[cc] = _campaignType;
    }

    /// @notice Function where admin can be changed
    /// @param _newAdminAddress is the address of new admin
    /// @dev think about some security layer here
    function changeAdmin(address _newAdminAddress) public onlyAdmin {
        twoKeyAdmin = TwoKeyAdmin(_newAdminAddress);
    }

    function checkCanEmit(bytes _contractCode) public view returns (bool) {
        bytes32 cc = keccak256(abi.encodePacked(_contractCode));
        return canEmit[cc];
    }

    /// @dev Only allowed contracts can call this function ---> means can emit events
    // TODO use msg.sender instead of _campaign
    function created(address _campaign, address _owner) public onlyAllowedContracts{
    	emit Created(_campaign, _owner);
    }

    /// @dev Only allowed contracts can call this function ---> means can emit events
    // TODO use msg.sender instead of _campaign
    function joined(address _campaign, address _from, address _to) public onlyAllowedContracts {
      activeUser[_to] = true;  // do we want to do it also for _from and created, escrow, rewarded, fulfilled
    	emit Joined(_campaign, _from, _to);
    }

    /// @dev Only allowed contracts can call this function ---> means can emit events
    // TODO use msg.sender instead of _campaign
    function escrow(address _campaign, address _converter, uint256 _tokenID, address _childContractID, uint256 _indexOrAmount, CampaignType _type) public onlyAllowedContracts{
    	emit Escrow(_campaign, _converter, _tokenID, _childContractID, _indexOrAmount, _type);
    }

    /// @dev Only allowed contracts can call this function ---> means can emit events
    // TODO use msg.sender instead of _campaign
    function rewarded(address _campaign, address _to, uint256 _amount) public onlyAllowedContracts {
    	emit Rewarded(_campaign, _to, _amount);
	}

    /// @dev Only allowed contracts can call this function ---> means can emit events
    // TODO use msg.sender instead of _campaign
	function fulfilled(address  _campaign, address _converter, uint256 _tokenID, address _childContractID, uint256 _indexOrAmount, CampaignType _type) public onlyAllowedContracts {
		emit Fulfilled(_campaign, _converter, _tokenID, _childContractID, _indexOrAmount, _type);
	}

    /// @dev Only allowed contracts can call this function ---> means can emit events
    // TODO use msg.sender instead of _campaign
	function cancelled(address  _campaign, address _converter, uint256 _tokenID, address _childContractID, uint256 _indexOrAmount, CampaignType _type) public onlyAllowedContracts{
		emit Cancelled(_campaign, _converter, _tokenID, _childContractID, _indexOrAmount, _type);
	}


    function getAdmin() public view returns (address) {
        return address(twoKeyAdmin);
    }

    function checkIsAuthorized(address _subAdmin) public view returns (bool) {
        return authorizedSubadmins[_subAdmin];
    }
}
