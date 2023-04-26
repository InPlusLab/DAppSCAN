pragma solidity ^0.5.4;
pragma experimental ABIEncoderV2;

/// @title Opium.Lib.LibDerivative contract should be inherited by contracts that use Derivative structure and calculate derivativeHash
contract LibDerivative {
    // Opium derivative structure (ticker) definition
    struct Derivative {
        // Margin parameter for syntheticId
        uint256 margin;
        // Maturity of derivative
        uint256 endTime;
        // Additional parameters for syntheticId
        uint256[] params;
        // oracleId of derivative
        address oracleId;
        // Margin token address of derivative
        address token;
        // syntheticId of derivative
        address syntheticId;
    }

    /// @notice Calculates hash of provided Derivative
    /// @param _derivative Derivative Instance of derivative to hash
    /// @return derivativeHash bytes32 Derivative hash
    function getDerivativeHash(Derivative memory _derivative) public pure returns (bytes32 derivativeHash) {
        derivativeHash = keccak256(abi.encodePacked(
            _derivative.margin,
            _derivative.endTime,
            _derivative.params,
            _derivative.oracleId,
            _derivative.token,
            _derivative.syntheticId
        ));
    }
}
