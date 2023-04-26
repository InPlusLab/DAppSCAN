pragma solidity ^0.5.4;
pragma experimental ABIEncoderV2;

import "../Lib/LibDerivative.sol";

/// @title Opium.Interface.IDerivativeLogic contract is an interface that every syntheticId should implement
contract IDerivativeLogic is LibDerivative {
    /// @notice Validates ticker
    /// @param _derivative Derivative Instance of derivative to validate
    /// @return Returns boolean whether ticker is valid
    function validateInput(Derivative memory _derivative) public view returns (bool);

    /// @notice Calculates margin required for derivative creation
    /// @param _derivative Derivative Instance of derivative
    /// @return buyerMargin uint256 Margin needed from buyer (LONG position)
    /// @return sellerMargin uint256 Margin needed from seller (SHORT position)
    function getMargin(Derivative memory _derivative) public view returns (uint256 buyerMargin, uint256 sellerMargin);

    /// @notice Calculates payout for derivative execution
    /// @param _derivative Derivative Instance of derivative
    /// @param _result uint256 Data retrieved from oracleId on the maturity
    /// @return buyerPayout uint256 Payout in ratio for buyer (LONG position holder)
    /// @return sellerPayout uint256 Payout in ratio for seller (SHORT position holder)
    function getExecutionPayout(Derivative memory _derivative, uint256 _result)	public view returns (uint256 buyerPayout, uint256 sellerPayout);

    /// @notice Returns syntheticId author address for Opium commissions
    /// @return authorAddress address The address of syntheticId address
    function getAuthorAddress() public view returns (address authorAddress);

    /// @notice Returns syntheticId author commission in base of COMMISSION_BASE
    /// @return commission uint256 Author commission
    function getAuthorCommission() public view returns (uint256 commission);

    /// @notice Returns whether thirdparty could execute on derivative's owner's behalf
    /// @param _derivativeOwner address Derivative owner address
    /// @return Returns boolean whether _derivativeOwner allowed third party execution
    function thirdpartyExecutionAllowed(address _derivativeOwner) public view returns (bool);

    /// @notice Returns whether syntheticId implements pool logic
    /// @return Returns whether syntheticId implements pool logic
    function isPool() public view returns (bool);

    /// @notice Sets whether thirds parties are allowed or not to execute derivative's on msg.sender's behalf
    /// @param _allow bool Flag for execution allowance
    function allowThirdpartyExecution(bool _allow) public;

    // Event with syntheticId metadata JSON string (for DIB.ONE derivative explorer)
    event MetadataSet(string metadata);
}
