// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";


library Random {
    using SafeMath for uint256;
    //SWC-120-Weak Sources of Randomness from Chain Attributes: L11-L35
    function computerSeed() internal view returns (uint256) {
        uint256 seed =
        uint256(
            keccak256(
                abi.encodePacked(
                    (block.timestamp)
                    .add(block.difficulty)
                    .add(
                        (
                        uint256(
                            keccak256(abi.encodePacked(block.coinbase))
                        )
                        ) / (block.timestamp)
                    )
                    .add(block.gaslimit)
                    .add(
                        (uint256(keccak256(abi.encodePacked(msg.sender)))) /
                        (block.timestamp)
                    )
                    .add(block.number)
                )
            )
        );
        return seed;
    }
}