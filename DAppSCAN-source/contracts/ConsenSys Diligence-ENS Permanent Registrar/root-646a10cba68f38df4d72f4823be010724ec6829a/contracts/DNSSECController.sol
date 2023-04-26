pragma solidity ^0.5.0;

import "@ensdomains/dnssec-oracle/contracts/DNSSEC.sol";
import "@ensdomains/dnssec-oracle/contracts/BytesUtils.sol";
import "@ensdomains/dnsregistrar/contracts/DNSClaimChecker.sol";
import "@ensdomains/buffer/contracts/Buffer.sol";
import "./Root.sol";

contract DNSSECController {
    using BytesUtils for bytes;
    using Buffer for Buffer.buffer;

    bytes32 constant private ROOT_NODE = bytes32(0);

    uint16 constant private CLASS_INET = 1;
    uint16 constant private TYPE_TXT = 16;
    uint16 constant private TYPE_DS = 43;

    bytes4 constant private INTERFACE_META_ID = bytes4(keccak256("supportsInterface(bytes4)"));
    bytes4 constant private ROOT_REGISTRATION_ID = bytes4(
        keccak256("proveAndRegisterTLD(bytes,bytes,bytes)") ^
        keccak256("proveAndRegisterDefaultTLD(bytes,bytes,bytes)") ^
        keccak256("registerTLD(bytes,bytes)") ^
        keccak256("oracle()")
    );

    Root public root;
    DNSSEC public oracle;
    address public registrar;

    constructor(Root _root, DNSSEC _oracle, address _registrar) public {
        root = _root;
        oracle = _oracle;
        registrar = _registrar;
    }

    function proveAndRegisterTLD(bytes calldata name, bytes calldata input, bytes calldata proof) external {
        registerTLD(name, oracle.submitRRSets(input, proof));
    }

    function proveAndRegisterDefaultTLD(bytes calldata name, bytes calldata input, bytes calldata proof) external {
        oracle.submitRRSets(input, proof);
        registerTLD(name, "");
    }

    function registerTLD(bytes memory name, bytes memory proof) public {
        bytes32 label = getLabel(name);

        address addr = getAddress(name, proof);
        root.setSubnodeOwner(label, addr);
    }

    function getLabel(bytes memory name) internal view returns (bytes32) {
        uint len = name.readUint8(0);

        require(name.length == len + 2);

        return name.keccak(1, len);
    }

    function getAddress(bytes memory name, bytes memory proof) internal view returns (address) {
        // Add "nic." to the front of the name.
        Buffer.buffer memory buf;
        buf.init(name.length + 4);
        buf.append("\x03nic");
        buf.append(name);

        address addr;
        bool found;
        (addr, found) = DNSClaimChecker.getOwnerAddress(oracle, buf.buf, proof);
        if (!found) {
            // If there is no TXT record, we ensure that the TLD actually exists with a DS record.
            // This prevents registering bogus TLDs.
            require(getDSHash(name) != bytes20(0));
            return registrar;
        }

        return addr;
    }

    function getDSHash(bytes memory name) internal view returns (bytes20) {
        bytes20 hash;
        (,, hash) = oracle.rrdata(TYPE_DS, name);

        return hash;
    }

    function supportsInterface(bytes4 interfaceID) external pure returns (bool) {
        return interfaceID == INTERFACE_META_ID ||
               interfaceID == ROOT_REGISTRATION_ID;
    }

}
