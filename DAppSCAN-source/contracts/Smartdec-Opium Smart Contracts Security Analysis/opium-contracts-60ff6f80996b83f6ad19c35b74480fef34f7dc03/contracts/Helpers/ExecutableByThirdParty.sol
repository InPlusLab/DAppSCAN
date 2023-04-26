pragma solidity ^0.5.4;

/// @title Opium.Helpers.ExecutableByThirdParty contract helps to syntheticId development and responsible for getting and setting thirdparty execution settings
contract ExecutableByThirdParty {
    // Mapping holds whether position owner allows thirdparty execution
    mapping (address => bool) thirdpartyExecutionAllowance;

    /// @notice Getter for thirdparty execution allowance
    /// @param derivativeOwner Address of position holder that's going to be executed
    /// @return bool Returns whether thirdparty execution is allowed by derivativeOwner
    function thirdpartyExecutionAllowed(address derivativeOwner) public view returns (bool) {
        return thirdpartyExecutionAllowance[derivativeOwner];
    }

    /// @notice Sets third party execution settings for `msg.sender`
    /// @param allow Indicates whether thirdparty execution should be allowed or not
    function allowThirdpartyExecution(bool allow) public {
        thirdpartyExecutionAllowance[msg.sender] = allow;
    }
}
