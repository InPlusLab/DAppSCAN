//SPDX-License-Identifier: Unlicense
/*
░██████╗██████╗░███████╗███████╗██████╗░░░░░░░░██████╗████████╗░█████╗░██████╗░
██╔════╝██╔══██╗██╔════╝██╔════╝██╔══██╗░░░░░░██╔════╝╚══██╔══╝██╔══██╗██╔══██╗
╚█████╗░██████╔╝█████╗░░█████╗░░██║░░██║█████╗╚█████╗░░░░██║░░░███████║██████╔╝
░╚═══██╗██╔═══╝░██╔══╝░░██╔══╝░░██║░░██║╚════╝░╚═══██╗░░░██║░░░██╔══██║██╔══██╗
██████╔╝██║░░░░░███████╗███████╗██████╔╝░░░░░░██████╔╝░░░██║░░░██║░░██║██║░░██║
╚═════╝░╚═╝░░░░░╚══════╝╚══════╝╚═════╝░░░░░░░╚═════╝░░░░╚═╝░░░╚═╝░░╚═╝╚═╝░░╚═╝
*/
pragma solidity 0.8.11;

import "@openzeppelin/contracts/access/Ownable.sol";

interface IHorse {
    function mint(
        address _receiver,
        string memory _uri,
        uint256 _tokenId,
        uint256 _rarity,
        uint256 _age
    ) external;

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    function getPopularity(uint256 tokenId) external returns (uint256);

    function ownerOf(uint256 tokenId) external returns (address);

    function isApprovedForAll(address user, address operator)
        external
        returns (bool);
}

contract SwapHorse is Ownable {
    IHorse public oldHorse;

    event SwapHorses(address user, uint256[] tokenIds, address oldHorse);

    event BurnHorse(address user, uint256 tokenId, address oldHorse);

    constructor(address _oldHorse) {
        oldHorse = IHorse(_oldHorse);
    }

    function swapHorses(uint256[] memory _tokenIds) external {
        // check owner
        for (uint256 index = 0; index < _tokenIds.length; index++) {
            require(
                oldHorse.ownerOf(_tokenIds[index]) == msg.sender,
                "User is not owner."
            );
        }

        require(
            oldHorse.isApprovedForAll(msg.sender, address(this)),
            "Require approve contract."
        );

        for (uint256 index = 0; index < _tokenIds.length; index++) {
            oldHorse.transferFrom(
                msg.sender,
                address(this),
                _tokenIds[index]
            );
            emit BurnHorse(msg.sender, _tokenIds[index], address(oldHorse));
        }

        emit SwapHorses(msg.sender, _tokenIds, address(oldHorse));
    }
}
