// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import { TestUtils } from "../../modules/contract-test-utils/contracts/test.sol";

import { MockInitializerV1, MockInitializerV2 } from "../../modules/proxy-factory/contracts/test/mocks/Mocks.sol";

import { Governor } from "./accounts/Governor.sol";
import { User }     from "./accounts/User.sol";

import { MapleGlobalsMock, MapleInstanceMock } from "./mocks/Mocks.sol";

import  { MapleProxyFactory } from "../MapleProxyFactory.sol";

contract MapleProxyFactoryTest is TestUtils {

    Governor             internal governor;
    Governor             internal notGovernor;
    MapleGlobalsMock     internal globals;
    MapleProxyFactory    internal factory;
    MapleInstanceMock    internal implementation1;
    MapleInstanceMock    internal implementation2;
    MockInitializerV1    internal initializerV1;
    MockInitializerV2    internal initializerV2;
    User                 internal user;

    function setUp() external {
        governor        = new Governor();
        implementation1 = new MapleInstanceMock();
        implementation2 = new MapleInstanceMock();
        initializerV1   = new MockInitializerV1();
        initializerV2   = new MockInitializerV2();
        notGovernor     = new Governor();
        user            = new User();


        globals = new MapleGlobalsMock(address(governor));
        factory = new MapleProxyFactory(address(globals));
    }

    function test_registerImplementation() external {
        assertTrue(!notGovernor.try_mapleProxyFactory_registerImplementation(address(factory), 1, address(implementation1), address(initializerV1)), "Should fail: not governor");
        assertTrue(   !governor.try_mapleProxyFactory_registerImplementation(address(factory), 0, address(implementation1), address(initializerV1)), "Should fail: invalid version");
        assertTrue(   !governor.try_mapleProxyFactory_registerImplementation(address(factory), 1, address(0),               address(initializerV1)), "Should fail: invalid implementation address");
        assertTrue(    governor.try_mapleProxyFactory_registerImplementation(address(factory), 1, address(implementation1), address(initializerV1)), "Should succeed");
        assertTrue(   !governor.try_mapleProxyFactory_registerImplementation(address(factory), 1, address(implementation1), address(initializerV1)), "Should fail: already registered version");

        assertEq(factory.implementationOf(1),             address(implementation1), "Incorrect state of implementationOf");
        assertEq(factory.migratorForPath(1, 1),           address(initializerV1),   "Incorrect state of migratorForPath");

        assertEq(factory.versionOf(address(implementation1)), 1, "Incorrect state of versionOf");
    }

    function test_setDefaultVersion() external {
        governor.mapleProxyFactory_registerImplementation(address(factory), 1, address(implementation1), address(initializerV1));

        assertTrue(!notGovernor.try_mapleProxyFactory_setDefaultVersion(address(factory), 1), "Should fail: not governor");
        assertTrue(   !governor.try_mapleProxyFactory_setDefaultVersion(address(factory), 2), "Should fail: version not registered");
        assertTrue(    governor.try_mapleProxyFactory_setDefaultVersion(address(factory), 1), "Should succeed: set");

        assertEq(factory.defaultVersion(), 1, "Incorrect state of defaultVersion");

        assertTrue(!notGovernor.try_mapleProxyFactory_setDefaultVersion(address(factory), 0), "Should fail: not governor");
        assertTrue(    governor.try_mapleProxyFactory_setDefaultVersion(address(factory), 0), "Should succeed: unset");

        assertEq(factory.defaultVersion(), 0, "Incorrect state of defaultVersion");
    }

    function test_createInstance() external {

        bytes memory arguments = new bytes(0);

        assertTrue(!user.try_mapleProxyFactory_createInstance(address(factory), arguments), "Should fail: unregistered version");

        governor.mapleProxyFactory_registerImplementation(address(factory), 1, address(implementation1), address(initializerV1));
        governor.mapleProxyFactory_setDefaultVersion(address(factory), 1);

        MapleInstanceMock instance1 = MapleInstanceMock(user.mapleProxyFactory_createInstance(address(factory), arguments));

        assertEq(instance1.factory(),                           address(factory));
        assertEq(instance1.implementation(),                    address(implementation1));
        assertEq(factory.versionOf(instance1.implementation()), 1);

        MapleInstanceMock instance2 = MapleInstanceMock(user.mapleProxyFactory_createInstance(address(factory), arguments));

        assertEq(instance2.factory(),                           address(factory));
        assertEq(instance2.implementation(),                    address(implementation1));
        assertEq(factory.versionOf(instance2.implementation()), 1);

        assertTrue(address(instance1) != address(instance2), "Instances should have unique addresses");
    }

    function test_enableUpgradePath() external {
        governor.mapleProxyFactory_registerImplementation(address(factory), 1, address(implementation1), address(initializerV1));
        governor.mapleProxyFactory_registerImplementation(address(factory), 2, address(implementation2), address(initializerV2));

        assertTrue(!notGovernor.try_mapleProxyFactory_enableUpgradePath(address(factory), 1, 2, address(444444)), "Should fail: not governor");
        assertTrue(   !governor.try_mapleProxyFactory_enableUpgradePath(address(factory), 1, 1, address(444444)), "Should fail: overwriting initializer");
        assertTrue(    governor.try_mapleProxyFactory_enableUpgradePath(address(factory), 1, 2, address(444444)), "Should succeed: upgrade");

        assertEq(factory.migratorForPath(1, 2), address(444444), "Incorrect migrator");

        assertTrue(governor.try_mapleProxyFactory_enableUpgradePath(address(factory), 2, 1, address(555555)), "Should succeed: downgrade");

        assertEq(factory.migratorForPath(2, 1), address(555555), "Incorrect migrator");

        assertTrue(governor.try_mapleProxyFactory_enableUpgradePath(address(factory), 1, 2, address(888888)), "Should succeed: change migrator");

        assertEq(factory.migratorForPath(1, 2), address(888888), "Incorrect migrator");
    }

    function test_disableUpgradePath() external {
        governor.mapleProxyFactory_registerImplementation(address(factory), 1, address(implementation1), address(initializerV1));
        governor.mapleProxyFactory_registerImplementation(address(factory), 2, address(implementation2), address(initializerV2));
        governor.mapleProxyFactory_enableUpgradePath(address(factory), 1, 2, address(444444));

        assertEq(factory.migratorForPath(1, 2), address(444444), "Incorrect migrator");

        assertTrue(!notGovernor.try_mapleProxyFactory_disableUpgradePath(address(factory), 1, 2), "Should fail: not governor");
        assertTrue(   !governor.try_mapleProxyFactory_disableUpgradePath(address(factory), 1, 1), "Should fail: overwriting initializer");
        assertTrue(    governor.try_mapleProxyFactory_disableUpgradePath(address(factory), 1, 2), "Should succeed");

        assertEq(factory.migratorForPath(1, 2), address(0), "Incorrect migrator");
    }

    function test_upgradeInstance() external {
        governor.mapleProxyFactory_registerImplementation(address(factory), 1, address(implementation1), address(initializerV1));
        governor.mapleProxyFactory_registerImplementation(address(factory), 2, address(implementation2), address(initializerV2));
        governor.mapleProxyFactory_setDefaultVersion(address(factory), 1);

        bytes memory arguments = new bytes(0);

        MapleInstanceMock instance = MapleInstanceMock(user.mapleProxyFactory_createInstance(address(factory), arguments));

        assertEq(instance.implementation(),                    address(implementation1));
        assertEq(factory.versionOf(instance.implementation()), 1);

        assertTrue(!user.try_mapleProxied_upgrade(address(instance), 2, new bytes(0)), "Should fail: upgrade path not enabled");

        governor.mapleProxyFactory_enableUpgradePath(address(factory), 1, 2, address(0));

        assertTrue(!user.try_mapleProxied_upgrade(address(instance), 0, new bytes(0)), "Should fail: invalid version");
        assertTrue(!user.try_mapleProxied_upgrade(address(instance), 1, new bytes(0)), "Should fail: same version");
        assertTrue(!user.try_mapleProxied_upgrade(address(instance), 3, new bytes(0)), "Should fail: non-existent version");
        assertTrue( user.try_mapleProxied_upgrade(address(instance), 2, new bytes(0)), "Should succeed");

        assertEq(instance.implementation(),                    address(implementation2));
        assertEq(factory.versionOf(instance.implementation()), 2);
    }

}
