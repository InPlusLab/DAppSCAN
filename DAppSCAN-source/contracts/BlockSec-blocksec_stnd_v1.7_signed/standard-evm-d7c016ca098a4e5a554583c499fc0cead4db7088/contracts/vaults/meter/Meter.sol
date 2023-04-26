// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/IStablecoin.sol";
import "./interfaces/IVaultFactory.sol";

/**
 * @title MeterToken
 * @dev This contract is template for MTR stablecoins
 */
contract MeterToken is AccessControl, IStablecoin, Ownable, ERC20 {
    // Create a new role identifier for the minter role
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant FACTORY_ROLE = keccak256("FACTORY_ROLE");

    bytes32 public DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH =
        0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint256) public nonces;

    /**
     * @dev Creates an instance of `MeterToken` where `name` and `symbol` is initialized.
     * Names and symbols can vary from the pegging currency
     */
    constructor(
        string memory name,
        string memory symbol,
        address manager
    ) ERC20(name, symbol) {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(MINTER_ROLE, _msgSender());
        _setupRole(PAUSER_ROLE, _msgSender());
        _setupRole(MINTER_ROLE, manager);
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes(name)),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
    }


    function mint(address to, uint256 amount) external override {
        // Check that the calling account has the minter role
        require(
            hasRole(MINTER_ROLE, msg.sender),
            "Meter: Caller is not a minter"
        );
        _mint(to, amount);
    }

    function mintFromVault(address factory, uint256 vaultId_, address to, uint256 amount) external override {
        require(hasRole(FACTORY_ROLE, factory), "IA");
        require(IVaultFactory(factory).getVault(vaultId_)  == _msgSender(), "Meter: Not from Vault");
    }

    function burn(uint256 amount) external override {
        // Check that the calling account has the burner role
        _burn(_msgSender(), amount);
    }

    function burnFrom(address account, uint256 amount) external override {
        uint256 currentAllowance = allowance(account, _msgSender());
        require(
            currentAllowance >= amount,
            "ERC20: burn amount exceeds allowance"
        );
        _approve(account, _msgSender(), currentAllowance - amount);
        _burn(account, amount);
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        require(deadline >= block.timestamp, "UniswapV2: EXPIRED");
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        PERMIT_TYPEHASH,
                        owner,
                        spender,
                        value,
                        nonces[owner]++,
                        deadline
                    )
                )
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(
            recoveredAddress != address(0) && recoveredAddress == owner,
            "Meter: INVALID_SIGNATURE"
        );
        _approve(owner, spender, value);
    }
}
