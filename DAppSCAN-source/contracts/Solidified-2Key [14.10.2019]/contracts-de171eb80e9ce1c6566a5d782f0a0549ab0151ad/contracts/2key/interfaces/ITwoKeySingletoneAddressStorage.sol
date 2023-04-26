pragma solidity ^0.4.24;
/**
 * @author Nikola Madjarevic
 * Created at 12/24/18
 */
contract ITwoKeySingletoneAddressStorage {
    function getContractAddress(string contractName) external view returns (address);
}
