pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "../shop/SWSupplyManager.sol";

import "multi-token-standard/contracts/tokens/ERC1155/ERC1155Meta.sol";
import "multi-token-standard/contracts/tokens/ERC1155/ERC1155MintBurn.sol";


contract SkyweaverCurrencies is SWSupplyManager, ERC1155MintBurn, ERC1155Meta {}
