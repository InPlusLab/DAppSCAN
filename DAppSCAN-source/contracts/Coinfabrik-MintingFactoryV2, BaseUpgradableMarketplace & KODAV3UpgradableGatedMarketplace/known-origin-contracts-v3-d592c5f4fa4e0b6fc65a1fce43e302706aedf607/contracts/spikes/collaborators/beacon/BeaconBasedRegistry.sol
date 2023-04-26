// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../IFundsHandler.sol";


contract BeaconBasedRegistry {

    // FIXME is this a constant for all creator royalties?
    uint256 constant ROYALTY_AMOUNT = 250000; // 2.5% as represented in eip-2981

    mapping(string => address) beacons;
    mapping(uint256 => address) proxies;

    event BeaconAdded (string name, address beacon);
    event ProxyDeployed (uint256 editionId, string beaconName, address proxy, address[] recipients, uint256[] splits);

    function addBeacon(string memory _name, address _beacon) public {

        // Store the beacon address by name
        beacons[_name] = _beacon;

        // Emit event
        emit BeaconAdded(_name, _beacon);
    }

    function setupRoyalty(uint256 _editionId, string memory _beaconName, address[] calldata _recipients, uint256[] calldata _splits)
    public
    payable
    returns (address proxy){

        // Get the specified beacon
        address beacon = beacons[_beaconName];

        // Create the initializer data
        bytes memory initData =
        abi.encodeWithSignature(
            "init(address[],uint256[])",
            _recipients,
            _splits
        );

        // Instantiate beacon proxy
        proxy = address(new BeaconProxy(beacon, initData));

        // Verify that it was initialized properly
        require(IFundsHandler(proxy).totalRecipients() == _recipients.length);

        // Store address of proxy by edition id
        proxies[_editionId] = proxy;

        // Emit event
        emit ProxyDeployed(_editionId, _beaconName, proxy, _recipients, _splits);
    }

    function royaltyInfo(uint256 editionId) public view returns (address receiver, uint256 amount) {
        receiver = proxies[editionId];
        amount = ROYALTY_AMOUNT;
    }

}
