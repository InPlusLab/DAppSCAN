// SPDX-License-Identifier: Apache-2.0

// File: contracts/UChildERC20.sol

pragma solidity 0.6.12;

import "./libraries/ERC20.sol";
import "./libraries/access/AccessControlMixin.sol";
import "./interfaces/IChildToken.sol";
import "./libraries/Initializable.sol";
import "./libraries/meta-transaction/NativeMetaTransaction.sol";
import "./libraries/meta-transaction/MaticGasAbstraction.sol";
import "./libraries/meta-transaction/Permit.sol";
import "./libraries/ContextMixin.sol";


contract UChildERC20 is
    ERC20,
    IChildToken,
    AccessControlMixin,
    Initializable,
    NativeMetaTransaction,
    ContextMixin,
    Permit,
    MaticGasAbstraction
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE");
    string public constant EIP712_VERSION = "1";

    constructor() public ERC20("", "") {}

    /**
     * @notice Initialize the contract after it has been proxified
     * @dev meant to be called once immediately after deployment
     */
    function initialize(
        string calldata newName,
        string calldata newSymbol,
        uint8 newDecimals,
        address childChainManager
    ) external initializer {
        _setName(newName);
        _setSymbol(newSymbol);
        _setDecimals(newDecimals);
        _setupContractId(string(abi.encodePacked("Child", newSymbol)));
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(MINTER_ROLE, _msgSender());
        _setupRole(DEPOSITOR_ROLE, childChainManager);
        _setDomainSeparator(newName, EIP712_VERSION);
    }

    // This is to support Native meta transactions
    // never use msg.sender directly, use _msgSender() instead
    function _msgSender()
        internal
        virtual
        override
        view
        returns (address payable sender)
    {
        return ContextMixin.msgSender();
    }

    function updateMetadata(string calldata newName, string calldata newSymbol)
        external
        only(DEFAULT_ADMIN_ROLE)
    {
        _setName(newName);
        _setSymbol(newSymbol);
        _setDomainSeparator(newName, EIP712_VERSION);
    }

    /**
     * @notice called when token is deposited on root chain
     * @dev Should be callable only by ChildChainManager
     * Should handle deposit by minting the required amount for user
     * Make sure minting is done only by this function
     * @param user user address for whom deposit is being done
     * @param depositData abi encoded amount
     */
    function deposit(address user, bytes calldata depositData)
        external
        override
        only(DEPOSITOR_ROLE)
    {
        uint256 amount = abi.decode(depositData, (uint256));
        _mint(user, amount);
    }

    /**
     * @notice called when user wants to withdraw tokens back to root chain
     * @dev Should burn user's tokens. This transaction will be verified when exiting on root chain
     * @param amount amount of tokens to withdraw
     */
    function withdraw(uint256 amount) external virtual {
        _burn(_msgSender(), amount);
    }

    /**
     * @notice Update allowance with a signed permit
     * @param owner       Token owner's address (Authorizer)
     * @param spender     Spender's address
     * @param value       Amount of allowance
     * @param deadline    Expiration time, seconds since the epoch
     * @param v           v of the signature
     * @param r           r of the signature
     * @param s           s of the signature
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual {
        _permit(owner, spender, value, deadline, v, r, s);
    }

    /**
     * @notice Execute a transfer with a signed authorization
     * @param from          Payer's address (Authorizer)
     * @param to            Payee's address
     * @param value         Amount to be transferred
     * @param validAfter    The time after which this is valid (unix time)
     * @param validBefore   The time before which this is valid (unix time)
     * @param nonce         Unique nonce
     * @param v             v of the signature
     * @param r             r of the signature
     * @param s             s of the signature
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
    ) external virtual {
        _transferWithAuthorization(
            from,
            to,
            value,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );
    }

    /**
     * @notice Update allowance with a signed authorization
     * @param owner         Token owner's address (Authorizer)
     * @param spender       Spender's address
     * @param value         Amount of allowance
     * @param validAfter    The time after which this is valid (unix time)
     * @param validBefore   The time before which this is valid (unix time)
     * @param nonce         Unique nonce
     * @param v             v of the signature
     * @param r             r of the signature
     * @param s             s of the signature
     */
    function approveWithAuthorization(
        address owner,
        address spender,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual {
        _approveWithAuthorization(
            owner,
            spender,
            value,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );
    }

    /**
     * @notice Increase allowance with a signed authorization
     * @param owner         Token owner's address (Authorizer)
     * @param spender       Spender's address
     * @param increment     Amount of increase in allowance
     * @param validAfter    The time after which this is valid (unix time)
     * @param validBefore   The time before which this is valid (unix time)
     * @param nonce         Unique nonce
     * @param v             v of the signature
     * @param r             r of the signature
     * @param s             s of the signature
     */
    function increaseAllowanceWithAuthorization(
        address owner,
        address spender,
        uint256 increment,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual {
        _increaseAllowanceWithAuthorization(
            owner,
            spender,
            increment,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );
    }

    /**
     * @notice Decrease allowance with a signed authorization
     * @param owner         Token owner's address (Authorizer)
     * @param spender       Spender's address
     * @param decrement     Amount of decrease in allowance
     * @param validAfter    The time after which this is valid (unix time)
     * @param validBefore   The time before which this is valid (unix time)
     * @param nonce         Unique nonce
     * @param v             v of the signature
     * @param r             r of the signature
     * @param s             s of the signature
     */
    function decreaseAllowanceWithAuthorization(
        address owner,
        address spender,
        uint256 decrement,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual {
        _decreaseAllowanceWithAuthorization(
            owner,
            spender,
            decrement,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );
    }

    /**
     * @notice Execute a withdrawal with a signed authorization. This is used to
     * transfer tokens back to the root chain.
     * @param owner         Token owner's address (Authorizer)
     * @param value         Amount to be withdrawn
     * @param validAfter    The time after which this is valid (unix time)
     * @param validBefore   The time before which this is valid (unix time)
     * @param nonce         Unique nonce
     * @param v             v of the signature
     * @param r             r of the signature
     * @param s             s of the signature
     */
    function withdrawWithAuthorization(
        address owner,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual {
        _withdrawWithAuthorization(
            owner,
            value,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );
    }

    /**
     * @notice Attempt to cancel an authorization
     * @dev Works only if the authorization is not yet used.
     * @param authorizer    Authorizer's address
     * @param nonce         Nonce of the authorization
     * @param v             v of the signature
     * @param r             r of the signature
     * @param s             s of the signature
     */
    function cancelAuthorization(
        address authorizer,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual {
        _cancelAuthorization(authorizer, nonce, v, r, s);
    }

    function mint(address account, uint256 amount) public {
        require(hasRole(MINTER_ROLE, msg.sender));
        _mint(account, amount);
    }
    
    function burnFrom(address account, uint256 amount) public {
        uint256 currentAllowance = this.allowance(account, _msgSender());
        require(currentAllowance >= amount, "ERC20: burn amount exceeds allowance");
        _approve(account, _msgSender(), currentAllowance - amount);
        _burn(account, amount);
    }
}