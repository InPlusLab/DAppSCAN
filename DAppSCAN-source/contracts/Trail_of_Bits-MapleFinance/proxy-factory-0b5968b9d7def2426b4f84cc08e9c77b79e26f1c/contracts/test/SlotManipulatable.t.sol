// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import { DSTest } from "../../modules/ds-test/src/test.sol";

import { SlotManipulatable }  from "../SlotManipulatable.sol";

contract StorageContract is SlotManipulatable {

    bytes32 private constant REFERENCE_SLOT = bytes32(0x1111111111111111111111111111111111111111111111111111111111111111);

    function setSlotValue(bytes32 slot_, bytes32 value_) external {
        _setSlotValue(slot_, value_);
    }

    function setReferenceValue(bytes32 key_, bytes32 value_) external {
        _setSlotValue(_getReferenceTypeSlot(REFERENCE_SLOT, bytes32(key_)), value_);
    }

    function getSlotValue(bytes32 slot_) external view returns (bytes32 value_) {
        value_ = _getSlotValue(slot_);
    }

    function getReferenceValue(bytes32 key_) external view returns (bytes32 value_) {
        value_ = _getSlotValue(_getReferenceTypeSlot(REFERENCE_SLOT, key_));
    }

    function getReferenceSlot(bytes32 slot_, bytes32 key) external pure returns (bytes32 referenceSlot_) {
        return _getReferenceTypeSlot(REFERENCE_SLOT, _getReferenceTypeSlot(slot_, key));
    }

}

contract SlotManipulatableTest is DSTest {

    StorageContract storageContract;

    function setUp() external {
        storageContract = new StorageContract();
    }

    function test_setAndRetrieve_uint256(uint256 value_) external {
        storageContract.setSlotValue(bytes32(0), bytes32(value_));

        assertEq(uint256(storageContract.getSlotValue(bytes32(0))), value_);
    }

    function test_setAndRetrieve_address(address value_) external {
        storageContract.setSlotValue(bytes32(0), bytes32(uint256(uint160(value_))));

        assertEq(address(uint160(uint256(storageContract.getSlotValue(bytes32(0))))), value_);
    }

    function test_setAndRetrieve_bytes32(bytes32 value_) external {
        storageContract.setSlotValue(bytes32(0), value_);

        assertEq(storageContract.getSlotValue(bytes32(0)), value_);
    }

    function test_setAndRetrieve_uint8(uint8 value_) external {
        storageContract.setSlotValue(bytes32(0), bytes32(uint256(value_)));

        assertEq(uint8(uint256(storageContract.getSlotValue(bytes32(0)))), value_);
    }

    function test_setAndRetrieve_bytes4(bytes4 value_) external {
        storageContract.setSlotValue(bytes32(0), bytes32(value_));

        assertEq(bytes4(storageContract.getSlotValue(bytes32(0))), value_);
    }

    function test_referenceType(bytes32 key_, bytes32 value_) external {
        storageContract.setReferenceValue(key_, value_);

        assertEq(storageContract.getReferenceValue(key_), value_);
    }

    function test_doubleReferenceType(bytes32 key_, bytes32 index_, bytes32 value_) external {
        bytes32 slot = storageContract.getReferenceSlot(key_, index_);

        storageContract.setReferenceValue(slot, value_);

        assertEq(storageContract.getReferenceValue(slot), value_);
    }

}
