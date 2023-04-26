// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.6;

// Based on https://github.com/ensdomains/ens/blob/master/contracts/ENS.sol
interface IENS {
    function resolver(bytes32 node) external view returns (IENSResolver);
}

// Based on https://github.com/ensdomains/resolvers/blob/master/contracts/profiles/AddrResolver.sol
interface IENSResolver {
    function addr(bytes32 node) external view returns (address);
}
