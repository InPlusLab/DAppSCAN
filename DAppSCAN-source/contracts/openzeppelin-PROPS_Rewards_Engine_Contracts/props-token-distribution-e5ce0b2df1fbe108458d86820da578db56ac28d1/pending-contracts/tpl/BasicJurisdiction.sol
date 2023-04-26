pragma solidity ^0.4.25;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/lifecycle/Pausable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./AttributeRegistryInterface.sol";
import "./BasicJurisdictionInterface.sol";


/**
 * @title A basic TPL jurisdiction for assigning attributes to addresses.
 */
contract BasicJurisdiction is Ownable, Pausable, AttributeRegistryInterface, BasicJurisdictionInterface {
  using SafeMath for uint256;

  // validators are entities who can add or authorize addition of new attributes
  struct Validator {
    bool exists;
    uint256 index; // NOTE: consider use of uint248 to pack index with exists
    string description;
  }

  // attributes are properties that validators associate with specific addresses
  struct IssuedAttribute {
    bool exists;
    address validator;
    uint256 value;
  }

  // attributes also have associated type - metadata common to each attribute
  struct AttributeType {
    bool exists;
    uint256 index;  // NOTE: consider use of uint248 to pack index with exists
    string description;
    mapping(address => bool) approvedValidators;
  }

  // top-level information about attribute types is held in a mapping of structs
  mapping(uint256 => AttributeType) private _attributeTypes;

  // the jurisdiction retains a mapping of addresses with assigned attributes
  mapping(address => mapping(uint256 => IssuedAttribute)) private _issuedAttributes;

  // there is also a mapping to identify all approved validators and their keys
  mapping(address => Validator) private _validators;

  // once attribute types are assigned to an ID, they cannot be modified
  mapping(uint256 => bytes32) private _attributeTypeHashes;

  // attribute approvals by validator are held in a mapping
  mapping(address => uint256[]) private _validatorApprovals;

   // attribute approval index by validator is tracked as well
  mapping(address => mapping(uint256 => uint256)) private _validatorApprovalsIndex;

  // IDs for all supplied attributes are held in an array (enables enumeration)
  uint256[] private _attributeIDs;

  // addresses for all designated validators are also held in an array
  address[] private _validatorAccounts;

  /**
  * @notice Add an attribute type with ID `ID` and description `description` to
  * the jurisdiction.
  * @param ID uint256 The ID of the attribute type to add.
  * @param description string A description of the attribute type.
  * @dev Once an attribute type is added with a given ID, the description of the
  * attribute type cannot be changed, even if the attribute type is removed and
  * added back later.
  */
  function addAttributeType(
    uint256 ID,
    string description
  ) external onlyOwner whenNotPaused {
    // prevent existing attributes with the same id from being overwritten
    require(
      isAttributeType(ID) == false,
      "an attribute type with the provided ID already exists"
    );

    // calculate a hash of the attribute type based on the type's properties
    bytes32 hash = keccak256(
      abi.encodePacked(
        ID, false, description
      )
    );

    // store hash if attribute type is the first one registered with provided ID
    if (_attributeTypeHashes[ID] == bytes32(0)) {
      _attributeTypeHashes[ID] = hash;
    }

    // prevent addition if different attribute type with the same ID has existed
    require(
      hash == _attributeTypeHashes[ID],
      "attribute type properties must match initial properties assigned to ID"
    );

    // set the attribute mapping, assigning the index as the end of attributeID
    _attributeTypes[ID] = AttributeType({
      exists: true,
      index: _attributeIDs.length,
      description: description
      // NOTE: no approvedValidators variable declaration - must be added later
    });
    
    // add the attribute type id to the end of the attributeID array
    _attributeIDs.push(ID);

    // log the addition of the attribute type
    emit AttributeTypeAdded(ID, description);
  }

  /**
  * @notice Remove the attribute type with ID `ID` from the jurisdiction.
  * @param ID uint256 The ID of the attribute type to remove.
  * @dev All issued attributes of the given type will become invalid upon
  * removal, but will become valid again if the attribute is reinstated.
  */
  function removeAttributeType(uint256 ID) external onlyOwner whenNotPaused {
    // if the attribute id does not exist, there is nothing to remove
    require(
      isAttributeType(ID),
      "unable to remove, no attribute type with the provided ID"
    );

    // get the attribute ID at the last index of the array
    uint256 lastAttributeID = _attributeIDs[_attributeIDs.length.sub(1)];

    // set the attributeID at attribute-to-delete.index to the last attribute ID
    _attributeIDs[_attributeTypes[ID].index] = lastAttributeID;

    // update the index of the attribute type that was moved
    _attributeTypes[lastAttributeID].index = _attributeTypes[ID].index;
    
    // remove the (now duplicate) attribute ID at the end by trimming the array
    _attributeIDs.length--;

    // delete the attribute type's record from the mapping
    delete _attributeTypes[ID];

    // log the removal of the attribute type
    emit AttributeTypeRemoved(ID);
  }

  /**
  * @notice Add account `validator` as a validator with a description
  * `description` who can be approved to set attributes of specific types.
  * @param validator address The account to assign as the validator.
  * @param description string A description of the validator.
  * @dev Note that the jurisdiction can add iteslf as a validator if desired.
  */
  function addValidator(
    address validator,
    string description
  ) external onlyOwner whenNotPaused {
    // check that an empty address was not provided by mistake
    require(validator != address(0), "must supply a valid address");

    // prevent existing validators from being overwritten
    require(
      isValidator(validator) == false,
      "a validator with the provided address already exists"
    );
    
    // create a record for the validator
    _validators[validator] = Validator({
      exists: true,
      index: _validatorAccounts.length,
      description: description
    });

    // add the validator to the end of the _validatorAccounts array
    _validatorAccounts.push(validator);
    
    // log the addition of the new validator
    emit ValidatorAdded(validator, description);
  }

  /**
  * @notice Remove the validator at address `validator` from the jurisdiction.
  * @param validator address The account of the validator to remove.
  * @dev Any attributes issued by the validator will become invalid upon their
  * removal. If the validator is reinstated, those attributes will become valid
  * again. Any approvals to issue attributes of a given type will need to be
  * set from scratch in the event a validator is reinstated.
  */
  function removeValidator(address validator) external onlyOwner whenNotPaused {
    // check that a validator exists at the provided address
    require(
      isValidator(validator),
      "unable to remove, no validator located at the provided address"
    );

    // first, start removing validator approvals until gas is exhausted
    while (_validatorApprovals[validator].length > 0 && gasleft() > 25000) {
      // locate the index of last attribute ID in the validator approval group
      uint256 lastIndex = _validatorApprovals[validator].length.sub(1);

      // locate the validator approval to be removed
      uint256 targetApproval = _validatorApprovals[validator][lastIndex];

      // remove the record of the approval from the associated attribute type
      delete _attributeTypes[targetApproval].approvedValidators[validator];

      // remove the record of the index of the approval
      delete _validatorApprovalsIndex[validator][targetApproval];

      // drop the last attribute ID from the validator approval group
      _validatorApprovals[validator].length--;
    }

    // require that all approvals were successfully removed
    require(
      _validatorApprovals[validator].length == 0,
      "Cannot remove validator - first remove any existing validator approvals"
    );

    // get the validator address at the last index of the array
    address lastAccount = _validatorAccounts[_validatorAccounts.length.sub(1)];

    // set the address at validator-to-delete.index to last validator address
    _validatorAccounts[_validators[validator].index] = lastAccount;

    // update the index of the attribute type that was moved
    _validators[lastAccount].index = _validators[validator].index;
    
    // remove (duplicate) validator address at the end by trimming the array
    _validatorAccounts.length--;

    // remove the validator record
    delete _validators[validator];

    // log the removal of the validator
    emit ValidatorRemoved(validator);
  }

  /**
  * @notice Approve the validator at address `validator` to issue attributes of
  * the type with ID `attributeTypeID`.
  * @param validator address The account of the validator to approve.
  * @param attributeTypeID uint256 The ID of the approved attribute type.
  */
  function addValidatorApproval(
    address validator,
    uint256 attributeTypeID
  ) external onlyOwner whenNotPaused {
    // check that the attribute is predefined and that the validator exists
    require(
      isValidator(validator) && isAttributeType(attributeTypeID),
      "must specify both a valid attribute and an available validator"
    );

    // check that the validator is not already approved
    require(
      _attributeTypes[attributeTypeID].approvedValidators[validator] == false,
      "validator is already approved on the provided attribute"
    );

    // set the validator approval status on the attribute
    _attributeTypes[attributeTypeID].approvedValidators[validator] = true;

    // add the record of the index of the validator approval to be added
    uint256 index = _validatorApprovals[validator].length;
    _validatorApprovalsIndex[validator][attributeTypeID] = index;

    // include the attribute type in the validator approval mapping
    _validatorApprovals[validator].push(attributeTypeID);

    // log the addition of the validator's attribute type approval
    emit ValidatorApprovalAdded(validator, attributeTypeID);
  }

  /**
  * @notice Deny the validator at address `validator` the ability to continue to
  * issue attributes of the type with ID `attributeTypeID`.
  * @param validator address The account of the validator with removed approval.
  * @param attributeTypeID uint256 The ID of the attribute type to unapprove.
  * @dev Any attributes of the specified type issued by the validator in
  * question will become invalid once the approval is removed. If the approval
  * is reinstated, those attributes will become valid again. The approval will
  * also be removed if the approved validator is removed.
  */
  function removeValidatorApproval(
    address validator,
    uint256 attributeTypeID
  ) external onlyOwner whenNotPaused {
    // check that the attribute is predefined and that the validator exists
    require(
      canValidate(validator, attributeTypeID),
      "unable to remove validator approval, attribute is already unapproved"
    );

    // remove the validator approval status from the attribute
    delete _attributeTypes[attributeTypeID].approvedValidators[validator];

    // locate the index of the last validator approval
    uint256 lastIndex = _validatorApprovals[validator].length.sub(1);

    // locate the last attribute ID in the validator approval group
    uint256 lastAttributeID = _validatorApprovals[validator][lastIndex];

    // locate the index of the validator approval to be removed
    uint256 index = _validatorApprovalsIndex[validator][attributeTypeID];

    // replace the validator approval with the last approval in the array
    _validatorApprovals[validator][index] = lastAttributeID;

    // drop the last attribute ID from the validator approval group
    _validatorApprovals[validator].length--;

    // update the record of the index of the swapped-in approval
    _validatorApprovalsIndex[validator][lastAttributeID] = index;

    // remove the record of the index of the removed approval
    delete _validatorApprovalsIndex[validator][attributeTypeID];
    
    // log the removal of the validator's attribute type approval
    emit ValidatorApprovalRemoved(validator, attributeTypeID);
  }

  /**
  * @notice Issue an attribute of the type with ID `attributeTypeID` and a value
  * of `value` to `account` if `message.caller.address()` is approved validator.
  * @param account address The account to issue the attribute on.
  * @param attributeTypeID uint256 The ID of the attribute type to issue.
  * @param value uint256 An optional value for the issued attribute.
  * @dev Existing attributes of the given type on the address must be removed
  * in order to set a new attribute. Be aware that ownership of the account to
  * which the attribute is assigned may still be transferable - restricting
  * assignment to externally-owned accounts may partially alleviate this issue.
  */
  function issueAttribute(
    address account,
    uint256 attributeTypeID,
    uint256 value
  ) external payable whenNotPaused {
    require(
      msg.value == 0,
      "Basic jurisdictions do not support payments when assigning attributes"
    );

    require(
      canValidate(msg.sender, attributeTypeID),
      "only approved validators may assign attributes of this type"
    );

    require(
      _issuedAttributes[account][attributeTypeID].validator == address(0),
      "duplicate attributes are not supported, remove existing attribute first"
    );

    // store attribute value and amount of ether staked in correct scope
    _issuedAttributes[account][attributeTypeID] = IssuedAttribute({
      exists: true,
      validator: msg.sender,
      value: value
    });

    // log the addition of the attribute
    emit AttributeAdded(msg.sender, account, attributeTypeID, value);
  }

  /**
  * @notice Revoke the attribute of the type with ID `attributeTypeID` from
  * `account` if `message.caller.address()` is the issuing validator.
  * @param account address The account to issue the attribute on.
  * @param attributeTypeID uint256 The ID of the attribute type to issue.
  * @dev Validators may still revoke issued attributes even after they have been
  * removed or had their approval to issue the attribute type removed - this
  * enables them to address any objectionable issuances before being reinstated.
  */
  function revokeAttribute(
    address account,
    uint256 attributeTypeID
  ) external whenNotPaused {
    // ensure that an attribute with the given account and attribute exists
    require(
      _issuedAttributes[account][attributeTypeID].exists,
      "only existing attributes may be removed"
    );

    // determine the assigned validator on the user attribute
    address validator = _issuedAttributes[account][attributeTypeID].validator;
    
    // caller must be either the jurisdiction owner or the assigning validator
    require(
      msg.sender == validator || msg.sender == owner(),
      "only jurisdiction or issuing validators may revoke arbitrary attributes"
    );

    // remove the attribute from the designated user account
    delete _issuedAttributes[account][attributeTypeID];

    // log the removal of the attribute
    emit AttributeRemoved(validator, account, attributeTypeID);
  }  

  /**
   * @notice Check if an attribute of the type with ID `attributeTypeID` has
   * been assigned to the account at `account` and is currently valid.
   * @param account address The account to check for a valid attribute.
   * @param attributeTypeID uint256 The ID of the attribute type to check for.
   * @return True if the attribute is assigned and valid, false otherwise.
   * @dev This function MUST return either true or false - i.e. calling this
   * function MUST NOT cause the caller to revert.
   */
  function hasAttribute(
    address account, 
    uint256 attributeTypeID
  ) external view returns (bool) {
    address validator = _issuedAttributes[account][attributeTypeID].validator;
    return (
      _validators[validator].exists &&        //isValidator(validator)
      _attributeTypes[attributeTypeID].approvedValidators[validator] &&
      _attributeTypes[attributeTypeID].exists //isAttributeType(attributeTypeID)    
    );
  }

  /**
   * @notice Retrieve the value of the attribute of the type with ID
   * `attributeTypeID` on the account at `account`, assuming it is valid.
   * @param account address The account to check for the given attribute value.
   * @param attributeTypeID uint256 The ID of the attribute type to check for.
   * @return The attribute value if the attribute is valid, reverts otherwise.
   * @dev This function MUST revert if a directly preceding or subsequent
   * function call to `hasAttribute` with identical `account` and
   * `attributeTypeID` parameters would return false.
   */
  function getAttributeValue(
    address account,
    uint256 attributeTypeID
  ) external view returns (uint256 value) {
    address validator = _issuedAttributes[account][attributeTypeID].validator;
    require(
      (
        _validators[validator].exists &&
        _attributeTypes[attributeTypeID].approvedValidators[validator] &&
        _attributeTypes[attributeTypeID].exists
      ),
      "could not find an attribute value at the provided address and ID"
    );

    return _issuedAttributes[account][attributeTypeID].value;
  }

  /**
   * @notice Determine if a validator at account `validator` is able to issue
   * attributes of the type with ID `attributeTypeID`.
   * @param validator address The account of the validator.
   * @param attributeTypeID uint256 The ID of the attribute type to check.
   * @return True if the validator can issue attributes of the given type, false
   * otherwise.
   */
  function canIssueAttributeType(
    address validator,
    uint256 attributeTypeID
  ) external view returns (bool) {
    return canValidate(validator, attributeTypeID);
  }

  /**
   * @notice Get a description of the attribute type with ID `attributeTypeID`.
   * @param attributeTypeID uint256 The ID of the attribute type to check for.
   * @return A description of the attribute type.
   */
  function getAttributeTypeDescription(
    uint256 attributeTypeID
  ) external view returns (
    string description
  ) {
    return _attributeTypes[attributeTypeID].description;
  }

  /**
   * @notice Get a description of the validator at account `validator`.
   * @param validator address The account of the validator in question.
   * @return A description of the validator.
   */
  function getValidatorDescription(
    address validator
  ) external view returns (
    string description
  ) {
    return _validators[validator].description;
  }

  /**
   * @notice Find the validator that issued the attribute of the type with ID
   * `attributeTypeID` on the account at `account` and determine if the
   * validator is still valid.
   * @param account address The account that contains the attribute be checked.
   * @param attributeTypeID uint256 The ID of the attribute type in question.
   * @return The validator and the current status of the validator as it
   * pertains to the attribute type in question.
   * @dev if no attribute of the given attribute type exists on the account, the
   * function will return (address(0), false).
   */
  function getAttributeValidator(
    address account,
    uint256 attributeTypeID
  ) external view returns (
    address validator,
    bool isStillValid
  ) {
    address issuer = _issuedAttributes[account][attributeTypeID].validator;
    return (issuer, canValidate(issuer, attributeTypeID));
  }

  /**
   * @notice Count the number of attribute types defined by the registry.
   * @return The number of available attribute types.
   * @dev This function MUST return a positive integer value  - i.e. calling
   * this function MUST NOT cause the caller to revert.
   */
  function countAttributeTypes() external view returns (uint256) {
    return _attributeIDs.length;
  }

  /**
   * @notice Get the ID of the attribute type at index `index`.
   * @param index uint256 The index of the attribute type in question.
   * @return The ID of the attribute type.
   * @dev This function MUST revert if the provided `index` value falls outside
   * of the range of the value returned from a directly preceding or subsequent
   * function call to `countAttributeTypes`. It MUST NOT revert if the provided
   * `index` value falls inside said range.
   */
  function getAttributeTypeID(uint256 index) external view returns (uint256) {
    require(
      index < _attributeIDs.length,
      "provided index is outside of the range of defined attribute type IDs"
    );

    return _attributeIDs[index];
  }

  /**
   * @notice Get the IDs of all available attribute types on the jurisdiction.
   * @return A dynamic array containing all available attribute type IDs.
   */
  function getAttributeTypeIDs() external view returns (uint256[]) {
    return _attributeIDs;
  }

  /**
   * @notice Count the number of validators defined by the jurisdiction.
   * @return The number of defined validators.
   */
  function countValidators() external view returns (uint256) {
    return _validatorAccounts.length;
  }

  /**
   * @notice Get the account of the validator at index `index`.
   * @param index uint256 The index of the validator in question.
   * @return The account of the validator.
   */
  function getValidator(
    uint256 index
  ) external view returns (address) {
    return _validatorAccounts[index];
  }

  /**
   * @notice Get the accounts of all available validators on the jurisdiction.
   * @return A dynamic array containing all available validator accounts.
   */
  function getValidators() external view returns (address[]) {
    return _validatorAccounts;
  }

  /**
   * @notice Determine if the interface ID `interfaceID` is supported (ERC-165)
   * @param interfaceID bytes4 The interface ID in question.
   * @return True if the interface is supported, false otherwise.
   * @dev this function will produce a compiler warning recommending that the
   * visibility be set to pure, but the interface expects a view function.
   * Supported interfaces include ERC-165 (0x01ffc9a7) and the attribute
   * registry interface (0x5f46473f).
   */
  function supportsInterface(bytes4 interfaceID) external view returns (bool) {
    return (
      interfaceID == this.supportsInterface.selector || // ERC165
      interfaceID == (
        this.hasAttribute.selector 
        ^ this.getAttributeValue.selector
        ^ this.countAttributeTypes.selector
        ^ this.getAttributeTypeID.selector
      ) // AttributeRegistryInterface
    ); // 0x01ffc9a7 || 0x5f46473f
  }

  /**
   * @notice Determine if an attribute type with ID `attributeTypeID` is
   * currently defined on the jurisdiction.
   * @param attributeTypeID uint256 The attribute type ID in question.
   * @return True if the attribute type is defined, false otherwise.
   */
  function isAttributeType(uint256 attributeTypeID) public view returns (bool) {
    return _attributeTypes[attributeTypeID].exists;
  }

  /**
   * @notice Determine if the account `account` is currently assigned as a
   * validator on the jurisdiction.
   * @param account address The account to check for validator status.
   * @return True if the account is assigned as a validator, false otherwise.
   */
  function isValidator(address account) public view returns (bool) {
    return _validators[account].exists;
  }

  /**
   * @notice Internal function to determine if a validator at account
   * `validator` can issue attributes of the type with ID `attributeTypeID`.
   * @param validator address The account of the validator.
   * @param attributeTypeID uint256 The ID of the attribute type to check.
   * @return True if the validator can issue attributes of the given type, false
   * otherwise.
   */
  function canValidate(
    address validator,
    uint256 attributeTypeID
  ) internal view returns (bool) {
    return (
      _validators[validator].exists &&   // isValidator(validator)
      _attributeTypes[attributeTypeID].approvedValidators[validator] &&
      _attributeTypes[attributeTypeID].exists // isAttributeType(attributeTypeID)
    );
  }
}