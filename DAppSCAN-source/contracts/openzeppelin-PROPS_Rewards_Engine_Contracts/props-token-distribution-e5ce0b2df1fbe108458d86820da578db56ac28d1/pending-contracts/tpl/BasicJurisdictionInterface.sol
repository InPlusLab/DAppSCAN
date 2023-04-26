pragma solidity ^0.4.25;


/**
 * @title Basic TPL Jurisdiction Interface.
 */
interface BasicJurisdictionInterface {
  // declare events
  event AttributeTypeAdded(uint256 indexed attributeTypeID, string description);
  
  event AttributeTypeRemoved(uint256 indexed attributeTypeID);
  
  event ValidatorAdded(address indexed validator, string description);
  
  event ValidatorRemoved(address indexed validator);
  
  event ValidatorApprovalAdded(
    address validator,
    uint256 indexed attributeTypeID
  );

  event ValidatorApprovalRemoved(
    address validator,
    uint256 indexed attributeTypeID
  );

  event AttributeAdded(
    address validator,
    address indexed attributee,
    uint256 attributeTypeID,
    uint256 attributeValue
  );

  event AttributeRemoved(
    address validator,
    address indexed attributee,
    uint256 attributeTypeID
  );

  /**
  * @notice Add an attribute type with ID `ID` and description `description` to
  * the jurisdiction.
  * @param ID uint256 The ID of the attribute type to add.
  * @param description string A description of the attribute type.
  * @dev Once an attribute type is added with a given ID, the description of the
  * attribute type cannot be changed, even if the attribute type is removed and
  * added back later.
  */
  function addAttributeType(uint256 ID, string description) external;

  /**
  * @notice Remove the attribute type with ID `ID` from the jurisdiction.
  * @param ID uint256 The ID of the attribute type to remove.
  * @dev All issued attributes of the given type will become invalid upon
  * removal, but will become valid again if the attribute is reinstated.
  */
  function removeAttributeType(uint256 ID) external;

  /**
  * @notice Add account `validator` as a validator with a description
  * `description` who can be approved to set attributes of specific types.
  * @param validator address The account to assign as the validator.
  * @param description string A description of the validator.
  * @dev Note that the jurisdiction can add iteslf as a validator if desired.
  */
  function addValidator(address validator, string description) external;

  /**
  * @notice Remove the validator at address `validator` from the jurisdiction.
  * @param validator address The account of the validator to remove.
  * @dev Any attributes issued by the validator will become invalid upon their
  * removal. If the validator is reinstated, those attributes will become valid
  * again. Any approvals to issue attributes of a given type will need to be
  * set from scratch in the event a validator is reinstated.
  */
  function removeValidator(address validator) external;

  /**
  * @notice Approve the validator at address `validator` to issue attributes of
  * the type with ID `attributeTypeID`.
  * @param validator address The account of the validator to approve.
  * @param attributeTypeID uint256 The ID of the approved attribute type.
  */
  function addValidatorApproval(
    address validator,
    uint256 attributeTypeID
  ) external;

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
  ) external;

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
  ) external payable;

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
  ) external;

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
  ) external view returns (bool);

  /**
   * @notice Get a description of the attribute type with ID `attributeTypeID`.
   * @param attributeTypeID uint256 The ID of the attribute type to check for.
   * @return A description of the attribute type.
   */
  function getAttributeTypeDescription(
    uint256 attributeTypeID
  ) external view returns (string description);
  
  /**
   * @notice Get a description of the validator at account `validator`.
   * @param validator address The account of the validator in question.
   * @return A description of the validator.
   */
  function getValidatorDescription(
    address validator
  ) external view returns (string description);

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
  ) external view returns (address validator, bool isStillValid);

  /**
   * @notice Count the number of attribute types defined by the jurisdiction.
   * @return The number of available attribute types.
   */
  function countAttributeTypes() external view returns (uint256);

  /**
   * @notice Get the ID of the attribute type at index `index`.
   * @param index uint256 The index of the attribute type in question.
   * @return The ID of the attribute type.
   */
  function getAttributeTypeID(uint256 index) external view returns (uint256);

  /**
   * @notice Get the IDs of all available attribute types on the jurisdiction.
   * @return A dynamic array containing all available attribute type IDs.
   */
  function getAttributeTypeIDs() external view returns (uint256[]);

  /**
   * @notice Count the number of validators defined by the jurisdiction.
   * @return The number of defined validators.
   */
  function countValidators() external view returns (uint256);

  /**
   * @notice Get the account of the validator at index `index`.
   * @param index uint256 The index of the validator in question.
   * @return The account of the validator.
   */
  function getValidator(uint256 index) external view returns (address);

  /**
   * @notice Get the accounts of all available validators on the jurisdiction.
   * @return A dynamic array containing all available validator accounts.
   */
  function getValidators() external view returns (address[]);
}