// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

interface IRegistry {
    struct Entry {
        address contractAddress;
        bool activated;
        bytes32 defaultData;
        bool activatedByDefault;
    }

    ///@notice return the address of PositionManagerFactory
    ///@return address of PositionManagerFactory
    function positionManagerFactoryAddress() external view returns (address);

    ///@notice return the address of Governance
    ///@return address of Governance
    function governance() external view returns (address);

    ///@notice return the address of Governance
    ///@return address of Governance
    function getModuleKeys() external view returns (bytes32[] memory);

    ///@notice adds a new whitelisted keeper
    ///@param _keeper address of the new keeper
    function addKeeperToWhitelist(address _keeper) external;

    ///@notice checks if the address is whitelisted as a keeper
    ///@param _keeper address to check
    ///@return bool true if the address is withelisted, false otherwise
    function isWhitelistedKeeper(address _keeper) external view returns (bool);

    function getModuleInfo(bytes32 _id)
        external
        view
        returns (
            address,
            bool,
            bytes32,
            bool
        );
}
