// "SPDX-License-Identifier: GPL-3.0-or-later"

pragma solidity 0.7.6;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/GSN/Context.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";

/**
 * @dev {ERC20} token, including:
 *
 *  - ability for holders to burn (destroy) their tokens
 *  - a minter role that allows for token minting (creation)
 *
 * This contract uses {AccessControl} to lock permissioned functions using the
 * different roles - head to its documentation for details.
 *
 * The account that deploys the contract will be granted the minter
 * role, as well as the default admin role, which will let it grant both minter
 * and pauser roles to another accounts
 */
contract ERC20PresetMinterPermitted is Context, AccessControl, ERC20Burnable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256(
            "EIP712Domain(string name,uint256 chainId,address verifyingContract)"
        );

    /// @notice The EIP-712 typehash for the permit struct used by the contract
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

    /// @notice A record of states for signing / validating signatures
    mapping(address => uint256) public nonces;

    /**
     * @dev Grants `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE` to the
     * account that deploys the contract.
     *
     * See {ERC20-constructor}.
     */
    constructor(
        string memory name,
        string memory symbol,
        address owner,
        uint8 decimals
    ) public ERC20(name, symbol) {
        _setupRole(DEFAULT_ADMIN_ROLE, owner);

        _setupRole(MINTER_ROLE, owner);

        _setupDecimals(decimals);
    }

    /**
     * @dev Creates `amount` new tokens for `to`.
     *
     * See {ERC20-_mint}.
     *
     * Requirements:
     *
     * - the caller must have the `MINTER_ROLE`.
     */
    function mint(address to, uint256 amount) public {
        require(
            hasRole(MINTER_ROLE, _msgSender()),
            "ERC20PresetMinterPermitted: must have minter role to mint"
        );
        _mint(to, amount);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20) {
        super._beforeTokenTransfer(from, to, amount);
    }

    /**
     * @notice Triggers an approval from owner to spends
     * @param owner The address to approve from
     * @param spender The address to be approved
     * @param amount The number of tokens that are approved (2^256-1 means infinite)
     * @param deadline The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function permit(
        address owner,
        address spender,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        bytes32 domainSeparator =
            keccak256(
                abi.encode(
                    DOMAIN_TYPEHASH,
                    keccak256(bytes(name())),
                    getChainId(),
                    address(this)
                )
            );
        bytes32 structHash =
            keccak256(
                abi.encode(
                    PERMIT_TYPEHASH,
                    owner,
                    spender,
                    amount,
                    nonces[owner]++,
                    deadline
                )
            );
        bytes32 digest =
            keccak256(
                abi.encodePacked("\x19\x01", domainSeparator, structHash)
            );
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "Permit: invalid signature");
        require(signatory == owner, "Permit: unauthorized");
        require(block.timestamp <= deadline, "Permit: signature expired");

        _approve(owner, spender, amount);
    }

    function getChainId() internal pure returns (uint256) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        return chainId;
    }
}
