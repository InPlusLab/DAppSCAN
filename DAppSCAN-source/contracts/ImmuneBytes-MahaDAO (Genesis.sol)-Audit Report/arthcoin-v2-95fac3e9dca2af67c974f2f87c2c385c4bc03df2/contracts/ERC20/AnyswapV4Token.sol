// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import {ERC20Custom} from './ERC20Custom.sol';
import {IAnyswapV4Token} from './IAnyswapV4Token.sol';
import {AccessControl} from '../access/AccessControl.sol';

interface IApprovalReceiver {
    function onTokenApproval(
        address,
        uint256,
        bytes calldata
    ) external returns (bool);
}

interface ITransferReceiver {
    function onTokenTransfer(
        address,
        uint256,
        bytes calldata
    ) external returns (bool);
}

abstract contract AnyswapV4Token is
    ERC20Custom,
    AccessControl,
    IAnyswapV4Token
{
    bytes32 public immutable DOMAIN_SEPARATOR;

    bytes32 public constant BRIDGE_ROLE = keccak256('BRIDGE_ROLE');
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256(
            'Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)'
        );
    bytes32 public constant TRANSFER_TYPEHASH =
        keccak256(
            'Transfer(address owner,address to,uint256 value,uint256 nonce,uint256 deadline)'
        );

    mapping(address => uint256) public override nonces;

    event LogSwapin(
        bytes32 indexed txhash,
        address indexed account,
        uint256 amount
    );

    event LogSwapout(
        address indexed account,
        address indexed bindaddr,
        uint256 amount
    );

    modifier onlyBridge {
        require(
            hasRole(BRIDGE_ROLE, _msgSender()),
            'AnyswapV4Token: forbidden'
        );
        _;
    }

    constructor(string memory name) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'
                ),
                keccak256(bytes(name)),
                keccak256(bytes('1')),
                chainId,
                address(this)
            )
        );

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    function approveAndCall(
        address spender,
        uint256 value,
        bytes calldata data
    ) external override returns (bool) {
        _approve(msg.sender, spender, value);
        return
            IApprovalReceiver(spender).onTokenApproval(msg.sender, value, data);
    }

    function transferAndCall(
        address to,
        uint256 value,
        bytes calldata data
    ) external override returns (bool) {
        require(to != address(0) || to != address(this));

        uint256 balance = balanceOf(msg.sender);
        require(
            balance >= value,
            'AnyswapV3ERC20: transfer amount exceeds balance'
        );

        _transfer(msg.sender, to, value);
        return ITransferReceiver(to).onTokenTransfer(msg.sender, value, data);
    }

    function transferWithPermit(
        address target,
        address to,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override returns (bool) {
        require(block.timestamp <= deadline, 'AnyswapV3ERC20: Expired permit');

        bytes32 hashStruct =
            keccak256(
                abi.encode(
                    TRANSFER_TYPEHASH,
                    target,
                    to,
                    value,
                    nonces[target]++,
                    deadline
                )
            );

        require(
            _verifyEIP712(target, hashStruct, v, r, s) ||
                _verifyPersonalSign(target, hashStruct, v, r, s)
        );

        // NOTE: is this check needed, was there in the refered contract.
        require(to != address(0) || to != address(this));
        require(
            balanceOf(target) >= value,
            'AnyswapV3ERC20: transfer amount exceeds balance'
        );

        _transfer(target, to, value);
        return true;
    }

    function permit(
        address target,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public override {
        require(block.timestamp <= deadline, 'AnyswapV3ERC20: Expired permit');

        bytes32 hashStruct =
            keccak256(
                abi.encode(
                    PERMIT_TYPEHASH,
                    target,
                    spender,
                    value,
                    nonces[target]++,
                    deadline
                )
            );

        require(
            _verifyEIP712(target, hashStruct, v, r, s) ||
                _verifyPersonalSign(target, hashStruct, v, r, s)
        );

        _approve(target, spender, value);
        emit Approval(target, spender, value);
    }

    /// @dev Only Auth needs to be implemented
    function Swapin(
        bytes32 txhash,
        address account,
        uint256 amount
    ) public override onlyBridge returns (bool) {
        _mint(account, amount);
        emit LogSwapin(txhash, account, amount);
        return true;
    }

    function Swapout(uint256 amount, address bindaddr)
        public
        override
        onlyBridge
        returns (bool)
    {
        require(bindaddr != address(0), 'AnyswapV4ERC20: address(0x0)');

        _burn(msg.sender, amount);
        emit LogSwapout(msg.sender, bindaddr, amount);
        return true;
    }

    function _verifyEIP712(
        address target,
        bytes32 hashStruct,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal view returns (bool) {
        bytes32 hash =
            keccak256(
                abi.encodePacked('\x19\x01', DOMAIN_SEPARATOR, hashStruct)
            );
        address signer = ecrecover(hash, v, r, s);

        return (signer != address(0) && signer == target);
    }

    /// @dev Builds a _prefixed hash to mimic the behavior of eth_sign.
    function _prefixed(bytes32 hash) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked('\x19Ethereum Signed Message:\n32', hash)
            );
    }

    function _verifyPersonalSign(
        address target,
        bytes32 hashStruct,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal pure returns (bool) {
        bytes32 hash = _prefixed(hashStruct);
        address signer = ecrecover(hash, v, r, s);
        return (signer != address(0) && signer == target);
    }
}
