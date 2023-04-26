// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.6.12;
import "../math/SafeMathUint128.sol";
import "../interfaces/IHEZToken.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/utils/ReentrancyGuard.sol";

/**
 * @dev Hermez will run an auction to incentivise efficiency in coordinators,
 * meaning that they need to be very effective and include as many transactions
 * as they can in the slots in order to compensate for their bidding costs, gas
 * costs and operations costs.The general porpouse of this smartcontract is to
 * define the rules to coordinate this auction where the bids will be placed
 * only in HEZ utility token.
 */
contract HermezAuctionProtocolV2 is Initializable, ReentrancyGuardUpgradeSafe {
    using SafeMath128 for uint128;

    struct Coordinator {
        address forger; // Address allowed by the bidder to forge a batch
        string coordinatorURL;
    }

    // The closedMinBid is the minimum bidding with which it has been closed a slot and may be
    // higher than the bidAmount. This means that the funds must be returned to whoever has bid
    struct SlotState {
        address bidder;
        bool fulfilled;
        uint128 bidAmount; // Since the total supply of HEZ will be less than 100M, with 128 bits it is enough to
        uint128 closedMinBid; // store the bidAmount and closed minBid. bidAmount is the bidding for an specific slot.
    }

    // bytes4 private constant _PERMIT_SIGNATURE =
    //    bytes4(keccak256(bytes("permit(address,address,uint256,uint256,uint8,bytes32,bytes32)")));
    bytes4 private constant _PERMIT_SIGNATURE = 0xd505accf;

    // Blocks per slot
    uint8 public constant BLOCKS_PER_SLOT = 40;
    // Minimum bid when no one has bid yet
    uint128 public constant INITIAL_MINIMAL_BIDDING = 10 * (1e18);

    // Hermez Network Token with which the bids will be made
    IHEZToken public tokenHEZ;
    // HermezRollup smartcontract address
    address public hermezRollup;
    // Hermez Governance smartcontract address who controls some parameters and collects HEZ fee
    address private _governanceAddress;
    // Boot Coordinator Address
    address private _donationAddress;
    // Boot Coordinator Address
    address private _bootCoordinator;
    // The minimum bid value in a series of 6 slots
    uint128[6] private _defaultSlotSetBid;
    // First block where the first slot begins
    uint128 public genesisBlock;
    // Distance (#slots) to the closest slot to which you can bid ( 2 Slots = 2 * 40 Blocks = 20 min )
    uint16 private _closedAuctionSlots;
    // Distance (#slots) to the farthest slot to which you can bid ( 30 days = 4320 slots )
    uint16 private _openAuctionSlots;
    // How the HEZ tokens deposited by the slot winner are distributed ( Burn: 40.00% - Donation: 40.00% - HGT: 20.00% )
    uint16[3] private _allocationRatio; // Two decimal precision
    // Minimum outbid (percentage, two decimal precision) over the previous one to consider it valid
    uint16 private _outbidding; // Two decimal precision
    // Number of blocks after the beginning of a slot after which any coordinator can forge if the winner has not forged
    // any batch in that slot
    uint8 private _slotDeadline;

    // Mapping to control slot state
    mapping(uint128 => SlotState) public slots;
    // Mapping to control balances pending to claim
    mapping(address => uint128) public pendingBalances;
    // Mapping to register all the coordinators. The address used for the mapping is the bidder address
    mapping(address => Coordinator) public coordinators;

    event NewBid(
        uint128 indexed slot,
        uint128 bidAmount,
        address indexed bidder
    );
    event NewSlotDeadline(uint8 newSlotDeadline);
    event NewClosedAuctionSlots(uint16 newClosedAuctionSlots);
    event NewOutbidding(uint16 newOutbidding);
    event NewDonationAddress(address indexed newDonationAddress);
    event NewBootCoordinator(address indexed newBootCoordinator);
    event NewOpenAuctionSlots(uint16 newOpenAuctionSlots);
    event NewAllocationRatio(uint16[3] newAllocationRatio);
    event SetCoordinator(
        address indexed bidder,
        address indexed forger,
        string coordinatorURL
    );
    event NewForgeAllocated(
        address indexed bidder,
        address indexed forger,
        uint128 indexed slotToForge,
        uint128 burnAmount,
        uint128 donationAmount,
        uint128 governanceAmount
    );
    event NewDefaultSlotSetBid(uint128 slotSet, uint128 newInitialMinBid);
    event NewForge(address indexed forger, uint128 indexed slotToForge);
    event HEZClaimed(address indexed owner, uint128 amount);

    modifier onlyGovernance() {
        require(
            _governanceAddress == msg.sender,
            "HermezAuctionProtocol::onlyGovernance: ONLY_GOVERNANCE"
        );
        _;
    }

    /**
     * @dev Initializer function (equivalent to the constructor). Since we use
     * upgradeable smartcontracts the state vars have to be initialized here.
     * @param token Hermez Network token with which the bids will be made
     * @param hermezRollupAddress address authorized to forge
     * @param donationAddress address that can claim donated tokens
     * @param governanceAddress Hermez Governance smartcontract
     * @param bootCoordinatorAddress Boot Coordinator Address
     */
    function hermezAuctionProtocolInitializer(
        address token,
        uint128 genesis,
        address hermezRollupAddress,
        address governanceAddress,
        address donationAddress,
        address bootCoordinatorAddress
    ) public initializer {
        __ReentrancyGuard_init_unchained();
        _outbidding = 1000;
        _slotDeadline = 20;
        _closedAuctionSlots = 2;
        _openAuctionSlots = 4320;
        _allocationRatio = [4000, 4000, 2000];
        _defaultSlotSetBid = [
            INITIAL_MINIMAL_BIDDING,
            INITIAL_MINIMAL_BIDDING,
            INITIAL_MINIMAL_BIDDING,
            INITIAL_MINIMAL_BIDDING,
            INITIAL_MINIMAL_BIDDING,
            INITIAL_MINIMAL_BIDDING
        ];

        tokenHEZ = IHEZToken(token);
        require(
            genesis >= block.number + (BLOCKS_PER_SLOT * _closedAuctionSlots),
            "HermezAuctionProtocol::hermezAuctionProtocolInitializer GENESIS_BELOW_MINIMAL"
        );
        genesisBlock = genesis;
        hermezRollup = hermezRollupAddress;
        _governanceAddress = governanceAddress;
        _donationAddress = donationAddress;
        _bootCoordinator = bootCoordinatorAddress;
    }

    /**
     * @notice Getter of the current `_slotDeadline`
     * @return The `_slotDeadline` value
     */
    function getSlotDeadline() external view returns (uint8) {
        return _slotDeadline;
    }

    function isNewVersion() external pure returns (bool) {
        return true;
    }

    /**
     * @notice Allows to change the `_slotDeadline` if it's called by the owner
     * @param newDeadline new `_slotDeadline`
     * Events: `NewSlotDeadline`
     */
    function setSlotDeadline(uint8 newDeadline) external onlyGovernance {
        require(
            newDeadline <= BLOCKS_PER_SLOT,
            "HermezAuctionProtocol::setSlotDeadline: GREATER_THAN_BLOCKS_PER_SLOT"
        );
        _slotDeadline = newDeadline;
        emit NewSlotDeadline(_slotDeadline);
    }

    /**
     * @notice Getter of the current `_openAuctionSlots`
     * @return The `_openAuctionSlots` value
     */
    function getOpenAuctionSlots() external view returns (uint16) {
        return _openAuctionSlots;
    }

    /**
     * @notice Allows to change the `_openAuctionSlots` if it's called by the owner
     * @dev Max newOpenAuctionSlots = 65536 slots
     * @param newOpenAuctionSlots new `_openAuctionSlots`
     * Events: `NewOpenAuctionSlots`
     * Note: the governance could set this parameter equal to `ClosedAuctionSlots`, this means that it can prevent bids
     * from being made and that only the boot coordinator can forge
     */
    function setOpenAuctionSlots(uint16 newOpenAuctionSlots)
        external
        onlyGovernance
    {
        require(
            newOpenAuctionSlots >= _closedAuctionSlots,
            "HermezAuctionProtocol::setOpenAuctionSlots: SMALLER_THAN_CLOSED_AUCTION_SLOTS"
        );
        _openAuctionSlots = newOpenAuctionSlots;
        emit NewOpenAuctionSlots(_openAuctionSlots);
    }

    /**
     * @notice Getter of the current `_closedAuctionSlots`
     * @return The `_closedAuctionSlots` value
     */
    function getClosedAuctionSlots() external view returns (uint16) {
        return _closedAuctionSlots;
    }

    /**
     * @notice Allows to change the `_closedAuctionSlots` if it's called by the owner
     * @dev Max newClosedAuctionSlots = 65536 slots
     * @param newClosedAuctionSlots new `_closedAuctionSlots`
     * Events: `NewClosedAuctionSlots`
     * Note: the governance could set this parameter equal to `OpenAuctionSlots`, this means that it can prevent bids
     * from being made and that only the boot coordinator can forge
     */
    function setClosedAuctionSlots(uint16 newClosedAuctionSlots)
        external
        onlyGovernance
    {
        require(
            newClosedAuctionSlots <= _openAuctionSlots,
            "HermezAuctionProtocol::setClosedAuctionSlots: GREATER_THAN_CLOSED_AUCTION_SLOTS"
        );
        _closedAuctionSlots = newClosedAuctionSlots;
        emit NewClosedAuctionSlots(_closedAuctionSlots);
    }

    /**
     * @notice Getter of the current `_outbidding`
     * @return The `_outbidding` value
     */
    function getOutbidding() external view returns (uint16) {
        return _outbidding;
    }

    /**
     * @notice Allows to change the `_outbidding` if it's called by the owner
     * @dev newOutbidding between 0.00% and 655.36%
     * @param newOutbidding new `_outbidding`
     * Events: `NewOutbidding`
     */
    function setOutbidding(uint16 newOutbidding) external onlyGovernance {
        _outbidding = newOutbidding;
        emit NewOutbidding(_outbidding);
    }

    /**
     * @notice Getter of the current `_allocationRatio`
     * @return The `_allocationRatio` array
     */
    function getAllocationRatio() external view returns (uint16[3] memory) {
        return _allocationRatio;
    }

    /**
     * @notice Allows to change the `_allocationRatio` array if it's called by the owner
     * @param newAllocationRatio new `_allocationRatio` uint8[3] array
     * Events: `NewAllocationRatio`
     */
    function setAllocationRatio(uint16[3] memory newAllocationRatio)
        external
        onlyGovernance
    {
        require(
            (newAllocationRatio[0] +
                newAllocationRatio[1] +
                newAllocationRatio[2]) == 10000,
            "HermezAuctionProtocol::setAllocationRatio: ALLOCATION_RATIO_NOT_VALID"
        );
        _allocationRatio = newAllocationRatio;
        emit NewAllocationRatio(_allocationRatio);
    }

    /**
     * @notice Getter of the current `_donationAddress`
     * @return The `_donationAddress`
     */
    function getDonationAddress() external view returns (address) {
        return _donationAddress;
    }

    /**
     * @notice Allows to change the `_donationAddress` if it's called by the owner
     * @param newDonationAddress new `_donationAddress`
     * Events: `NewDonationAddress`
     */
    function setDonationAddress(address newDonationAddress)
        external
        onlyGovernance
    {
        require(
            newDonationAddress != address(0),
            "HermezAuctionProtocol::setDonationAddress: NOT_VALID_ADDRESS"
        );
        _donationAddress = newDonationAddress;
        emit NewDonationAddress(_donationAddress);
    }

    /**
     * @notice Getter of the current `_bootCoordinator`
     * @return The `_bootCoordinator`
     */
    function getBootCoordinator() external view returns (address) {
        return _bootCoordinator;
    }

    /**
     * @notice Allows to change the `_bootCoordinator` if it's called by the owner
     * @param newBootCoordinator new `_bootCoordinator` uint8[3] array
     * Events: `NewBootCoordinator`
     */
    function setBootCoordinator(address newBootCoordinator)
        external
        onlyGovernance
    {
        _bootCoordinator = newBootCoordinator;
        emit NewBootCoordinator(_bootCoordinator);
    }

    /**
     * @notice Returns the minimum default bid for an slotSet
     * @param slotSet to obtain the minimum default bid
     * @return the minimum default bid for an slotSet
     */
    function getDefaultSlotSetBid(uint8 slotSet) public view returns (uint128) {
        return _defaultSlotSetBid[slotSet];
    }

    /**
     * @notice Allows to change the change the min bid for an slotSet if it's called by the owner.
     * @dev If an slotSet has the value of 0 it's considered decentralized, so the minbid cannot be modified
     * @param slotSet the slotSet to update
     * @param newInitialMinBid the minBid
     * Events: `NewDefaultSlotSetBid`
     */
    function changeDefaultSlotSetBid(uint128 slotSet, uint128 newInitialMinBid)
        external
        onlyGovernance
    {
        require(
            slotSet <= _defaultSlotSetBid.length,
            "HermezAuctionProtocol::changeDefaultSlotSetBid: NOT_VALID_SLOT_SET"
        );
        require(
            _defaultSlotSetBid[slotSet] != 0,
            "HermezAuctionProtocol::changeDefaultSlotSetBid: SLOT_DECENTRALIZED"
        );

        uint128 current = getCurrentSlotNumber();
        // This prevents closed bids from being modified
        for (uint128 i = current; i <= current + _closedAuctionSlots; i++) {
            // Save the minbid in case it has not been previously set
            if (slots[i].closedMinBid == 0) {
                slots[i].closedMinBid = _defaultSlotSetBid[getSlotSet(i)];
            }
        }
        _defaultSlotSetBid[slotSet] = newInitialMinBid;
        emit NewDefaultSlotSetBid(slotSet, newInitialMinBid);
    }

    /**
     * @notice Allows to register a new coordinator
     * @dev The `msg.sender` will be considered the `bidder`, who can change the forger address and the url
     * @param forger the address allowed to forger batches
     * @param coordinatorURL endopoint for this coordinator
     * Events: `NewCoordinator`
     */
    function setCoordinator(address forger, string memory coordinatorURL)
        external
    {
        require(
            keccak256(abi.encodePacked(coordinatorURL)) !=
                keccak256(abi.encodePacked("")),
            "HermezAuctionProtocol::setCoordinator: NOT_VALID_URL"
        );
        coordinators[msg.sender].forger = forger;
        coordinators[msg.sender].coordinatorURL = coordinatorURL;
        emit SetCoordinator(msg.sender, forger, coordinatorURL);
    }

    /**
     * @notice Returns the current slot number
     * @return slotNumber an uint128 with the current slot
     */
    function getCurrentSlotNumber() public view returns (uint128) {
        return getSlotNumber(uint128(block.number));
    }

    /**
     * @notice Returns the slot number of a given block
     * @param blockNumber from which to calculate the slot
     * @return slotNumber an uint128 with the slot calculated
     */
    function getSlotNumber(uint128 blockNumber) public view returns (uint128) {
        return
            (blockNumber >= genesisBlock)
                ? ((blockNumber - genesisBlock) / BLOCKS_PER_SLOT)
                : uint128(0);
    }

    /**
     * @notice Returns an slotSet given an slot
     * @param slot from which to calculate the slotSet
     * @return the slotSet of the slot
     */
    function getSlotSet(uint128 slot) public view returns (uint128) {
        return slot.mod(uint128(_defaultSlotSetBid.length));
    }

    /**
     * @notice gets the minimum bid that someone has to bid to win the slot for a given slot
     * @dev it will revert in case of trying to obtain the minimum bid for a closed slot
     * @param slot from which to get the minimum bid
     * @return the minimum amount to bid
     */
    function getMinBidBySlot(uint128 slot) public view returns (uint128) {
        require(
            slot >= (getCurrentSlotNumber() + _closedAuctionSlots),
            "HermezAuctionProtocol::getMinBidBySlot: AUCTION_CLOSED"
        );
        uint128 slotSet = getSlotSet(slot);
        // If the bidAmount for a slot is 0 it means that it has not yet been bid, so the midBid will be the minimum
        // bid for the slot time plus the outbidding set, otherwise it will be the bidAmount plus the outbidding
        return
            (slots[slot].bidAmount == 0)
                ? _defaultSlotSetBid[slotSet].add(
                    _defaultSlotSetBid[slotSet].mul(_outbidding).div(
                        uint128(10000) // two decimal precision
                    )
                )
                : slots[slot].bidAmount.add(
                    slots[slot].bidAmount.mul(_outbidding).div(uint128(10000)) // two decimal precision
                );
    }

    /**
     * @notice Function to process a single bid
     * @dev If the bytes calldata permit parameter is empty the smart contract assume that it has enough allowance to
     * make the transferFrom. In case you want to use permit, you need to send the data of the permit call in bytes
     * @param amount the amount of tokens that have been sent
     * @param slot the slot for which the caller is bidding
     * @param bidAmount the amount of the bidding
     */
    function processBid(
        uint128 amount,
        uint128 slot,
        uint128 bidAmount,
        bytes calldata permit
    ) external {
        // To avoid possible mistakes we don't allow anyone to bid without setting a forger
        require(
            coordinators[msg.sender].forger != address(0),
            "HermezAuctionProtocol::processBid: COORDINATOR_NOT_REGISTERED"
        );
        require(
            slot >= (getCurrentSlotNumber() + _closedAuctionSlots),
            "HermezAuctionProtocol::processBid: AUCTION_CLOSED"
        );
        require(
            bidAmount >= getMinBidBySlot(slot),
            "HermezAuctionProtocol::processBid: BELOW_MINIMUM"
        );

        require(
            slot <
                (getCurrentSlotNumber() +
                    _closedAuctionSlots +
                    _openAuctionSlots),
            "HermezAuctionProtocol::processBid: AUCTION_NOT_OPEN"
        );

        if (permit.length != 0) {
            _permit(amount, permit);
        }

        require(
            tokenHEZ.transferFrom(msg.sender, address(this), amount),
            "HermezAuctionProtocol::processBid: TOKEN_TRANSFER_FAILED"
        );
        pendingBalances[msg.sender] = pendingBalances[msg.sender].add(amount);

        require(
            pendingBalances[msg.sender] >= bidAmount,
            "HermezAuctionProtocol::processBid: NOT_ENOUGH_BALANCE"
        );
        _doBid(slot, bidAmount, msg.sender);
    }

    /**
     * @notice function to process a multi bid
     * @dev If the bytes calldata permit parameter is empty the smart contract assume that it has enough allowance to
     * make the transferFrom. In case you want to use permit, you need to send the data of the permit call in bytes
     * @param amount the amount of tokens that have been sent
     * @param startingSlot the first slot to bid
     * @param endingSlot the last slot to bid
     * @param slotSets the set of slots to which the coordinator wants to bid
     * @param maxBid the maximum bid that is allowed
     * @param minBid the minimum that you want to bid
     */
    function processMultiBid(
        uint128 amount,
        uint128 startingSlot,
        uint128 endingSlot,
        bool[6] memory slotSets,
        uint128 maxBid,
        uint128 minBid,
        bytes calldata permit
    ) external {
        require(
            startingSlot >= (getCurrentSlotNumber() + _closedAuctionSlots),
            "HermezAuctionProtocol::processMultiBid AUCTION_CLOSED"
        );
        require(
            endingSlot <
                (getCurrentSlotNumber() +
                    _closedAuctionSlots +
                    _openAuctionSlots),
            "HermezAuctionProtocol::processMultiBid AUCTION_NOT_OPEN"
        );
        require(
            maxBid >= minBid,
            "HermezAuctionProtocol::processMultiBid MAXBID_GREATER_THAN_MINBID"
        );
        // To avoid possible mistakes we don't allow anyone to bid without setting a forger
        require(
            coordinators[msg.sender].forger != address(0),
            "HermezAuctionProtocol::processMultiBid COORDINATOR_NOT_REGISTERED"
        );

        if (permit.length != 0) {
            _permit(amount, permit);
        }

        require(
            tokenHEZ.transferFrom(msg.sender, address(this), amount),
            "HermezAuctionProtocol::processMultiBid: TOKEN_TRANSFER_FAILED"
        );
        pendingBalances[msg.sender] = pendingBalances[msg.sender].add(amount);

        uint128 bidAmount;
        for (uint128 slot = startingSlot; slot <= endingSlot; slot++) {
            uint128 minBidBySlot = getMinBidBySlot(slot);
            // In case that the minimum bid is below the desired minimum bid, we will use this lower limit as the bid
            if (minBidBySlot <= minBid) {
                bidAmount = minBid;
                // If the `minBidBySlot` is between the upper (`maxBid`) and lower limit (`minBid`) we will use
                // this value `minBidBySlot` as the bid
            } else if (minBidBySlot > minBid && minBidBySlot <= maxBid) {
                bidAmount = minBidBySlot;
                // if the `minBidBySlot` is higher than the upper limit `maxBid`, we will not bid for this slot
            } else {
                continue;
            }

            // check if it is a selected slotSet
            if (slotSets[getSlotSet(slot)]) {
                require(
                    pendingBalances[msg.sender] >= bidAmount,
                    "HermezAuctionProtocol::processMultiBid NOT_ENOUGH_BALANCE"
                );
                _doBid(slot, bidAmount, msg.sender);
            }
        }
    }

    /**
     * @notice function to call token permit function
     * @param _amount the quantity that is expected to be allowed
     * @param _permitData the raw data of the call `permit` of the token
     */
    function _permit(uint256 _amount, bytes calldata _permitData) internal {
        bytes4 sig = abi.decode(_permitData, (bytes4));

        require(
            sig == _PERMIT_SIGNATURE,
            "HermezAuctionProtocol::_permit: NOT_VALID_CALL"
        );
        (
            address owner,
            address spender,
            uint256 value,
            uint256 deadline,
            uint8 v,
            bytes32 r,
            bytes32 s
        ) = abi.decode(
            _permitData[4:],
            (address, address, uint256, uint256, uint8, bytes32, bytes32)
        );
        require(
            owner == msg.sender,
            "HermezAuctionProtocol::_permit: OWNER_NOT_EQUAL_SENDER"
        );
        require(
            spender == address(this),
            "HermezAuctionProtocol::_permit: SPENDER_NOT_EQUAL_THIS"
        );
        require(
            value == _amount,
            "HermezAuctionProtocol::_permit: WRONG_AMOUNT"
        );

        // we call without checking the result, in case it fails and he doesn't have enough balance
        // the following transferFrom should be fail. This prevents DoS attacks from using a signature
        // before the smartcontract call
        /* solhint-disable avoid-low-level-calls avoid-call-value */
        address(tokenHEZ).call(
            abi.encodeWithSelector(
                _PERMIT_SIGNATURE,
                owner,
                spender,
                value,
                deadline,
                v,
                r,
                s
            )
        );
    }

    /**
     * @notice Internal function to make the bid
     * @dev will only be called by processBid or processMultiBid
     * @param slot the slot for which the caller is bidding
     * @param bidAmount the amount of the bidding
     * @param bidder the address of the bidder
     * Events: `NewBid`
     */
    function _doBid(
        uint128 slot,
        uint128 bidAmount,
        address bidder
    ) private {
        address prevBidder = slots[slot].bidder;
        uint128 prevBidValue = slots[slot].bidAmount;

        pendingBalances[bidder] = pendingBalances[bidder].sub(bidAmount);

        slots[slot].bidder = bidder;
        slots[slot].bidAmount = bidAmount;

        // If there is a previous bid we must return the HEZ tokens
        if (prevBidder != address(0) && prevBidValue != 0) {
            pendingBalances[prevBidder] = pendingBalances[prevBidder].add(
                prevBidValue
            );
        }
        emit NewBid(slot, bidAmount, bidder);
    }

    /**
     * @notice function to know if a certain address can forge into a certain block
     * @param forger the address of the coodirnator's forger
     * @param blockNumber block number to check
     * @return a bool true in case it can forge, false otherwise
     */
    function canForge(address forger, uint256 blockNumber)
        public
        view
        returns (bool)
    {
        require(
            blockNumber < 2**128,
            "HermezAuctionProtocol::canForge WRONG_BLOCKNUMBER"
        );
        require(
            blockNumber >= genesisBlock,
            "HermezAuctionProtocol::canForge AUCTION_NOT_STARTED"
        );

        uint128 slotToForge = getSlotNumber(uint128(blockNumber));
        // Get the relativeBlock to check if the slotDeadline has been exceeded
        uint128 relativeBlock = uint128(blockNumber).sub(
            (slotToForge.mul(BLOCKS_PER_SLOT)).add(genesisBlock)
        );
        // If the closedMinBid is 0 it means that we have to take as minBid the one that is set for this slot set,
        // otherwise the one that has been saved will be used
        uint128 minBid = (slots[slotToForge].closedMinBid == 0)
            ? _defaultSlotSetBid[getSlotSet(slotToForge)]
            : slots[slotToForge].closedMinBid;

        // if the relative block has exceeded the slotDeadline and no batch has been forged, anyone can forge
        if (!slots[slotToForge].fulfilled && (relativeBlock >= _slotDeadline)) {
            return true;
            //if forger bidAmount has exceeded the minBid it can forge
        } else if (
            (coordinators[slots[slotToForge].bidder].forger == forger) &&
            (slots[slotToForge].bidAmount >= minBid)
        ) {
            return true;
            //if it's the boot coordinator and it has not been bid or the bid is below the minimum it can forge
        } else if (
            (_bootCoordinator == forger) &&
            ((slots[slotToForge].bidAmount < minBid) ||
                (slots[slotToForge].bidAmount == 0))
        ) {
            return true;
            // if it is not any of these three cases will not be able to forge
        } else {
            return false;
        }
    }

    /**
     * @notice function to process the forging
     * @param forger the address of the coodirnator's forger
     * Events: `NewForgeAllocated` and `NewForge`
     */
    function forge(address forger) external {
        require(
            msg.sender == hermezRollup,
            "HermezAuctionProtocol::forge: ONLY_HERMEZ_ROLLUP"
        );
        require(
            canForge(forger, block.number),
            "HermezAuctionProtocol::forge: CANNOT_FORGE"
        );
        uint128 slotToForge = getCurrentSlotNumber();

        bool prevFulfilled = slots[slotToForge].fulfilled;

        // If the closedMinBid is 0 it means that we have to take as minBid the one that is set for this slot set,
        // otherwise the one that has been saved will be used
        uint128 minBid = (slots[slotToForge].closedMinBid == 0)
            ? _defaultSlotSetBid[getSlotSet(slotToForge)]
            : slots[slotToForge].closedMinBid;

        // Default values:** Burn: 40% - Donation: 40% - HGT: 20%
        // Allocated is used to know if we have already distributed the HEZ tokens
        if (!prevFulfilled) {
            slots[slotToForge].fulfilled = true;

            // If the bootcoordinator is forging and there has been a previous bid that is lower than the slot min bid,
            // we must return the tokens to the bidder and the tokens have not been distributed
            if (
                (_bootCoordinator == forger) &&
                (slots[slotToForge].bidAmount != 0) &&
                (slots[slotToForge].bidAmount < minBid)
            ) {
                // We save the minBid that this block has had
                slots[slotToForge].closedMinBid = minBid;
                pendingBalances[slots[slotToForge]
                    .bidder] = pendingBalances[slots[slotToForge].bidder].add(
                    slots[slotToForge].bidAmount
                );
                // In case the winner is forging we have to allocate the tokens according to the desired distribution
            } else if (_bootCoordinator != forger) {
                // We save the minBid that this block has had
                slots[slotToForge].closedMinBid = slots[slotToForge].bidAmount;
                // calculation of token distribution
                uint128 burnAmount = slots[slotToForge]
                    .bidAmount
                    .mul(_allocationRatio[0])
                    .div(uint128(10000)); // Two decimal precision
                uint128 donationAmount = slots[slotToForge]
                    .bidAmount
                    .mul(_allocationRatio[1])
                    .div(uint128(10000)); // Two decimal precision
                uint128 governanceAmount = slots[slotToForge]
                    .bidAmount
                    .mul(_allocationRatio[2])
                    .div(uint128(10000)); // Two decimal precision
                // Tokens to burn
                tokenHEZ.burn(burnAmount);
                // Tokens to donate
                pendingBalances[_donationAddress] = pendingBalances[_donationAddress]
                    .add(donationAmount);
                // Tokens for the governace address
                pendingBalances[_governanceAddress] = pendingBalances[_governanceAddress]
                    .add(governanceAmount);

                emit NewForgeAllocated(
                    slots[slotToForge].bidder,
                    forger,
                    slotToForge,
                    burnAmount,
                    donationAmount,
                    governanceAmount
                );
            }
        }
        emit NewForge(forger, slotToForge);
    }

    /**
     * @notice function to know how much HEZ tokens are pending to be claimed for an address
     * @param bidder address to query
     * @return the total claimable HEZ by an address
     */
    function getClaimableHEZ(address bidder) public view returns (uint128) {
        return pendingBalances[bidder];
    }

    /**
     * @notice distributes the tokens to msg.sender address
     * Events: `HEZClaimed`
     */
    function claimHEZ() public nonReentrant {
        uint128 pending = getClaimableHEZ(msg.sender);
        require(
            pending > 0,
            "HermezAuctionProtocol::claimHEZ: NOT_ENOUGH_BALANCE"
        );
        pendingBalances[msg.sender] = 0;
        require(
            tokenHEZ.transfer(msg.sender, pending),
            "HermezAuctionProtocol::claimHEZ: TOKEN_TRANSFER_FAILED"
        );
        emit HEZClaimed(msg.sender, pending);
    }
}
