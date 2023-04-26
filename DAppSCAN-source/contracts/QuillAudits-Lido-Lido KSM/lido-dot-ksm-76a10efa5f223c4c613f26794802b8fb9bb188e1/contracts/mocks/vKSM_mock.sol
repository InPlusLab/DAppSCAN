// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../interfaces/IvKSM.sol";

contract vKSM_mock is ERC20("vKSM", "vKSM"), IvKSM {
    event UpwardTransfer(
        address from,
        bytes32 to,
        uint256 amount
    );

    constructor() {
        _mint(msg.sender, 10**9 * 10**18);
    }

    function relayTransferTo(bytes32 relayChainAccount, uint256 amount) override external {
        _burn(msg.sender, amount);

        emit UpwardTransfer(msg.sender, relayChainAccount, amount);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}