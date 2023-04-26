pragma solidity 0.7.5;

interface VersionableBridge {
    function getBridgeInterfacesVersion()
        external
        pure
        returns (
            uint64 major,
            uint64 minor,
            uint64 patch
        );

    function getBridgeMode() external pure returns (bytes4);
}
