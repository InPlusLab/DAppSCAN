pragma solidity ^0.5.0;

import "@ensdomains/ens/contracts/ENS.sol";
import "@ensdomains/dnssec-oracle/contracts/DNSSEC.sol";
import "@ensdomains/dnssec-oracle/contracts/BytesUtils.sol";
import "@ensdomains/dnsregistrar/contracts/DNSClaimChecker.sol";
import "@ensdomains/buffer/contracts/Buffer.sol";
import "./Ownable.sol";

contract Root is Ownable {

    using BytesUtils for bytes;
    using Buffer for Buffer.buffer;

    bytes32 public constant ROOT_NODE = bytes32(0);
    bytes32 public constant ETH_NODE = keccak256("eth");

    uint16 constant public CLASS_INET = 1;
    uint16 constant public TYPE_TXT = 16;
    uint16 constant public TYPE_SOA = 6;

    ENS public ens;
    DNSSEC public oracle;

    address public registrar;

    event TLDRegistered(bytes32 indexed node, address indexed registrar);
    event RegistrarChanged(address indexed registrar);

    constructor(ENS _ens, DNSSEC _oracle, address _registrar) public {
        ens = _ens;
        oracle = _oracle;
        registrar = _registrar;
    }

    function proveAndRegisterTLD(bytes name, bytes input, bytes proof) external {
        registerTLD(name, oracle.submitRRSets(input, proof));
    }

    function setSubnodeOwner(bytes32 label, address owner) external onlyOwner {
        ens.setSubnodeOwner(ROOT_NODE, label, owner);
    }

    function setRegistrar(address _registrar) external onlyOwner {
        require(_registrar != address(0x0));
        registrar = _registrar;
        emit RegistrarChanged(registrar);
    }

    function registerTLD(bytes name, bytes proof) public {
        bytes32 label = getLabel(name);

        address addr = getAddress(name, proof);
        require(ens.owner(keccak256(ROOT_NODE, label)) != addr);
        require(label != ETH_NODE);

        ens.setSubnodeOwner(ROOT_NODE, label, addr);
        emit TLDRegistered(keccak256(ROOT_NODE, label), addr);
    }

    function setResolver(bytes32 node, address resolver) public onlyOwner {
        ens.setResolver(node, resolver);
    }

    function setOwner(bytes32 node, address owner) public onlyOwner {
        ens.setOwner(node, owner);
    }

    function setTTL(bytes32 node, uint64 ttl) public onlyOwner {
        ens.setTTL(node, ttl);
    }

    function getLabel(bytes memory name) internal view returns (bytes32) {
        uint len = name.readUint8(0);

        require(name.length == len + 2);

        return name.keccak(1, len);
    }

    function getAddress(bytes name, bytes proof) internal view returns (address) {
        // Add "nic." to the front of the name.
        Buffer.buffer memory buf;
        buf.init(name.length + 4);
        buf.append("\x03nic");
        buf.append(name);

        address addr;
        bool found;
        (addr, found) = DNSClaimChecker.getOwnerAddress(oracle, buf.buf, proof);
        if (!found) {
            // If there is no TXT record, we ensure that the TLD actually exists with a SOA record.
            // This prevents registering bogus TLDs.
            require(getSOAHash(buf.buf) != bytes20(0));
            return registrar;
        }

        return addr;
    }

    function getSOAHash(bytes name) internal view returns (bytes20) {
        Buffer.buffer memory buf;
        buf.init(name.length + 5);
        buf.append("\x04_ens");
        buf.append(name);

        bytes20 hash;
        (,, hash) = oracle.rrdata(TYPE_SOA, buf.buf);

        return hash;
    }
}
