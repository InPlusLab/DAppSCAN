// contracts/erc20/SuperRareToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.7.3;

import "@openzeppelin/contracts-upgradeable/presets/ERC20PresetMinterPauserUpgradeable.sol";
import "../InitializableV2.sol";


/** Upgradeable ERC20 token that is Detailed, Mintable, Pausable, Burnable. */
contract SuperRareToken is InitializableV2,
                           ERC20PresetMinterPauserUpgradeable
{
    string constant NAME = "SuperRare";

    string constant SYMBOL = "SR";

    // Defines number of Wei in 1 token
    // 18 decimals is standard - imitates relationship between Ether and Wei
    uint8 constant DECIMALS = 18;

    // 10^27 = 1 million (10^6) tokens, 18 decimal places
    // 1 TAUD = 1 * 10^18 wei
    uint256 constant INITIAL_SUPPLY = 1000000 * 10**uint256(DECIMALS);

    // for ERC20 approve transactions in compliance with EIP 2612:
    // https://github.com/ethereum/EIPs/blob/master/EIPS/eip-2612.md
    // code below, in constructor, and in permit function adapted from the audited reference Uniswap implementation:
    // https://github.com/Uniswap/uniswap-v2-core/blob/master/contracts/UniswapV2ERC20.sol
    bytes32 public DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint) public nonces;

    function init(address _owner) public initializer {
        // ERC20 has no initialize function

        // ERC20Burnable has no initialize function. Makes token burnable

        // Initialize call makes token pausable & gives pauserRole to owner
        // ERC20PausableUpgradeable.initialize(owner);

        // Initialize call makes token mintable & gives minterRole to msg.sender
        ERC20PresetMinterPauserUpgradeable.initialize(NAME, SYMBOL);

        // Mints initial token supply & transfers to _owner account
        _mint(_owner, INITIAL_SUPPLY);

        InitializableV2.initialize();

        // EIP712-compatible signature data
        uint256 chainId;
        // solium-disable security/no-inline-assembly
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(NAME)),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
    }
    //SWC-114-Transaction Order Dependence: 67-91
    function permit(
        address owner,
        address spender,
        uint value,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        // solium-disable security/no-block-members
        require(deadline >= block.timestamp, "SuperRareToken: Deadline has expired");
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(
            recoveredAddress != address(0) && recoveredAddress == owner,
            "SuperRareToken: Invalid signature"
        );
        _approve(owner, spender, value);
    }
}
