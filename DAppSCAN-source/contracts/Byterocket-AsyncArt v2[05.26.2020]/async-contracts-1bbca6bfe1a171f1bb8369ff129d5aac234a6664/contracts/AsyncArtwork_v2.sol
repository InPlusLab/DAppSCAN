pragma solidity ^0.5.12;

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./ERC721Metadata.sol";

// interface for the v1 contract
interface AsyncArtwork_v1 {
    function getControlToken(uint256 controlTokenId) external view returns (int256[] memory);

    function tokenURI(uint256 tokenId) external view returns (string memory);
}

// Copyright (C) 2020 Asynchronous Art, Inc.
// GNU General Public License v3.0
// Full notice https://github.com/asyncart/async-contracts/blob/master/LICENSE

contract AsyncArtwork_v2 is Initializable, ERC721, ERC721Enumerable, ERC721Metadata {
    // An event whenever the platform address is updated
    event PlatformAddressUpdated(
        address platformAddress
    );

    event PermissionUpdated(
        uint256 tokenId,
        address tokenOwner,
        address permissioned
    );

    // An event whenever a creator is whitelisted with the token id and the layer count
    event CreatorWhitelisted(
        uint256 tokenId,
        uint256 layerCount,
        address creator
    );

    // An event whenever royalty amount for a token is updated
    event PlatformSalePercentageUpdated (
        uint256 tokenId,
        uint256 platformFirstPercentage,
        uint256 platformSecondPercentage        
    );

    // An event whenever artist secondary sale percentage is updated
    event ArtistSecondSalePercentUpdated (
        uint256 artistSecondPercentage
    );

    // An event whenever a bid is proposed
    event BidProposed(
        uint256 tokenId,
        uint256 bidAmount,
        address bidder
    );

    // An event whenever an bid is withdrawn
    event BidWithdrawn(
        uint256 tokenId
    );

    // An event whenever a buy now price has been set
    event BuyPriceSet(
        uint256 tokenId,
        uint256 price
    );

    // An event when a token has been sold 
    event TokenSale(
        // the id of the token
        uint256 tokenId,
        // the price that the token was sold for
        uint256 salePrice,
        // the address of the buyer
        address buyer
    );

    // An event whenever a control token has been updated
    event ControlLeverUpdated(
        // the id of the token
        uint256 tokenId,
        // an optional amount that the updater sent to boost priority of the rendering
        uint256 priorityTip,
        // the number of times this control lever can now be updated
        int256 numRemainingUpdates,
        // the ids of the levers that were updated
        uint256[] leverIds,        
        // the previous values that the levers had before this update (for clients who want to animate the change)
        int256[] previousValues,
        // the new updated value
        int256[] updatedValues
    );

    // struct for a token that controls part of the artwork
    struct ControlToken {
        // number that tracks how many levers there are
        uint256 numControlLevers;
        // The number of update calls this token has (-1 for infinite)
        int256 numRemainingUpdates;
        // false by default, true once instantiated
        bool exists;
        // false by default, true once setup by the artist
        bool isSetup;
        // the levers that this control token can use
        mapping(uint256 => ControlLever) levers;
    }

    // struct for a lever on a control token that can be changed
    struct ControlLever {
        // // The minimum value this token can have (inclusive)
        int256 minValue;
        // The maximum value this token can have (inclusive)
        int256 maxValue;
        // The current value for this token
        int256 currentValue;
        // false by default, true once instantiated
        bool exists;
    }

    // struct for a pending bid 
    struct PendingBid {
        // the address of the bidder
        address payable bidder;
        // the amount that they bid
        uint256 amount;
        // false by default, true once instantiated
        bool exists;
    }

    struct WhitelistReservation {
        // the address of the creator
        address creator;
        // the amount of layers they're expected to mint
        uint256 layerCount;
    }

    // track whether this token was sold the first time or not (used for determining whether to use first or secondary sale percentage)
    mapping(uint256 => bool) public tokenDidHaveFirstSale;
    // if a token's URI has been locked or not
    mapping(uint256 => bool) public tokenURILocked;    
    // map control token ID to its buy price
    mapping(uint256 => uint256) public buyPrices;    
    // mapping of addresses to credits for failed transfers
    mapping(address => uint256) public failedTransferCredits;
    // mapping of tokenId to percentage of sale that the platform gets on first sales
    mapping(uint256 => uint256) public platformFirstSalePercentages;
    // mapping of tokenId to percentage of sale that the platform gets on secondary sales
    mapping(uint256 => uint256) public platformSecondSalePercentages;
    // what tokenId creators are allowed to mint (and how many layers)
    mapping(uint256 => WhitelistReservation) public creatorWhitelist;
    // for each token, holds an array of the creator collaborators. For layer tokens it will likely just be [artist], for master tokens it may hold multiples
    mapping(uint256 => address payable[]) public uniqueTokenCreators;    
    // map a control token ID to its highest bid
    mapping(uint256 => PendingBid) public pendingBids;
    // map a control token id to a control token struct
    // SWC-108-State Variable Default Visibility: L156
    mapping(uint256 => ControlToken) controlTokenMapping;    
    // mapping of addresses that are allowed to control tokens on your behalf
    mapping(address => mapping(uint256 => address)) public permissionedControllers;
    // the percentage of sale that an artist gets on secondary sales
    uint256 public artistSecondSalePercentage;
    // gets incremented to placehold for tokens not minted yet
    uint256 public expectedTokenSupply;
    // the minimum % increase for new bids coming
    uint256 public minBidIncreasePercent;
    // the address of the platform (for receving commissions and royalties)
    address payable public platformAddress;
    // the address of the contract that can upgrade from v1 to v2 tokens
    address public upgraderAddress;

    function initialize(string memory name, string memory symbol, uint256 initialExpectedTokenSupply, address _upgraderAddress) public initializer {
        ERC721.initialize();
        ERC721Enumerable.initialize();
        ERC721Metadata.initialize(name, symbol);

        // starting royalty amounts
        artistSecondSalePercentage = 10;

        // intitialize the minimum bid increase percent
        minBidIncreasePercent = 1;

        // by default, the platformAddress is the address that mints this contract
        platformAddress = msg.sender;

        // set the upgrader address
        upgraderAddress = _upgraderAddress;

        // set the initial expected token supply       
        expectedTokenSupply = initialExpectedTokenSupply;

        require(expectedTokenSupply > 0);
    }

    // modifier for only allowing the platform to make a call
    modifier onlyPlatform() {
        require(msg.sender == platformAddress);
        _;
    }

    modifier onlyWhitelistedCreator(uint256 masterTokenId, uint256 layerCount) {
        require(creatorWhitelist[masterTokenId].creator == msg.sender);
        require(creatorWhitelist[masterTokenId].layerCount == layerCount);
        _;
    }

    // reserve a tokenID and layer count for a creator. Define a platform royalty percentage per art piece (some pieces have higher or lower amount)
    function whitelistTokenForCreator(address creator, uint256 masterTokenId, uint256 layerCount, 
        uint256 platformFirstSalePercentage, uint256 platformSecondSalePercentage) external onlyPlatform {
        // the tokenID we're reserving must be the current expected token supply
        require(masterTokenId == expectedTokenSupply);
        // Async pieces must have at least 1 layer
        require (layerCount > 0);
        // reserve the tokenID for this creator
        creatorWhitelist[masterTokenId] = WhitelistReservation(creator, layerCount);
        // increase the expected token supply
        expectedTokenSupply = masterTokenId.add(layerCount).add(1);
        // define the platform percentages for this token here
        platformFirstSalePercentages[masterTokenId] = platformFirstSalePercentage;
        platformSecondSalePercentages[masterTokenId] = platformSecondSalePercentage;

        emit CreatorWhitelisted(masterTokenId, layerCount, creator);
    }

    // Allows the current platform address to update to something different
    function updatePlatformAddress(address payable newPlatformAddress) external onlyPlatform {
        platformAddress = newPlatformAddress;

        emit PlatformAddressUpdated(newPlatformAddress);
    }

    // Allows platform to waive the first sale requirement for a token (for charity events, special cases, etc)
    function waiveFirstSaleRequirement(uint256 tokenId) external onlyPlatform {
        // This allows the token sale proceeds to go to the current owner (rather than be distributed amongst the token's creators)
        tokenDidHaveFirstSale[tokenId] = true;
    }

    // Allows platform to change the royalty percentage for a specific token
    function updatePlatformSalePercentage(uint256 tokenId, uint256 platformFirstSalePercentage, 
        uint256 platformSecondSalePercentage) external onlyPlatform {
        // set the percentages for this token
        platformFirstSalePercentages[tokenId] = platformFirstSalePercentage;
        platformSecondSalePercentages[tokenId] = platformSecondSalePercentage;
        // emit an event to notify that the platform percent for this token has changed
        emit PlatformSalePercentageUpdated(tokenId, platformFirstSalePercentage, platformSecondSalePercentage);
    }
    // Allows the platform to change the minimum percent increase for incoming bids
    function updateMinimumBidIncreasePercent(uint256 _minBidIncreasePercent) external onlyPlatform {
        require((_minBidIncreasePercent > 0) && (_minBidIncreasePercent <= 50), "Bid increases must be within 0-50%");
        // set the new bid increase percent
        minBidIncreasePercent = _minBidIncreasePercent;
    }
    // Allow the platform to update a token's URI if it's not locked yet (for fixing tokens post mint process)
    function updateTokenURI(uint256 tokenId, string calldata tokenURI) external onlyPlatform {
        // ensure that this token exists
        require(_exists(tokenId));
        // ensure that the URI for this token is not locked yet
        require(tokenURILocked[tokenId] == false);
        // update the token URI
        super._setTokenURI(tokenId, tokenURI);
    }

    // Locks a token's URI from being updated
    function lockTokenURI(uint256 tokenId) external onlyPlatform {
        // ensure that this token exists
        require(_exists(tokenId));
        // lock this token's URI from being changed
        tokenURILocked[tokenId] = true;
    }

    // Allows platform to change the percentage that artists receive on secondary sales
    function updateArtistSecondSalePercentage(uint256 _artistSecondSalePercentage) external onlyPlatform {
        // update the percentage that artists get on secondary sales
        artistSecondSalePercentage = _artistSecondSalePercentage;
        // emit an event to notify that the artist second sale percent has updated
        emit ArtistSecondSalePercentUpdated(artistSecondSalePercentage);
    }

    function setupControlToken(uint256 controlTokenId, string calldata controlTokenURI,
        int256[] calldata leverMinValues,
        int256[] calldata leverMaxValues,
        int256[] calldata leverStartValues,
        int256 numAllowedUpdates,
        address payable[] calldata additionalCollaborators
    ) external {
        // Hard cap the number of levers a single control token can have
        require (leverMinValues.length <= 500, "Too many control levers.");
        // Hard cap the number of collaborators a single control token can have
        require (additionalCollaborators.length <= 50, "Too many collaborators.");
        // check that a control token exists for this token id
        require(controlTokenMapping[controlTokenId].exists, "No control token found");
        // ensure that this token is not setup yet
        require(controlTokenMapping[controlTokenId].isSetup == false, "Already setup");
        // ensure that only the control token artist is attempting this mint
        require(uniqueTokenCreators[controlTokenId][0] == msg.sender, "Must be control token artist");
        // enforce that the length of all the array lengths are equal
        require((leverMinValues.length == leverMaxValues.length) && (leverMaxValues.length == leverStartValues.length), "Values array mismatch");
        // require the number of allowed updates to be infinite (-1) or some finite number
        require((numAllowedUpdates == -1) || (numAllowedUpdates > 0), "Invalid allowed updates");
        // mint the control token here
        super._safeMint(msg.sender, controlTokenId);
        // set token URI
        super._setTokenURI(controlTokenId, controlTokenURI);        
        // create the control token
        controlTokenMapping[controlTokenId] = ControlToken(leverStartValues.length, numAllowedUpdates, true, true);
        // create the control token levers now
        for (uint256 k = 0; k < leverStartValues.length; k++) {
            // enforce that maxValue is greater than or equal to minValue
            require(leverMaxValues[k] >= leverMinValues[k], "Max val must >= min");
            // enforce that currentValue is valid
            require((leverStartValues[k] >= leverMinValues[k]) && (leverStartValues[k] <= leverMaxValues[k]), "Invalid start val");
            // add the lever to this token
            controlTokenMapping[controlTokenId].levers[k] = ControlLever(leverMinValues[k],
                leverMaxValues[k], leverStartValues[k], true);
        }
        // the control token artist can optionally specify additional collaborators on this layer
        for (uint256 i = 0; i < additionalCollaborators.length; i++) {
            // can't provide burn address as collaborator
            require(additionalCollaborators[i] != address(0));

            uniqueTokenCreators[controlTokenId].push(additionalCollaborators[i]);
        }
    }

    // upgrade a token from the v1 contract to this v2 version
    function upgradeV1Token(uint256 tokenId, address v1Address, bool isControlToken, address to, 
        uint256 platformFirstPercentageForToken, uint256 platformSecondPercentageForToken, bool hasTokenHadFirstSale,
        address payable[] calldata uniqueTokenCreatorsForToken) external {
        // get reference to v1 token contract
        AsyncArtwork_v1 v1Token = AsyncArtwork_v1(v1Address);

        // require that only the upgrader address is calling this method
        require(msg.sender == upgraderAddress, "Only upgrader can call.");

        // preserve the unique token creators
        uniqueTokenCreators[tokenId] = uniqueTokenCreatorsForToken;

        if (isControlToken) {
            // preserve the control token details if it's a control token
            int256[] memory controlToken = v1Token.getControlToken(tokenId);
            // Require control token to be a valid size (multiple of 3)
            require(controlToken.length % 3 == 0, "Invalid control token.");
            // Require control token to have at least 1 lever
            require(controlToken.length > 0, "Control token must have levers");            
            // Setup the control token
            // Use -1 for numRemainingUpdates since v1 tokens were infinite use
            controlTokenMapping[tokenId] = ControlToken(controlToken.length / 3, -1, true, true);

            // set each lever for the control token. getControlToken returns levers like:
            // [minValue, maxValue, curValue, minValue, maxValue, curValue, ...] so they always come in groups of 3
            for (uint256 k = 0; k < controlToken.length; k+=3) {
                controlTokenMapping[tokenId].levers[k / 3] = ControlLever(controlToken[k],
                    controlToken[k + 1], controlToken[k + 2], true);
            }
        }

        // Set the royalty percentage for this token
        platformFirstSalePercentages[tokenId] = platformFirstPercentageForToken;

        platformSecondSalePercentages[tokenId] = platformSecondPercentageForToken;

        // whether this token has already had its first sale
        tokenDidHaveFirstSale[tokenId] = hasTokenHadFirstSale;

        // Mint and transfer the token to the original v1 token owner
        super._safeMint(to, tokenId);

        // set the same token URI
        super._setTokenURI(tokenId, v1Token.tokenURI(tokenId));
    }

    function mintArtwork(uint256 masterTokenId, string calldata artworkTokenURI, address payable[] calldata controlTokenArtists)
        external onlyWhitelistedCreator(masterTokenId, controlTokenArtists.length) {
        // Can't mint a token with ID 0 anymore
        require(masterTokenId > 0);
        // Mint the token that represents ownership of the entire artwork    
        super._safeMint(msg.sender, masterTokenId);
        // set the token URI for this art
        super._setTokenURI(masterTokenId, artworkTokenURI);
        // track the msg.sender address as the artist address for future royalties
        uniqueTokenCreators[masterTokenId].push(msg.sender);
        // iterate through all control token URIs (1 for each control token)
        for (uint256 i = 0; i < controlTokenArtists.length; i++) {
            // can't provide burn address as artist
            require(controlTokenArtists[i] != address(0));
            // determine the tokenID for this control token
            uint256 controlTokenId = masterTokenId + i + 1;
            // add this control token artist to the unique creator list for that control token
            uniqueTokenCreators[controlTokenId].push(controlTokenArtists[i]);
            // stub in an existing control token so exists is true
            controlTokenMapping[controlTokenId] = ControlToken(0, 0, true, false);

            // Layer control tokens use the same royalty percentage as the master token
            platformFirstSalePercentages[controlTokenId] = platformFirstSalePercentages[masterTokenId];

            platformSecondSalePercentages[controlTokenId] = platformSecondSalePercentages[masterTokenId];

            if (controlTokenArtists[i] != msg.sender) {
                bool containsControlTokenArtist = false;

                for (uint256 k = 0; k < uniqueTokenCreators[masterTokenId].length; k++) {
                    if (uniqueTokenCreators[masterTokenId][k] == controlTokenArtists[i]) {
                        containsControlTokenArtist = true;
                        break;
                    }
                }
                if (containsControlTokenArtist == false) {
                    uniqueTokenCreators[masterTokenId].push(controlTokenArtists[i]);
                }
            }
        }
    }
    // Bidder functions
    function bid(uint256 tokenId) external payable {
        // don't allow bids of 0
        require(msg.value > 0);
        // don't let owners/approved bid on their own tokens
        require(_isApprovedOrOwner(msg.sender, tokenId) == false);
        // check if there's a high bid
        if (pendingBids[tokenId].exists) {
            // enforce that this bid is higher by at least the minimum required percent increase
            require(msg.value >= (pendingBids[tokenId].amount.mul(minBidIncreasePercent.add(100)).div(100)), "Bid must increase by min %");
            // Return bid amount back to bidder
            safeFundsTransfer(pendingBids[tokenId].bidder, pendingBids[tokenId].amount);
        }
        // set the new highest bid
        pendingBids[tokenId] = PendingBid(msg.sender, msg.value, true);
        // Emit event for the bid proposal
        emit BidProposed(tokenId, msg.value, msg.sender);
    }
    // allows an address with a pending bid to withdraw it
    function withdrawBid(uint256 tokenId) external {
        // check that there is a bid from the sender to withdraw (also allows platform address to withdraw a bid on someone's behalf)
        require((pendingBids[tokenId].bidder == msg.sender) || (msg.sender == platformAddress));
        // attempt to withdraw the bid
        _withdrawBid(tokenId);        
    }
    function _withdrawBid(uint256 tokenId) internal {
        require(pendingBids[tokenId].exists);
        // Return bid amount back to bidder
        safeFundsTransfer(pendingBids[tokenId].bidder, pendingBids[tokenId].amount);
        // clear highest bid
        pendingBids[tokenId] = PendingBid(address(0), 0, false);
        // emit an event when the highest bid is withdrawn
        emit BidWithdrawn(tokenId);
    }

    // Buy the artwork for the currently set price
    // Allows the buyer to specify a minimum remaining uses they'll accept
    function takeBuyPrice(uint256 tokenId, int256 expectedRemainingUpdates) external payable {
        // don't let owners/approved buy their own tokens
        require(_isApprovedOrOwner(msg.sender, tokenId) == false);
        // get the sale amount
        uint256 saleAmount = buyPrices[tokenId];
        // check that there is a buy price
        require(saleAmount > 0);
        // check that the buyer sent exact amount to purchase
        require(msg.value == saleAmount);
        // if this is a control token
        if (controlTokenMapping[tokenId].exists) {
            // ensure that the remaining uses on the token is equal to what buyer expects
            require(controlTokenMapping[tokenId].numRemainingUpdates == expectedRemainingUpdates);
        }
        // Return all highest bidder's money
        if (pendingBids[tokenId].exists) {
            // Return bid amount back to bidder
            safeFundsTransfer(pendingBids[tokenId].bidder, pendingBids[tokenId].amount);
            // clear highest bid
            pendingBids[tokenId] = PendingBid(address(0), 0, false);
        }
        onTokenSold(tokenId, saleAmount, msg.sender);
    }

    // Take an amount and distribute it evenly amongst a list of creator addresses
    function distributeFundsToCreators(uint256 amount, address payable[] memory creators) private {
        uint256 creatorShare = amount.div(creators.length);

        for (uint256 i = 0; i < creators.length; i++) {
            safeFundsTransfer(creators[i], creatorShare);
        }
    }

    // When a token is sold via list price or bid. Distributes the sale amount to the unique token creators and transfer
    // the token to the new owner
    function onTokenSold(uint256 tokenId, uint256 saleAmount, address to) private {
        // if the first sale already happened, then give the artist + platform the secondary royalty percentage
        if (tokenDidHaveFirstSale[tokenId]) {
            // give platform its secondary sale percentage
            uint256 platformAmount = saleAmount.mul(platformSecondSalePercentages[tokenId]).div(100);
            safeFundsTransfer(platformAddress, platformAmount);
            // distribute the creator royalty amongst the creators (all artists involved for a base token, sole artist creator for layer )
            uint256 creatorAmount = saleAmount.mul(artistSecondSalePercentage).div(100);
            distributeFundsToCreators(creatorAmount, uniqueTokenCreators[tokenId]);
            // cast the owner to a payable address
            address payable payableOwner = address(uint160(ownerOf(tokenId)));
            // transfer the remaining amount to the owner of the token
            safeFundsTransfer(payableOwner, saleAmount.sub(platformAmount).sub(creatorAmount));
        } else {
            tokenDidHaveFirstSale[tokenId] = true;
            // give platform its first sale percentage
            uint256 platformAmount = saleAmount.mul(platformFirstSalePercentages[tokenId]).div(100);
            safeFundsTransfer(platformAddress, platformAmount);
            // this is a token first sale, so distribute the remaining funds to the unique token creators of this token
            // (if it's a base token it will be all the unique creators, if it's a control token it will be that single artist)                      
            distributeFundsToCreators(saleAmount.sub(platformAmount), uniqueTokenCreators[tokenId]);
        }
        // clear highest bid
        pendingBids[tokenId] = PendingBid(address(0), 0, false);
        // Transfer token to msg.sender
        _transferFrom(ownerOf(tokenId), to, tokenId);
        // Emit event
        emit TokenSale(tokenId, saleAmount, to);
    }

    // Owner functions
    // Allow owner to accept the highest bid for a token
    function acceptBid(uint256 tokenId, uint256 minAcceptedAmount) external {
        // check if sender is owner/approved of token        
        require(_isApprovedOrOwner(msg.sender, tokenId));
        // check if there's a bid to accept
        require(pendingBids[tokenId].exists);
        // check that the current pending bid amount is at least what the accepting owner expects
        require(pendingBids[tokenId].amount >= minAcceptedAmount);
        // process the sale
        onTokenSold(tokenId, pendingBids[tokenId].amount, pendingBids[tokenId].bidder);
    }

    // Allows owner of a control token to set an immediate buy price. Set to 0 to reset.
    function makeBuyPrice(uint256 tokenId, uint256 amount) external {
        // check if sender is owner/approved of token        
        require(_isApprovedOrOwner(msg.sender, tokenId));
        // set the buy price
        buyPrices[tokenId] = amount;
        // emit event
        emit BuyPriceSet(tokenId, amount);
    }

    // return the number of times that a control token can be used
    function getNumRemainingControlUpdates(uint256 controlTokenId) external view returns (int256) {
        require(controlTokenMapping[controlTokenId].exists, "Token does not exist.");

        return controlTokenMapping[controlTokenId].numRemainingUpdates;
    }

    // return the min, max, and current value of a control lever
    function getControlToken(uint256 controlTokenId) external view returns(int256[] memory) {
        require(controlTokenMapping[controlTokenId].exists, "Token does not exist.");

        ControlToken storage controlToken = controlTokenMapping[controlTokenId];

        int256[] memory returnValues = new int256[](controlToken.numControlLevers.mul(3));
        uint256 returnValIndex = 0;

        // iterate through all the control levers for this control token
        for (uint256 i = 0; i < controlToken.numControlLevers; i++) {
            returnValues[returnValIndex] = controlToken.levers[i].minValue;
            returnValIndex = returnValIndex.add(1);

            returnValues[returnValIndex] = controlToken.levers[i].maxValue;
            returnValIndex = returnValIndex.add(1);

            returnValues[returnValIndex] = controlToken.levers[i].currentValue;
            returnValIndex = returnValIndex.add(1);
        }

        return returnValues;
    }

    // anyone can grant permission to another address to control a specific token on their behalf. Set to Address(0) to reset.
    function grantControlPermission(uint256 tokenId, address permissioned) external {
        permissionedControllers[msg.sender][tokenId] = permissioned;

        emit PermissionUpdated(tokenId, msg.sender, permissioned);
    }

    // Allows owner (or permissioned user) of a control token to update its lever values
    // Optionally accept a payment to increase speed of rendering priority
    function useControlToken(uint256 controlTokenId, uint256[] calldata leverIds, int256[] calldata newValues) external payable {
        // check if sender is owner/approved of token OR if they're a permissioned controller for the token owner      
        require(_isApprovedOrOwner(msg.sender, controlTokenId) || (permissionedControllers[ownerOf(controlTokenId)][controlTokenId] == msg.sender),
            "Owner or permissioned only");
        // check if control exists
        require(controlTokenMapping[controlTokenId].exists, "Token does not exist.");
        // get the control token reference
        ControlToken storage controlToken = controlTokenMapping[controlTokenId];
        // check that number of uses for control token is either infinite or is positive
        require((controlToken.numRemainingUpdates == -1) || (controlToken.numRemainingUpdates > 0), "No more updates allowed");        
        // collect the previous lever values for the event emit below
        int256[] memory previousValues = new int256[](newValues.length);

        for (uint256 i = 0; i < leverIds.length; i++) {
            // get the control lever
            ControlLever storage lever = controlTokenMapping[controlTokenId].levers[leverIds[i]];

            // Enforce that the new value is valid        
            require((newValues[i] >= lever.minValue) && (newValues[i] <= lever.maxValue), "Invalid val");

            // Enforce that the new value is different
            require(newValues[i] != lever.currentValue, "Must provide different val");

            // grab previous value for the event emit
            // SWC-131-Presence of unused variables: L600
            int256 previousValue = lever.currentValue;

            // Update token current value
            lever.currentValue = newValues[i];

            // collect the previous lever values for the event emit below
            previousValues[i] = previousValue;
        }

        // if there's a payment then send it to the platform (for higher priority updates)
        if (msg.value > 0) {
            safeFundsTransfer(platformAddress, msg.value);
        }

        // if this control token is finite in its uses
        if (controlToken.numRemainingUpdates > 0) {
            // decrease it down by 1
            controlToken.numRemainingUpdates = controlToken.numRemainingUpdates - 1;

            // since we used one of those updates, withdraw any existing bid for this token if exists
            if (pendingBids[controlTokenId].exists) {
                _withdrawBid(controlTokenId);
            }
        }

        // emit event
        emit ControlLeverUpdated(controlTokenId, msg.value, controlToken.numRemainingUpdates, leverIds, previousValues, newValues);
    }

    // Allows a user to withdraw all failed transaction credits
    function withdrawAllFailedCredits() external {
        uint256 amount = failedTransferCredits[msg.sender];

        require(amount != 0);
        require(address(this).balance >= amount);

        failedTransferCredits[msg.sender] = 0;

        (bool successfulWithdraw, ) = msg.sender.call.value(amount)("");
        require(successfulWithdraw);
    }

    // Safely transfer funds and if fail then store that amount as credits for a later pull
    function safeFundsTransfer(address payable recipient, uint256 amount) internal {
        // attempt to send the funds to the recipient
        // SWC-107-Reentrancy: L647
        (bool success, ) = recipient.call.value(amount).gas(2300)("");
        // if it failed, update their credit balance so they can pull it later
        if (success == false) {
            failedTransferCredits[recipient] = failedTransferCredits[recipient].add(amount);
        }
    }

    // override the default transfer
    function _transferFrom(address from, address to, uint256 tokenId) internal {
        // clear a buy now price
        buyPrices[tokenId] = 0;
        // transfer the token
        super._transferFrom(from, to, tokenId);
    }
}