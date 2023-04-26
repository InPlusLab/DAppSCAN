//"SPDX-License-Identifier: UNLICENSED"
pragma solidity 0.6.12;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155PausableUpgradeable.sol";
import "./interfaces/IAdmin.sol";

contract AvalaunchBadgeFactory is ERC1155PausableUpgradeable {

	// Admin contract
	IAdmin public admin;

	// Contract level uri
	string private contractURI;
	// Store id of latest badge created
	uint256 private lastCreatedBadgeId;
	// Mapping badge id to tradeability
	mapping (uint256 => bool) private badgeIdToTradeability;
	// Mapping badge id to multiplier
	mapping (uint256 => uint8) private badgeIdToMultiplier;
	// Mapping badge id to minted supply
	mapping (uint256 => uint256) private badgeIdToMintedSupply;
	// Mapping for verified marketplace contracts
	mapping (address => bool) private verifiedMarketplaces;

	// Events
	event BadgeCreated(uint256 badgeId, uint8 multiplier, bool tradeability);
	event BadgeMinted(uint256 badgeId, address receiver);
	event NewURISet(string newUri);
	event NewContractURISet(string newContractUri);
	event VMarketplaceAdded(address marketplace);
	event VMarketplaceRemoved(address marketplace);

	// Restricting calls only to sale admin
	modifier onlyAdmin() {
		require(
			admin.isAdmin(msg.sender),
			"Only admin can call this function."
		);
		_;
	}

	function initialize(
		address _admin,
		string calldata _uri,
		string calldata _contractURI
	)
	external
	initializer
	{
		__ERC1155_init(_uri);

		require(_admin != address(0), "Admin cannot be zero address.");
		admin = IAdmin(_admin);

		contractURI = _contractURI;
	}

	/// @notice 	Function to pause the nft transfer related ops
	function pause()
	external
	onlyAdmin
	{
		_pause();
	}

	/// @notice 	Function to unpause the nft transfer related ops
	function unpause()
	external
	onlyAdmin
	{
		_unpause();
	}

	/// @notice 	Uri setter
	function setNewUri(
		string calldata _uri
	)
	external
	onlyAdmin
	{
		_setURI(_uri);
		emit NewURISet(_uri);
	}

	/// @notice 	Contract level uri setter
	function setNewContractUri(
		string calldata _contractURI
	)
	external
	onlyAdmin
	{
		contractURI = _contractURI;
		emit NewURISet(_contractURI);
	}

	/// @notice 	Verify marketplace contract
	function addVerifiedMarketplace(
		address _contract
	)
	external
	onlyAdmin
	{
		verifiedMarketplaces[_contract] = true;
		emit VMarketplaceAdded(_contract);
	}

	/// @notice 	Remove marketplace contract verification
	function removeVerifiedMarketplace(
		address _contract
	)
	external
	onlyAdmin
	{
		verifiedMarketplaces[_contract] = false;
		emit VMarketplaceRemoved(_contract);
	}

	/// @notice 	Function to create badges
	/// @dev		Necessary for minting
	function createBadges(
		uint256[] calldata badgeIds,
		uint8[] calldata multipliers,
		bool[] calldata tradeability
	)
	external
	onlyAdmin
	{
		// Validate array size
		require(
			badgeIds.length == multipliers.length &&
			multipliers.length == tradeability.length,
			"Array size mismatch."
		);

		// Create badges
		for(uint i = 0; i < badgeIds.length; i++) {
			// Require that new badge has proper id
			require(badgeIds[i] == lastCreatedBadgeId.add(1), "Invalid badge id.");
			// Set new lastly created badge id
			lastCreatedBadgeId = badgeIds[i];

			// Set badge params
			badgeIdToTradeability[badgeIds[i]] = tradeability[i];
			badgeIdToMultiplier[badgeIds[i]] = multipliers[i];

			// Emit event
			emit BadgeCreated(badgeIds[i], multipliers[i], tradeability[i]);
		}
	}

	/// @notice 	Function to mint badges to users
	/** @dev
	 *	isContract check can be safely used in combination with isAdmin modifier.
	 *	Therefore, it is impossible to initiate function call from malicious contract constructor
	 *	and exploit the check.
	 */
	function mintBadges(
		uint256[] calldata badgeIds,
		address[] calldata receivers
	)
	external
	onlyAdmin
	{
		// Require that array lengths match
		require(badgeIds.length == receivers.length, "Array length mismatch.");

		for(uint i = 0; i < badgeIds.length; i++) {
			// Require that receiver is not a contract
			require(
				!AddressUpgradeable.isContract(receivers[i]),
				"Cannot mint badge to untrusted contract."
			);

			// Require that badge has been created
			require(badgeIds[i] <= lastCreatedBadgeId, "Badge must be created before minting.");

			// Mint badge NFT to user
			_mint(receivers[i], badgeIds[i], 1, "0x0");
			emit BadgeMinted(badgeIds[i], receivers[i]);
		}
	}

	/// @notice 	Contract level uri getter
	function getContractURI()
	external
	view
	returns
	(string memory)
	{
		return contractURI;
	}

	/// @notice 	Badge total supply getter
	function getBadgeSupply(
		uint badgeId
	)
	external
	view
	returns (uint256)
	{
		return badgeIdToMintedSupply[badgeId];
	}

	/// @notice 	Badge multiplier getter
	function getBadgeMultiplier(
		uint badgeId
	)
	external
	view
	returns (uint256)
	{
		return badgeIdToMultiplier[badgeId];
	}

	/// @notice 	Returns id from lastly created badge
	function getLastCreatedBadgeId()
	external
	view
	returns (uint256)
	{
		return lastCreatedBadgeId;
	}

	function isMarketplaceVerified(
		address marketplace
	)
	external
	view
	returns (bool)
	{
		return verifiedMarketplaces[marketplace];
	}

	function _beforeTokenTransfer(
		address operator,
		address from,
		address to,
		uint256[] memory ids,
		uint256[] memory amounts,
		bytes memory data
	)
	internal
	override
	{
		super._beforeTokenTransfer(operator, from, to, ids, amounts, data);

		// If operation != mint
		if(from != address(0)) {
			// Require that verified marketplace is transfer operator
			require(
				verifiedMarketplaces[operator],
				"Badges can be traded only through verified marketplaces."
			);
			for(uint i = 0; i < ids.length; i++) {
				// Require that badges are tradeable prior to transfer
				require(badgeIdToTradeability[ids[i]], "Badge not tradeable.");
			}
		} else { // In case of minting
			for(uint i = 0; i < ids.length; i++) {
				// Increase total minted supply
				badgeIdToMintedSupply[ids[i]] = badgeIdToMintedSupply[ids[i]].add(amounts[i]);
			}
		}
	}
}
