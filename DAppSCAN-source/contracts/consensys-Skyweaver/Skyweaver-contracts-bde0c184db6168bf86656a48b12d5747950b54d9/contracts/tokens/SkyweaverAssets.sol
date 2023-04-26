pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "../shop/SWSupplyManager.sol";

import "multi-token-standard/contracts/tokens/ERC1155PackedBalance/ERC1155MetaPackedBalance.sol";
import "multi-token-standard/contracts/tokens/ERC1155PackedBalance/ERC1155MintBurnPackedBalance.sol";


contract SkyweaverAssets is SWSupplyManager, ERC1155MintBurnPackedBalance, ERC1155MetaPackedBalance {}
