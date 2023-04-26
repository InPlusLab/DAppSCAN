// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IEdenToken.sol";
import "./lib/AccessControl.sol";

/**
 * @title EdenToken
 * @dev ERC-20 with minting + add-ons to allow for offchain signing
 * See EIP-712, EIP-2612, and EIP-3009 for details
 */
contract EdenToken is AccessControl, IEdenToken {
    /// @notice EIP-20 token name for this token
    string public override name = "Eden";

    /// @notice EIP-20 token symbol for this token
    string public override symbol = "EDEN";

    /// @notice EIP-20 token decimals for this token
    uint8 public override constant decimals = 18;

    /// @notice Total number of tokens in circulation
    uint256 public override totalSupply;

    /// @notice Max total supply
    uint256 public constant override maxSupply = 250_000_000e18; // 250 million

    /// @notice Minter role
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice Address which may change token metadata
    address public override metadataManager;

    /// @dev Allowance amounts on behalf of others
    mapping (address => mapping (address => uint256)) public override allowance;

    /// @dev Official record of token balanceOf for each account
    mapping (address => uint256) public override balanceOf;

    /// @notice The EIP-712 typehash for the contract's domain
    /// keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
    bytes32 public constant override DOMAIN_TYPEHASH = 0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;
    
    /// @notice The EIP-712 version hash
    /// keccak256("1");
    bytes32 public constant override VERSION_HASH = 0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6;

    /// @notice The EIP-712 typehash for permit (EIP-2612)
    /// keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant override PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    /// @notice The EIP-712 typehash for transferWithAuthorization (EIP-3009)
    /// keccak256("TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)");
    bytes32 public constant override TRANSFER_WITH_AUTHORIZATION_TYPEHASH = 0x7c7c6cdb67a18743f49ec6fa9b35f50d52ed05cbed4cc592e13b44501c1a2267;

    /// @notice The EIP-712 typehash for receiveWithAuthorization (EIP-3009)
    /// keccak256("ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)")
    bytes32 public constant override RECEIVE_WITH_AUTHORIZATION_TYPEHASH = 0xd099cc98ef71107a616c4f0f941f04c322d8e254fe26b3c6668db87aae413de8;

    /// @notice A record of states for signing / validating signatures
    mapping (address => uint) public override nonces;

    /// @dev authorizer address > nonce > state (true = used / false = unused)
    mapping (address => mapping (bytes32 => bool)) public authorizationState;

    /**
     * @notice Construct a new Eden token
     * @param _admin Default admin role
     */
    constructor(address _admin) {
        metadataManager = _admin;
        emit MetadataManagerChanged(address(0), metadataManager);
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /**
     * @notice Change the metadataManager address
     * @param newMetadataManager The address of the new metadata manager
     * @return true if successful
     */
    function setMetadataManager(address newMetadataManager) external override returns (bool) {
        require(msg.sender == metadataManager, "Eden::setMetadataManager: only MM can change MM");
        emit MetadataManagerChanged(metadataManager, newMetadataManager);
        metadataManager = newMetadataManager;
        return true;
    }

    /**
     * @notice Mint new tokens
     * @param dst The address of the destination account
     * @param amount The number of tokens to be minted
     * @return Boolean indicating success of mint
     */
    function mint(address dst, uint256 amount) external override returns (bool) {
        require(hasRole(MINTER_ROLE, msg.sender), "Eden::mint: only minters can mint");
        require(totalSupply + amount <= maxSupply, "Eden::mint: exceeds max supply");
        require(dst != address(0), "Eden::mint: cannot transfer to the zero address");

        totalSupply = totalSupply + amount;
        balanceOf[dst] = balanceOf[dst] + amount;
        emit Transfer(address(0), dst, amount);
        return true;
    }

    /**
     * @notice Burn tokens
     * @param amount The number of tokens to burn
     * @return Boolean indicating success of burn
     */
    function burn(uint256 amount) external override returns (bool) {
        balanceOf[msg.sender] = balanceOf[msg.sender] - amount;
        totalSupply = totalSupply - amount;
        
        emit Transfer(msg.sender, address(0), amount);
        return true;
    }

    /**
     * @notice Update the token name and symbol
     * @param tokenName The new name for the token
     * @param tokenSymbol The new symbol for the token
     * @return true if successful
     */
    function updateTokenMetadata(string memory tokenName, string memory tokenSymbol) external override returns (bool) {
        require(msg.sender == metadataManager, "Eden::updateTokenMeta: only MM can update token metadata");
        name = tokenName;
        symbol = tokenSymbol;
        emit TokenMetaUpdated(name, symbol);
        return true;
    }

    /**
     * @notice Approve `spender` to transfer up to `amount` from `src`
     * @dev This will overwrite the approval amount for `spender`
     * and is subject to issues noted [here](https://eips.ethereum.org/EIPS/eip-20#approve)
     * It is recommended to use increaseAllowance and decreaseAllowance instead
     * @param spender The address of the account which may transfer tokens
     * @param amount The number of tokens that are approved (2^256-1 means infinite)
     * @return Whether or not the approval succeeded
     */
    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    /**
     * @notice Increase the allowance by a given amount
     * @param spender Spender's address
     * @param addedValue Amount of increase in allowance
     * @return True if successful
     */
    function increaseAllowance(address spender, uint256 addedValue)
        external override
        returns (bool)
    {
        _approve(
            msg.sender, 
            spender, 
            allowance[msg.sender][spender] + addedValue
        );
        return true;
    }

    /**
     * @notice Decrease the allowance by a given amount
     * @param spender Spender's address
     * @param subtractedValue Amount of decrease in allowance
     * @return True if successful
     */
    function decreaseAllowance(address spender, uint256 subtractedValue)
        external override
        returns (bool)
    {
        _approve(
            msg.sender,
            spender,
            allowance[msg.sender][spender] - subtractedValue
        );
        return true;
    }

    /**
     * @notice Triggers an approval from owner to spender
     * @param owner The address to approve from
     * @param spender The address to be approved
     * @param value The number of tokens that are approved (2^256-1 means infinite)
     * @param deadline The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function permit(
        address owner, 
        address spender, 
        uint256 value, 
        uint256 deadline, 
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) external override {
        require(deadline >= block.timestamp, "Eden::permit: signature expired");

        bytes32 encodeData = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline));
        _validateSignedData(owner, encodeData, v, r, s);

        _approve(owner, spender, value);
    }

    /**
     * @notice Transfer `amount` tokens from `msg.sender` to `dst`
     * @param dst The address of the destination account
     * @param amount The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transfer(address dst, uint256 amount) external override returns (bool) {
        _transferTokens(msg.sender, dst, amount);
        return true;
    }

    /**
     * @notice Transfer `amount` tokens from `src` to `dst`
     * @param src The address of the source account
     * @param dst The address of the destination account
     * @param amount The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transferFrom(address src, address dst, uint256 amount) external override returns (bool) {
        address spender = msg.sender;
        uint256 spenderAllowance = allowance[src][spender];

        if (spender != src && spenderAllowance != type(uint256).max) {
            uint256 newAllowance = spenderAllowance - amount;
            allowance[src][spender] = newAllowance;

            emit Approval(src, spender, newAllowance);
        }

        _transferTokens(src, dst, amount);
        return true;
    }

    /**
     * @notice Transfer tokens with a signed authorization
     * @param from Payer's address (Authorizer)
     * @param to Payee's address
     * @param value Amount to be transferred
     * @param validAfter The time after which this is valid (unix time)
     * @param validBefore The time before which this is valid (unix time)
     * @param nonce Unique nonce
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        require(block.timestamp > validAfter, "Eden::transferWithAuth: auth not yet valid");
        require(block.timestamp < validBefore, "Eden::transferWithAuth: auth expired");
        require(!authorizationState[from][nonce],  "Eden::transferWithAuth: auth already used");

        bytes32 encodeData = keccak256(abi.encode(TRANSFER_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce));
        _validateSignedData(from, encodeData, v, r, s);

        authorizationState[from][nonce] = true;
        emit AuthorizationUsed(from, nonce);

        _transferTokens(from, to, value);
    }

    /**
     * @notice Receive a transfer with a signed authorization from the payer
     * @dev This has an additional check to ensure that the payee's address matches
     * the caller of this function to prevent front-running attacks.
     * @param from Payer's address (Authorizer)
     * @param to Payee's address
     * @param value Amount to be transferred
     * @param validAfter The time after which this is valid (unix time)
     * @param validBefore The time before which this is valid (unix time)
     * @param nonce Unique nonce
     * @param v v of the signature
     * @param r r of the signature
     * @param s s of the signature
     */
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        require(to == msg.sender, "Eden::receiveWithAuth: caller must be the payee");
        require(block.timestamp > validAfter, "Eden::receiveWithAuth: auth not yet valid");
        require(block.timestamp < validBefore, "Eden::receiveWithAuth: auth expired");
        require(!authorizationState[from][nonce],  "Eden::receiveWithAuth: auth already used");

        bytes32 encodeData = keccak256(abi.encode(RECEIVE_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce));
        _validateSignedData(from, encodeData, v, r, s);

        authorizationState[from][nonce] = true;
        emit AuthorizationUsed(from, nonce);

        _transferTokens(from, to, value);
    }

    /**
     * @notice EIP-712 Domain separator
     * @return Separator
     */
    function getDomainSeparator() public view override returns (bytes32) {
        return keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(name)),
                VERSION_HASH,
                block.chainid,
                address(this)
            )
        );
    }

    /**
     * @notice Recovers address from signed data and validates the signature
     * @param signer Address that signed the data
     * @param encodeData Data signed by the address
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function _validateSignedData(address signer, bytes32 encodeData, uint8 v, bytes32 r, bytes32 s) internal view {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                getDomainSeparator(),
                encodeData
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        // Explicitly disallow authorizations for address(0) as ecrecover returns address(0) on malformed messages
        require(recoveredAddress != address(0) && recoveredAddress == signer, "Eden::validateSig: invalid signature");
    }

    /**
     * @notice Approval implementation
     * @param owner The address of the account which owns tokens
     * @param spender The address of the account which may transfer tokens
     * @param amount The number of tokens that are approved (2^256-1 means infinite)
     */
    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "Eden::_approve: approve from the zero address");
        require(spender != address(0), "Eden::_approve: approve to the zero address");
        allowance[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @notice Transfer implementation
     * @param from The address of the account which owns tokens
     * @param to The address of the account which is receiving tokens
     * @param value The number of tokens that are being transferred
     */
    function _transferTokens(address from, address to, uint256 value) internal {
        require(to != address(0), "Eden::_transferTokens: cannot transfer to the zero address");

        balanceOf[from] = balanceOf[from] - value;
        balanceOf[to] = balanceOf[to] + value;
        emit Transfer(from, to, value);
    }
}