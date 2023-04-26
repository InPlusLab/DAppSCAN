//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "../interfaces/IOracle.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MultiOracle is Ownable {
    mapping (address => address) public oracles;

    function setOracle(address _token, address _oracle) external onlyOwner{
        oracles[_token] = _oracle;
    }

    function consult(address _token) external view returns(uint256) {
        address oracle = oracles[_token];
        if (oracle != address (0)) {
            return IOracle(oracle).consult();
        }
        return 0;
    }
}