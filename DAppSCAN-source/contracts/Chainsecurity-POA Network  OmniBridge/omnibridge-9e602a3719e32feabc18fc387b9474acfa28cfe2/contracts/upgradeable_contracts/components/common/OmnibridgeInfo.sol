pragma solidity 0.7.5;

import "../../VersionableBridge.sol";

/**
 * @title OmnibridgeInfo
 * @dev Functionality for versioning Omnibridge mediator.
 */
contract OmnibridgeInfo is VersionableBridge {
    event TokensBridgingInitiated(
        address indexed token,
        address indexed sender,
        uint256 value,
        bytes32 indexed messageId
    );
    event TokensBridged(address indexed token, address indexed recipient, uint256 value, bytes32 indexed messageId);

    /**
     * @dev Tells the bridge interface version that this contract supports.
     * @return major value of the version
     * @return minor value of the version
     * @return patch value of the version
     */
    function getBridgeInterfacesVersion()
        external
        pure
        override
        returns (
            uint64 major,
            uint64 minor,
            uint64 patch
        )
    {
        return (3, 0, 0);
    }

    /**
     * @dev Tells the bridge mode that this contract supports.
     * @return _data 4 bytes representing the bridge mode
     */
    function getBridgeMode() external pure override returns (bytes4 _data) {
        return 0xb1516c26; // bytes4(keccak256(abi.encodePacked("multi-erc-to-erc-amb")))
    }
}
