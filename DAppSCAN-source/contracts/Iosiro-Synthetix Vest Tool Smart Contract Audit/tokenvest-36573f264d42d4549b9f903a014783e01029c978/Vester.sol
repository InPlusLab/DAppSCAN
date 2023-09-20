//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

/// @title Vesting Contract
/// @author Noah Litvin (@noahlitvin)
/// @notice This contract allows the recipient of a grant to redeem tokens each vesting interval, up to a total amount with an optional cliff.
contract Vester is ERC721Enumerable {

    struct Grant {
        uint128 vestAmount;
        uint128 totalAmount;
        uint128 amountRedeemed;
        uint64 startTimestamp;
        uint64 cliffTimestamp;
        uint32 vestInterval;
    }

    address public owner;
    address public nominatedOwner;
    address public tokenAddress;
    uint public tokenCounter;
    mapping (uint => Grant) public grants;

    constructor(string memory name, string memory symbol, address _owner, address _tokenAddress) ERC721(name, symbol) {
        owner = _owner;
        tokenAddress = _tokenAddress;
    }

    /// @notice Redeem all available vested tokens
    function redeem(uint tokenId) public {
        require(ownerOf(tokenId) == msg.sender, "You don't own this grant.");

        uint128 amount = availableForRedemption(tokenId);
        require(amount > 0, "You don't have any tokens currently available for redemption.");

        IERC20 tokenContract = IERC20(tokenAddress);
        require(tokenContract.balanceOf(address(this)) >= amount, "More tokens must be transferred to this contract before you can redeem.");

        grants[tokenId].amountRedeemed += amount;
        tokenContract.transfer(msg.sender, amount);

        emit Redemption(tokenId, msg.sender, amount);
    }
//SWC-107-Reentrancy:L51, 127
    /// @notice Redeem all available vested tokens and transfer in arbitrary tokens (to make this an exchange rather than income)
    /// @param incomingTokenAddress The address of the token being transferred in
    /// @param incomingTokenAmount The amount of the token being transferred in
    function redeemWithTransfer(uint tokenId, address incomingTokenAddress, uint incomingTokenAmount) external {
        IERC20 incomingTokenContract = IERC20(incomingTokenAddress);
        require(
            incomingTokenContract.transferFrom(msg.sender, address(this), incomingTokenAmount),
            "Incoming tokens failed to transfer."
        );
        redeem(tokenId);
    }

    /// @notice Calculate the amount of tokens currently available for redemption for a given grantee
    /// @dev This subtracts the amount of previously redeemed token from the total amount that has vested.
    /// @param tokenId The ID of the grant
    /// @return The amount available for redemption, denominated in tokens * 10^18
    function availableForRedemption(uint tokenId) public view returns (uint128) {
        return amountVested(tokenId) - grants[tokenId].amountRedeemed;
    }

    /// @notice Calculate the amount that has vested for a given address
    /// @param tokenId The ID of the grant
    /// @return The amount of vested tokens, denominated in tokens * 10^18
    function amountVested(uint tokenId) public view returns (uint128) {
        // Nothing has vested until the cliff has past.
        if(block.timestamp < grants[tokenId].cliffTimestamp){
            return 0;
        }

        // Calculate the number of intervals elapsed (will round down) multiplied by the amount to vest per vesting interval.
        uint128 amount = ((uint128(block.timestamp) - grants[tokenId].startTimestamp) / grants[tokenId].vestInterval) * grants[tokenId].vestAmount;

        // The total amount vested cannot exceed total grant size.
        if(amount > grants[tokenId].totalAmount){
            return grants[tokenId].totalAmount;
        }

        return amount;
    }

    /// @notice Withdraw tokens owned by this contract to the caller
    /// @dev Only the owner of the contract may call this function.
    /// @param withdrawalTokenAddress The address of the ERC20 token to redeem
    function withdraw(address withdrawalTokenAddress, uint withdrawalTokenAmount) public onlyOwner {
        IERC20 tokenContract = IERC20(withdrawalTokenAddress);
        tokenContract.transfer(msg.sender, withdrawalTokenAmount);

        emit Withdrawal(msg.sender, withdrawalTokenAddress, withdrawalTokenAmount);
    }

    /// @notice Update the data pertaining to a grant
    /// @dev Only the owner of the contract may call this function.
    /// @param tokenId The ID of the grant
    /// @param startTimestamp The timestamp defining the start of the vesting schedule
    /// @param cliffTimestamp Before this timestamp, no tokens can be redeemed
    /// @param vestAmount The amount of tokens that will vest for the recipient each interval, denominated in tokens * 10^18
    /// @param totalAmount The total amount of tokens that will be granted to the recipient, denominated in tokens * 10^18
    /// @param amountRedeemed The amount of tokens already redeemed by this recipient
    /// @param vestInterval The vesting period in seconds
    function updateGrant(uint tokenId, uint64 startTimestamp, uint64 cliffTimestamp, uint128 vestAmount, uint128 totalAmount, uint128 amountRedeemed, uint32 vestInterval) public onlyOwner {
        grants[tokenId].startTimestamp = startTimestamp;
        grants[tokenId].cliffTimestamp = cliffTimestamp;
        grants[tokenId].vestAmount = vestAmount;
        grants[tokenId].totalAmount = totalAmount;
        grants[tokenId].amountRedeemed = amountRedeemed;
        grants[tokenId].vestInterval = vestInterval;

        emit GrantUpdate(tokenId, startTimestamp, cliffTimestamp, vestAmount, totalAmount, amountRedeemed, vestInterval);
    }

    /// @notice Create a new grant
    /// @dev Only the owner of the contract may call this function.
    /// @param granteeAddress The address of the grant recipient
    /// @param startTimestamp The timestamp defining the start of the vesting schedule
    /// @param cliffTimestamp Before this timestamp, no tokens can be redeemed
    /// @param vestAmount The amount of tokens that will vest for the recipient each interval, denominated in tokens * 10^18
    /// @param totalAmount The total amount of tokens that will be granted to the recipient, denominated in tokens * 10^18
    /// @param amountRedeemed The amount of tokens already redeemed by this recipient
    /// @param vestInterval The vesting period in seconds
    function mint(address granteeAddress, uint64 startTimestamp, uint64 cliffTimestamp, uint128 vestAmount, uint128 totalAmount, uint128 amountRedeemed, uint32 vestInterval) external onlyOwner {
        _safeMint(granteeAddress, tokenCounter);
        updateGrant(tokenCounter, startTimestamp, cliffTimestamp, vestAmount, totalAmount, amountRedeemed, vestInterval);
        tokenCounter++;
    }

    /// @notice Destroy a grant
    /// @dev Only the owner of the contract may call this function.
    /// @param tokenId The ID of the grant
    function burn(uint tokenId) external onlyOwner {
        _burn(tokenId);
    }

    /// @notice Nominate a new owner
    /// @dev Only the owner of the contract may call this function.
    function nominateOwner(address nominee) external onlyOwner {
        nominatedOwner = nominee;
        emit OwnerNomination(nominee);
    }

    /// @notice Accept ownership if nominated
    function acceptOwnership() external {
        require(msg.sender == nominatedOwner);
        emit OwnerUpdate(owner, nominatedOwner);
        owner = nominatedOwner;
        nominatedOwner = address(0);
    }

    modifier onlyOwner {
        require(msg.sender == owner, "Only the owner can call this function.");
        _;
    }

    event Redemption(uint indexed tokenId, address indexed redeemerAddress, uint128 amount);
    event GrantUpdate(uint indexed tokenId, uint64 startTimestamp, uint64 cliffTimestamp, uint128 vestAmount, uint128 totalAmount, uint128 amountRedeemed, uint32 vestInterval);
    event Withdrawal(address indexed withdrawerAddress, address indexed withdrawalTokenAddress, uint amount);
    event OwnerNomination(address indexed newOwner);
    event OwnerUpdate(address indexed oldOwner, address indexed newOwner);
}
