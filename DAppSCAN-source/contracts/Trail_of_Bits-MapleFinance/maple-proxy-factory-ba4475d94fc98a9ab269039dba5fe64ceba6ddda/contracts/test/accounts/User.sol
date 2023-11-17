// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import { IMapleProxyFactory } from "../../interfaces/IMapleProxyFactory.sol";
import { IMapleProxied }      from "../../interfaces/IMapleProxied.sol";

contract User {

    /************************/
    /*** Direct Functions ***/
    /************************/

    function mapleProxied_upgrade(address instance_, uint256 toVersion_, bytes calldata arguments_) external {
        IMapleProxied(instance_).upgrade(toVersion_, arguments_);
    }

    function mapleProxyFactory_createInstance(address factory_, bytes calldata arguments_) external returns (address instance_) {
        return IMapleProxyFactory(factory_).createInstance(arguments_);
    }

    /*********************/
    /*** Try Functions ***/
    /*********************/

    function try_mapleProxied_upgrade(address instance_, uint256 toVersion_, bytes calldata arguments_) external returns (bool ok_) {
        ( ok_, ) = instance_.call(abi.encodeWithSelector(IMapleProxied.upgrade.selector, toVersion_, arguments_));
    }

    function try_mapleProxyFactory_createInstance(address factory_, bytes calldata arguments_) external returns (bool ok_) {
        ( ok_, ) = factory_.call(abi.encodeWithSelector(IMapleProxyFactory.createInstance.selector, arguments_));
    }

}
