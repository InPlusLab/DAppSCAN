//SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./libraries/Endian.sol";
//SWC-135-Code With No Effects:L10
import "./interfaces/ERC20Interface.sol";

import "./Verify.sol";
import "./Owned.sol";

// ----------------------------------------------------------------------------
// Contract function to receive approval and execute function in one call
//
// Borrowed from MiniMeToken
// ----------------------------------------------------------------------------
abstract contract ApproveAndCallFallBack {
    function receiveApproval(
        address from,
        uint256 tokens,
        address token,
        bytes memory data
    ) public virtual;
}

contract Oracled is Owned {
    mapping(address => bool) public oracles;

    modifier onlyOracle() {
        require(
            oracles[msg.sender] == true,
            "Account is not a registered oracle"
        );

        _;
    }

    function regOracle(address _newOracle) public onlyOwner {
        require(!oracles[_newOracle], "Oracle is already registered");

        oracles[_newOracle] = true;
    }

    function unregOracle(address _remOracle) public onlyOwner {
        require(oracles[_remOracle] == true, "Oracle is not registered");

        delete oracles[_remOracle];
    }
}

// ----------------------------------------------------------------------------
// RFOX Bridge contract lock and release swap amount for each cross chain swap
//
// ----------------------------------------------------------------------------
contract ETHWAXBRIDGE is Oracled, Verify {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // RFOX Token address
    // Only using this address for bridging
    IERC20 public rfox;
    // Threshold meaning the minimum requirement for oracle confirmations
    uint8 public threshold;
    // ChainID for RFOX Bridge
    uint8 public thisChainId;
    // How many locked token in ETHWAXBRIDGE
    uint256 public totalLocked;
    // Mapping from transaction ID
    mapping(uint64 => mapping(address => bool)) signed;
    mapping(uint64 => bool) public claimed;

    event Bridge(
        address indexed from,
        string to,
        uint256 tokens,
        uint256 chainId
    );
    event Claimed(uint64 id, address to, uint256 tokens);

    struct BridgeData {
        uint64 id;
        uint32 ts;
        uint64 fromAddr;
        uint256 quantity;
        uint64 symbolRaw;
        uint8 chainId;
        address toAddress;
    }

    event Locked(address from, uint256 amount);
    event Released(address to, uint256 amount);

    // ------------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------------
    constructor(IERC20 rfoxAddress) public {
        uint8 chainId;

        threshold = 3;
        rfox = rfoxAddress;

        assembly {
            chainId := chainid()
        }

        thisChainId = chainId;
    }

    // ------------------------------------------------------------------------
    // Moves tokens to the inaccessible account and then sends event for the oracles
    // to monitor and issue on other chain
    // to : WAX address
    // tokens : number of tokens in satoshis
    // chainId : The chain id that they will be sent to
    // ------------------------------------------------------------------------

    function bridge(
        string memory to,
        uint256 tokens,
        uint256 chainid
    ) public returns (bool success) {
        lock(msg.sender, tokens);

        emit Bridge(msg.sender, to, tokens, chainid);
        emit Locked(msg.sender, tokens);

        return true;
    }

    // ------------------------------------------------------------------------
    // Claim tokens sent using signatures supplied to the other chain
    // ------------------------------------------------------------------------

    function verifySigData(bytes memory sigData)
        private
        returns (BridgeData memory)
    {
        BridgeData memory td;

        uint64 oracleQuantity = 0;
        uint64 id;
        uint32 ts;
        uint64 fromAddr;
        uint64 symbolRaw;
        uint8 chainId;
        address toAddress;

        assembly {
            id := mload(add(add(sigData, 0x8), 0))
            ts := mload(add(add(sigData, 0x4), 8))
            fromAddr := mload(add(add(sigData, 0x8), 12))
            oracleQuantity := mload(add(add(sigData, 0x8), 20))
            symbolRaw := mload(add(add(sigData, 0x8), 28))
            chainId := mload(add(add(sigData, 0x1), 36))
            toAddress := mload(add(add(sigData, 0x14), 37))
        }

        uint256 reversedQuantity = Endian.reverse64(oracleQuantity);

        td.id = Endian.reverse64(id);
        td.ts = Endian.reverse32(ts);
        td.fromAddr = Endian.reverse64(fromAddr);
        td.quantity = uint256(reversedQuantity) * 1e10;
        td.symbolRaw = Endian.reverse64(symbolRaw);
        td.chainId = chainId;
        td.toAddress = toAddress;

        require(thisChainId == td.chainId, "Invalid Chain ID");
        require(
            block.timestamp < SafeMath.add(td.ts, (60 * 60 * 24 * 30)),
            "Bridge has expired"
        );

        require(!claimed[td.id], "Already Claimed");

        claimed[td.id] = true;

        return td;
    }

    function claim(bytes memory sigData, bytes[] calldata signatures)
        public
        returns (address toAddress)
    {
        BridgeData memory td = verifySigData(sigData);

        // verify signatures
        require(sigData.length == 69, "Signature data is the wrong size");
        require(
            signatures.length <= 10,
            "Maximum of 10 signatures can be provided"
        );

        bytes32 message = keccak256(sigData);

        uint8 numberSigs = 0;

        for (uint8 i = 0; i < signatures.length; i++) {
            address potential = Verify.recoverSigner(message, signatures[i]);

            // Check that they are an oracle and they haven't signed twice
            if (oracles[potential] && !signed[td.id][potential]) {
                signed[td.id][potential] = true;
                numberSigs++;

                if (numberSigs >= 10) {
                    break;
                }
            }
        }

        require(
            numberSigs >= threshold,
            "Not enough valid signatures provided"
        );

        release(td.toAddress, td.quantity);

        emit Claimed(td.id, td.toAddress, td.quantity);

        return td.toAddress;
    }

    function updateThreshold(uint8 newThreshold)
        public
        onlyOwner
        returns (bool success)
    {
        if (newThreshold > 0) {
            require(newThreshold <= 10, "Threshold has maximum of 10");

            threshold = newThreshold;

            return true;
        }

        return false;
    }

    // ------------------------------------------------------------------------
    // Don't accept ETH
    // ------------------------------------------------------------------------
    receive() external payable {
        revert();
    }

    // ------------------------------------------------------------------------
    // Owner can transfer out any accidentally sent ERC20 tokens
    // ------------------------------------------------------------------------
    function transferAnyERC20Token(IERC20 tokenAddress, uint256 tokens)
        public
        onlyOwner
    {
        // We never transfer our RFOX to another addresses
        require(tokenAddress != rfox, "Token locked");
        // Transfer any tokens
        tokenAddress.safeTransfer(owner, tokens);
    }

    /// @notice Function that lock the RFOX token when bridging
    /// @dev Internal function, only call when bridging
    /// @param from Owner of this bridge action
    /// @param amount Quantity RFOX for bridging of this bridge action
    function lock(address from, uint256 amount) internal {
        totalLocked = totalLocked.add(amount);
        rfox.safeTransferFrom(from, address(this), amount);

        emit Locked(from, amount);
    }

    /// @notice Function that release the RFOX token when bridging
    /// @dev Internal function, only call when bridging
    /// @param to Address of receive bridging token
    /// @param amount Quantity RFOX for bridging of this bridge action
    function release(address to, uint256 amount) internal {
        totalLocked = totalLocked.sub(amount);
        rfox.safeTransfer(to, amount);

        emit Released(to, amount);
    }
}
