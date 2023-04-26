// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../IFundsHandler.sol";


contract CloneBasedRegistry {

    // FIXME is this a constant for all creator royalties?
    uint256 constant ROYALTY_AMOUNT = 125000; // 12.5% as represented in eip-2981

    mapping(string => address) handlers;
    mapping(uint256 => address) proxies;

    event HandlerAdded (string name, address handler);
    event ProxyDeployed (uint256 editionId, string handlerName, address proxy, address[] recipients, uint256[] splits);

    function addHandler(string memory _name, address _handler) public {

        // Store the beacon address by name
        handlers[_name] = _handler;

        // Emit event
        emit HandlerAdded(_name, _handler);
    }

    function setupRoyalty(uint256 _editionId, string memory _handlerName, address[] calldata _recipients, uint256[] calldata _splits)
    public
    payable
    returns (address proxy){

        // Get the specified funds handler
        address handler = handlers[_handlerName];

        // Clone funds handler as Minimal Proxy
        proxy = Clones.clone(handler);

        // Initialize proxy
        IFundsHandler(proxy).init(_recipients, _splits);

        // Verify that it was initialized properly
        require(IFundsHandler(proxy).totalRecipients() == _recipients.length);

        // Store address of proxy by edition id
        proxies[_editionId] = proxy;

        // Emit event
        emit ProxyDeployed(_editionId, _handlerName, proxy, _recipients, _splits);
    }

    function royaltyInfo(uint256 editionId) public view returns (address receiver, uint256 amount) {
        receiver = proxies[editionId];
        amount = ROYALTY_AMOUNT;
    }

}
