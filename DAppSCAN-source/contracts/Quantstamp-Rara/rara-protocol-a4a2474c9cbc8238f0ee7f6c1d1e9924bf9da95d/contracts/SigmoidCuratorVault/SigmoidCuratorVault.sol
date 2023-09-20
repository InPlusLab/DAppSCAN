//SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../Token/IStandard1155.sol";
import "../Config/IAddressManager.sol";
import "./SigmoidCuratorVaultStorage.sol";
import "./Curve/Sigmoid.sol";

/// @title SigmoidCuratorVault
/// @dev This contract tracks tokens in a sigmoid bonding curve per Taker NFT.
/// When users spend reactions against a Taker NFT, it will use the Curator Liability
/// to buy curator tokens against that Taker NFT and allocate to various parties.
/// The curator tokens will be priced via the sigmoid curve.  The params that control
/// the shape of the sigmoid are set in the parameter manager.
/// At any point in time the owners of the curator tokens can sell them back to the
/// bonding curve.
contract SigmoidCuratorVault is
    ReentrancyGuardUpgradeable,
    Sigmoid,
    SigmoidCuratorVaultStorageV1
{
    /// @dev Use the safe methods when interacting with transfers with outside ERC20s
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @dev verifies that the calling address is the reaction vault
    modifier onlyCuratorVaultPurchaser() {
        require(
            addressManager.roleManager().isCuratorVaultPurchaser(msg.sender),
            "Not Admin"
        );
        _;
    }

    /// @dev Event triggered when curator tokens are purchased
    event CuratorTokensBought(
        uint256 indexed curatorTokenId,
        uint256 nftChainId,
        address nftAddress,
        uint256 nftId,
        IERC20Upgradeable paymentToken,
        uint256 paymentTokenPaid,
        uint256 curatorTokensBought,
        bool isTakerPosition
    );

    /// @dev Event triggered when curator tokens are sold
    event CuratorTokensSold(
        uint256 indexed curatorTokenId,
        uint256 paymentTokenRefunded,
        uint256 curatorTokensSold
    );

    /// @dev initializer to call after deployment, can only be called once
    function initialize(address _addressManager, IStandard1155 _curatorTokens)
        public
        initializer
    {
        // Save the address manager
        addressManager = IAddressManager(_addressManager);

        // Save the curator token contract
        curatorTokens = _curatorTokens;
    }

    /// @dev get a unique token ID for a given nft address and nft ID
    function getTokenId(
        uint256 nftChainId,
        address nftAddress,
        uint256 nftId,
        IERC20Upgradeable paymentToken
    ) external pure returns (uint256) {
        return _getTokenId(nftChainId, nftAddress, nftId, paymentToken);
    }

    function _getTokenId(
        uint256 nftChainId,
        address nftAddress,
        uint256 nftId,
        IERC20Upgradeable paymentToken
    ) internal pure returns (uint256) {
        return
            uint256(
                keccak256(
                    abi.encode(nftChainId, nftAddress, nftId, paymentToken)
                )
            );
    }

    /// @dev Buy curator Tokens when reactions are spent.
    /// The reaction vault is the only account allowed to call this.
    /// @return Returns the amount of curator tokens purchased.
    //SWC-107-Reentrancy: L95-L57
    function buyCuratorTokens(
        uint256 nftChainId,
        address nftAddress,
        uint256 nftId,
        IERC20Upgradeable paymentToken,
        uint256 paymentAmount,
        address mintToAddress,
        bool isTakerPosition
    ) external onlyCuratorVaultPurchaser returns (uint256) {
        // Get the curator token token ID
        uint256 curatorTokenId = _getTokenId(
            nftChainId,
            nftAddress,
            nftId,
            paymentToken
        );

        //
        // Pull value from ReactionVault
        //
        paymentToken.safeTransferFrom(msg.sender, address(this), paymentAmount);

        // Get curve params
        (uint256 a, uint256 b, uint256 c) = addressManager
            .parameterManager()
            .bondingCurveParams();

        // Calculate the amount of tokens that will be minted based on the price
        uint256 curatorTokenAmount = calculateTokensBoughtFromPayment(
            int256(a),
            int256(b),
            int256(c),
            int256(curatorTokenSupply[curatorTokenId]),
            int256(reserves[curatorTokenId]),
            int256(paymentAmount)
        );

        // Update the amounts
        reserves[curatorTokenId] += paymentAmount;
        curatorTokenSupply[curatorTokenId] += curatorTokenAmount;

        // Mint the tokens
        curatorTokens.mint(
            mintToAddress,
            curatorTokenId,
            curatorTokenAmount,
            new bytes(0)
        );

        // Emit the event
        emit CuratorTokensBought(
            curatorTokenId,
            nftChainId,
            nftAddress,
            nftId,
            paymentToken,
            paymentAmount,
            curatorTokenAmount,
            isTakerPosition
        );

        return curatorTokenAmount;
    }

    /// @dev Sell curator tokens back into the bonding curve.
    /// Any holder who owns tokens can sell them back
    /// @return Returns the amount of payment tokens received for the curator tokens.
    function sellCuratorTokens(
        uint256 nftChainId,
        address nftAddress,
        uint256 nftId,
        IERC20Upgradeable paymentToken,
        uint256 tokensToBurn,
        address refundToAddress
    ) external nonReentrant returns (uint256) {
        require(tokensToBurn > 0, "Invalid 0 input");

        // Get the curator token token ID
        uint256 curatorTokenId = _getTokenId(
            nftChainId,
            nftAddress,
            nftId,
            paymentToken
        );

        // Burn the curator tokens
        curatorTokens.burn(msg.sender, curatorTokenId, tokensToBurn);

        // Get curve params
        (uint256 a, uint256 b, uint256 c) = addressManager
            .parameterManager()
            .bondingCurveParams();

        // Calculate the amount of tokens that will be minted based on the price
        uint256 refundAmount = calculatePaymentReturnedFromTokens(
            int256(a),
            int256(b),
            int256(c),
            int256(curatorTokenSupply[curatorTokenId]),
            int256(reserves[curatorTokenId]),
            int256(tokensToBurn)
        );

        // Update the amounts
        reserves[curatorTokenId] -= refundAmount;
        curatorTokenSupply[curatorTokenId] -= tokensToBurn;

        // Send payment token back
        paymentToken.safeTransfer(refundToAddress, refundAmount);

        // Emit the event
        emit CuratorTokensSold(curatorTokenId, refundAmount, tokensToBurn);

        return refundAmount;
    }
}
