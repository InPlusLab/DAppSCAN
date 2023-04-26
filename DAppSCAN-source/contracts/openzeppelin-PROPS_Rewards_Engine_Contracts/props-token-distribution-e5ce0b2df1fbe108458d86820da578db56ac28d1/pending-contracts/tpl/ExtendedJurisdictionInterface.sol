pragma solidity ^0.4.24;


interface ExtendedJurisdictionInterface {
  // NOTE: this extends BasicJurisdictionInterface for additional functionality.

  // declare events (NOTE: consider which fields should be indexed)
  event ValidatorSigningKeyModified(
    address indexed validator,
    address newSigningKey
  );

  event StakeAllocated(
    address indexed staker,
    uint256 indexed attribute,
    uint256 amount
  );

  event StakeRefunded(
    address indexed staker,
    uint256 indexed attribute,
    uint256 amount
  );

  event FeePaid(
    address indexed recipient,
    address indexed payee,
    uint256 indexed attribute,
    uint256 amount
  );
  
  event TransactionRebatePaid(
    address indexed submitter,
    address indexed payee,
    uint256 indexed attribute,
    uint256 amount
  );

  /**
  * @notice Add a restricted attribute type with ID `ID` and description
  * `description` to the jurisdiction. Restricted attribute types can only be
  * removed by the issuing validator or the jurisdiction.
  * @param ID uint256 The ID of the restricted attribute type to add.
  * @param description string A description of the restricted attribute type.
  * @dev Once an attribute type is added with a given ID, the description or the
  * restricted status of the attribute type cannot be changed, even if the
  * attribute type is removed and added back later.
  */
  function addRestrictedAttributeType(uint256 ID, string description) external;

  /**
  * @notice Enable or disable a restriction for a given attribute type ID `ID`
  * that prevents attributes of the given type from being set by operators based
  * on the provided value for `onlyPersonal`.
  * @param ID uint256 The attribute type ID in question.
  * @param onlyPersonal bool Whether the address may only be set personally.
  */
  function setAttributeTypeOnlyPersonal(uint256 ID, bool onlyPersonal) external;

  /**
  * @notice Set a secondary source for a given attribute type ID `ID`, with an
  * address `registry` of the secondary source in question and a given
  * `sourceAttributeTypeID` for attribute type ID to check on the secondary
  * source. The secondary source will only be checked for the given attribute in
  * cases where no attribute of the given attribute type ID is assigned locally.
  * @param ID uint256 The attribute type ID to set the secondary source for.
  * @param attributeRegistry address The secondary attribute registry account.
  * @param sourceAttributeTypeID uint256 The attribute type ID on the secondary
  * source to check.
  * @dev To remove a secondary source on an attribute type, the registry address
  * should be set to the null address.
  */
  function setAttributeTypeSecondarySource(
    uint256 ID,
    address attributeRegistry,
    uint256 sourceAttributeTypeID
  ) external;

  /**
  * @notice Set a minimum required stake for a given attribute type ID `ID` and
  * an amount of `stake`, to be locked in the jurisdiction upon assignment of
  * attributes of the given type. The stake will be applied toward a transaction
  * rebate in the event the attribute is revoked, with the remainder returned to
  * the staker.
  * @param ID uint256 The attribute type ID to set a minimum required stake for.
  * @param minimumRequiredStake uint256 The minimum required funds to lock up.
  * @dev To remove a stake requirement from an attribute type, the stake amount
  * should be set to 0.
  */
  function setAttributeTypeMinimumRequiredStake(
    uint256 ID,
    uint256 minimumRequiredStake
  ) external;

  /**
  * @notice Set a required fee for a given attribute type ID `ID` and an amount
  * of `fee`, to be paid to the owner of the jurisdiction upon assignment of
  * attributes of the given type.
  * @param ID uint256 The attribute type ID to set the required fee for.
  * @param fee uint256 The required fee amount to be paid upon assignment.
  * @dev To remove a fee requirement from an attribute type, the fee amount
  * should be set to 0.
  */
  function setAttributeTypeJurisdictionFee(uint256 ID, uint256 fee) external;

  /**
  * @notice Set the public address associated with a validator signing key, used
  * to sign off-chain attribute approvals, as `newSigningKey`.
  * @param newSigningKey address The address associated with signing key to set.
  */
  function setValidatorSigningKey(address newSigningKey) external;

  /**
  * @notice Add an attribute of the type with ID `attributeTypeID`, an attribute
  * value of `value`, and an associated validator fee of `validatorFee` to
  * account of `msg.sender` by passing in a signed attribute approval with
  * signature `signature`.
  * @param attributeTypeID uint256 The ID of the attribute type to add.
  * @param value uint256 The value for the attribute to add.
  * @param validatorFee uint256 The fee to be paid to the issuing validator.
  * @param signature bytes The signature from the validator attribute approval.
  */
  function addAttribute(
    uint256 attributeTypeID,
    uint256 value,
    uint256 validatorFee,
    bytes signature
  ) external payable;

  /**
  * @notice Remove an attribute of the type with ID `attributeTypeID` from
  * account of `msg.sender`.
  * @param attributeTypeID uint256 The ID of the attribute type to remove.
  */
  function removeAttribute(uint256 attributeTypeID) external;

  /**
  * @notice Add an attribute of the type with ID `attributeTypeID`, an attribute
  * value of `value`, and an associated validator fee of `validatorFee` to
  * account `account` by passing in a signed attribute approval with signature
  * `signature`.
  * @param account address The account to add the attribute to.
  * @param attributeTypeID uint256 The ID of the attribute type to add.
  * @param value uint256 The value for the attribute to add.
  * @param validatorFee uint256 The fee to be paid to the issuing validator.
  * @param signature bytes The signature from the validator attribute approval.
  * @dev Restricted attribute types can only be removed by issuing validators or
  * the jurisdiction itself.
  */
  function addAttributeFor(
    address account,
    uint256 attributeTypeID,
    uint256 value,
    uint256 validatorFee,
    bytes signature
  ) external payable;

  /**
  * @notice Remove an attribute of the type with ID `attributeTypeID` from
  * account of `account`.
  * @param account address The account to remove the attribute from.
  * @param attributeTypeID uint256 The ID of the attribute type to remove.
  * @dev Restricted attribute types can only be removed by issuing validators or
  * the jurisdiction itself.
  */
  function removeAttributeFor(address account, uint256 attributeTypeID) external;

  /**
   * @notice Invalidate a signed attribute approval before it has been set by
   * supplying the hash of the approval `hash` and the signature `signature`.
   * @param hash bytes32 The hash of the attribute approval.
   * @param signature bytes The hash's signature, resolving to the signing key.
   * @dev Attribute approvals can only be removed by issuing validators or the
   * jurisdiction itself.
   */
  function invalidateAttributeApproval(
    bytes32 hash,
    bytes signature
  ) external;

  /**
   * @notice Get the hash of a given attribute approval.
   * @param account address The account specified by the attribute approval.
   * @param operator address An optional account permitted to submit approval.
   * @param attributeTypeID uint256 The ID of the attribute type in question.
   * @param value uint256 The value of the attribute in the approval.
   * @param fundsRequired uint256 The amount to be included with the approval.
   * @param validatorFee uint256 The required fee to be paid to the validator.
   * @return The hash of the attribute approval.
   */
  function getAttributeApprovalHash(
    address account,
    address operator,
    uint256 attributeTypeID,
    uint256 value,
    uint256 fundsRequired,
    uint256 validatorFee
  ) external view returns (bytes32 hash);

  /**
   * @notice Check if a given signed attribute approval is currently valid when
   * submitted directly by `msg.sender`.
   * @param attributeTypeID uint256 The ID of the attribute type in question.
   * @param value uint256 The value of the attribute in the approval.
   * @param fundsRequired uint256 The amount to be included with the approval.
   * @param validatorFee uint256 The required fee to be paid to the validator.
   * @param signature bytes The attribute approval signature, based on a hash of
   * the other parameters and the submitting account.
   * @return True if the approval is currently valid, false otherwise.
   */
  function canAddAttribute(
    uint256 attributeTypeID,
    uint256 value,
    uint256 fundsRequired,
    uint256 validatorFee,
    bytes signature
  ) external view returns (bool);

  /**
   * @notice Check if a given signed attribute approval is currently valid for a
   * given account when submitted by the operator at `msg.sender`.
   * @param account address The account specified by the attribute approval.
   * @param attributeTypeID uint256 The ID of the attribute type in question.
   * @param value uint256 The value of the attribute in the approval.
   * @param fundsRequired uint256 The amount to be included with the approval.
   * @param validatorFee uint256 The required fee to be paid to the validator.
   * @param signature bytes The attribute approval signature, based on a hash of
   * the other parameters and the submitting account.
   * @return True if the approval is currently valid, false otherwise.
   */
  function canAddAttributeFor(
    address account,
    uint256 attributeTypeID,
    uint256 value,
    uint256 fundsRequired,
    uint256 validatorFee,
    bytes signature
  ) external view returns (bool);

  /**
   * @notice Get comprehensive information on an attribute type with ID
   * `attributeTypeID`.
   * @param attributeTypeID uint256 The attribute type ID in question.
   * @return Information on the attribute type in question.
   */
  function getAttributeTypeInformation(
    uint256 attributeTypeID
  ) external view returns (
    string description,
    bool isRestricted,
    bool isOnlyPersonal,
    address secondarySource,
    uint256 secondaryId,
    uint256 minimumRequiredStake,
    uint256 jurisdictionFee
  );
  
  /**
   * @notice Get a validator's signing key.
   * @param validator address The account of the validator.
   * @return The account referencing the public component of the signing key.
   */
  function getValidatorSigningKey(
    address validator
  ) external view returns (
    address signingKey
  );
}
