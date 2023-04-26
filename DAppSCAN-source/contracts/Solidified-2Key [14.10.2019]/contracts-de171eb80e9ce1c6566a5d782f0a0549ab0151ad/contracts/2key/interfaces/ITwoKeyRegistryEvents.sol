pragma solidity ^0.4.0;

contract ITwoKeyRegistryEvents {
    function getPlasmaToEthereum(address plasma) public view returns (address);
    function getEthereumToPlasma(address ethereum) public view returns (address);
}
