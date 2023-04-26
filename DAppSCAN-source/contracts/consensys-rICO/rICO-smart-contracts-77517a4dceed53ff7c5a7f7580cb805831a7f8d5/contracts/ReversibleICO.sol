/*
 * source       https://github.com/lukso-network/rICO-smart-contracts
 * @name        rICO
 * @package     rICO-smart-contracts
 * @author      Micky Socaci <micky@binarzone.com>, Fabian Vogelsteller <@frozeman>, Marjorie Hernandez <marjorie@lukso.io>
 * @license     MIT
 */

pragma solidity ^0.5.0;

import "./zeppelin/math/SafeMath.sol";
import "./zeppelin/token/ERC777/IERC777.sol";
import "./zeppelin/token/ERC777/IERC777Recipient.sol";
import "./zeppelin/introspection/IERC1820Registry.sol";

contract ReversibleICO is IERC777Recipient {


    /*
     *   Instances
     */
    using SafeMath for uint256;

    /// @dev The address of the introspection registry contract deployed.
    IERC1820Registry private ERC1820 = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
    bytes32 constant private TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");


    /*
     *   Contract States
     */
    /// @dev It is set to TRUE after the deployer initializes the contract.
    bool public initialized;

    /// @dev Security guard. The freezer address can the freeze the contract and move its funds in case of emergency.
    bool public frozen;
    uint256 public frozenPeriod;
    uint256 public freezeStart;


    /*
     *   Addresses
     */
    /// @dev Only the deploying address is allowed to initialize the contract.
    address public deployingAddress;
    /// @dev The rICO token contract address.
    address public tokenAddress;
    /// @dev The address of wallet of the project running the rICO.
    address public projectAddress;
    /// @dev Only the whitelist controller can whitelist addresses.
    address public whitelistingAddress;
    /// @dev Only the freezer address can call the freeze functions.
    address public freezerAddress;
    /// @dev Only the rescuer address can move funds if the rICO is frozen.
    address public rescuerAddress;


    /*
     *   Public Variables
     */
    /// @dev Total amount tokens available to be bought.
    uint256 public tokenSupply;
    /// @dev Total amount of ETH currently accepted as a commitment to buy tokens (excluding pendingETH).
    uint256 public committedETH;
    /// @dev Total amount of ETH currently pending to be whitelisted.
    uint256 public pendingETH;
    /// @dev Accumulated amount of all ETH returned from canceled pending ETH.
    uint256 public canceledETH;
    /// @dev Accumulated amount of all ETH withdrawn by participants.
    uint256 public withdrawnETH;
    /// @dev Count of the number the project has withdrawn from the funds raised.
    uint256 public projectWithdrawCount;
    /// @dev Total amount of ETH withdrawn by the project
    uint256 public projectWithdrawnETH;

    /// @dev Minimum amount of ETH accepted for a contribution. Everything lower than that will trigger a canceling of pending ETH.
    uint256 public minContribution = 0.001 ether;

    mapping(uint8 => Stage) public stages;
    uint256 public stageBlockCount;
    uint8 public stageCount;

    /// @dev Maps participants stats by their address.
    mapping(address => Participant) public participants;
    /// @dev Maps participants address to a unique participant ID (incremental IDs, based on "participantCount").
    mapping(uint256 => address) public participantsById; // TODO remove?
    /// @dev Total number of rICO participants.
    uint256 public participantCount;

    /*
     *   Commit phase (Stage 0)
     */
    /// @dev Initial token price in the commit phase (Stage 0).
    uint256 public commitPhasePrice;
    /// @dev Block number that indicates the start of the commit phase.
    uint256 public commitPhaseStartBlock;
    /// @dev Block number that indicates the end of the commit phase.
    uint256 public commitPhaseEndBlock;
    /// @dev The duration of the commit phase in blocks.
    uint256 public commitPhaseBlockCount;


    /*
     *   Buy phases (Stages 1-n)
     */
    /// @dev Block number that indicates the start of the buy phase (Stages 1-n).
    uint256 public buyPhaseStartBlock;
    /// @dev Block number that indicates the end of the buy phase.
    uint256 public buyPhaseEndBlock;
    /// @dev The duration of the buy phase in blocks.
    uint256 public buyPhaseBlockCount;

//    uint256 public DEBUG1 = 9999;
//    uint256 public DEBUG2 = 9999;
//    uint256 public DEBUG3 = 9999;
//    uint256 public DEBUG4 = 9999;

    /*
    *   Internal Variables
    */
    /// @dev Total amount of the current reserved ETH for the project by the participants contributions.
    uint256 internal _projectCurrentlyReservedETH;
    /// @dev Accumulated amount allocated to the project by participants.
    uint256 internal _projectUnlockedETH;
    /// @dev Last block since the project has calculated the _projectUnlockedETH.
    uint256 internal _projectLastBlock;


    /*
    *   Structs
    */

    /*
     *   Stages
     *   Stage 0 = commit phase
     *   Stage 1-n = buy phase
     */
    struct Stage {
        uint128 startBlock;
        uint128 endBlock;
        uint256 tokenPrice;
    }

    /*
     * Participants
     */
    struct Participant {
        bool whitelisted;
        uint32 contributions;
        uint32 withdraws;
        uint256 reservedTokens;
        uint256 committedETH;
        uint256 pendingETH;

        uint256 _currentReservedTokens;
        uint256 _unlockedTokens;
        uint256 _lastBlock;

        mapping(uint8 => ParticipantStageDetails) stages;
    }

    struct ParticipantStageDetails {
        uint256 pendingETH;
    }

    /*
     * Events
     */
    event ApplicationEvent (
        uint8 indexed typeId,
        uint32 indexed id,
        address indexed relatedAddress,
        uint256 value
    );

    event TransferEvent (
        uint8 indexed typeId,
        address indexed relatedAddress,
        uint256 indexed value
    );

    enum ApplicationEventTypes {
        NOT_SET, // 0; will match default value of a mapping result
        CONTRIBUTION_ADDED, // 1
        CONTRIBUTION_CANCELED, // 2
        CONTRIBUTION_ACCEPTED, // 3
        WHITELIST_APPROVED, // 4
        WHITELIST_REJECTED, // 5
        PROJECT_WITHDRAWN, // 6
        FROZEN_FREEZE, // 7
        FROZEN_UNFREEZE, // 8
        FROZEN_DISBALEHATCH, // 9
        FROZEN_ESCAPEHATCH // 10
    }

    enum TransferTypes {
        NOT_SET, // 0
        WHITELIST_REJECTED, // 1
        CONTRIBUTION_CANCELED, // 2
        CONTRIBUTION_ACCEPTED_OVERFLOW, // 3 not accepted ETH
        PARTICIPANT_WITHDRAW, // 4
        PARTICIPANT_WITHDRAW_OVERFLOW, // 5 not returnable tokens
        PROJECT_WITHDRAWN, // 6
        FROZEN_ESCAPEHATCH_TOKEN, // 7
        FROZEN_ESCAPEHATCH_ETH // 8
    }


    // ------------------------------------------------------------------------------------------------

    /// @notice Constructor sets the deployer and defines ERC777TokensRecipient interface support.
    constructor() public {
        deployingAddress = msg.sender;
        ERC1820.setInterfaceImplementer(address(this), TOKENS_RECIPIENT_INTERFACE_HASH, address(this));
    }

    /**
     * @notice Initializes the contract. Only the deployer (set in the constructor) can call this method.
     * @param _tokenAddress The address of the ERC777 rICO token contract.
     * @param _whitelistingAddress The address handling whitelisting.
     * @param _projectAddress The project wallet that can withdraw ETH contributions.
     * @param _commitPhaseStartBlock The block at which the commit phase starts.
     * @param _commitPhaseBlockCount The duration of the commit phase in blocks.
     * @param _commitPhasePrice The initial token price (in WEI per token) during the commit phase.
     * @param _stageCount The number of the rICO stages, excluding the commit phase (Stage 0).
     * @param _stageBlockCount The duration of each stage in blocks.
     * @param _stagePriceIncrease A factor used to increase the token price from the _commitPhasePrice at each subsequent stage. The increase already happens in the first stage too.
     */
    function init(
        address _tokenAddress,
        address _whitelistingAddress,
        address _projectAddress,
        uint256 _commitPhaseStartBlock,
        uint256 _commitPhaseBlockCount,
        uint256 _commitPhasePrice,
        uint8 _stageCount,
        uint256 _stageBlockCount,
        uint256 _stagePriceIncrease
    )
    public
    onlyDeployingAddress
    isNotInitialized
    {

        require(_commitPhaseStartBlock > getCurrentBlockNumber(), "Start block cannot be set in the past.");

        // Assign address variables
        tokenAddress = _tokenAddress;
        whitelistingAddress = _whitelistingAddress;
        projectAddress = _projectAddress;
        freezerAddress = _projectAddress; // TODO change, here only for testing
        rescuerAddress = _projectAddress; // TODO change, here only for testing

        // UPDATE global STATS
        commitPhaseStartBlock = _commitPhaseStartBlock;
        commitPhaseBlockCount = _commitPhaseBlockCount;
        commitPhaseEndBlock = _commitPhaseStartBlock.add(_commitPhaseBlockCount).sub(1);
        commitPhasePrice = _commitPhasePrice;

        stageBlockCount = _stageBlockCount;
        stageCount = _stageCount;

        // Setup stage 0: The commit phase.
        Stage storage commitPhase = stages[0];

        commitPhase.startBlock = uint128(_commitPhaseStartBlock);
        commitPhase.endBlock = uint128(commitPhaseEndBlock);
        commitPhase.tokenPrice = _commitPhasePrice;

        // Setup stage 1 to n: The buy phase stages
        // Each new stage starts after the previous phase's endBlock
        uint256 previousStageEndBlock = commitPhase.endBlock;

        // Update stages: start, end, price
        for (uint8 i = 1; i <= _stageCount; i++) {
            // Get i-th stage
            Stage storage stageN = stages[i];
            // Start block is previous phase end block + 1, e.g. previous stage end=0, start=1;
            stageN.startBlock = uint128(previousStageEndBlock.add(1));
            // End block is previous phase end block + stage duration e.g. start=1, duration=10, end=0+10=10;
            stageN.endBlock = uint128(previousStageEndBlock.add(_stageBlockCount));
            // Store the current stage endBlock in order to update the next one
            previousStageEndBlock = stageN.endBlock;
            // At each stage the token price increases by _stagePriceIncrease * stageCount
            stageN.tokenPrice = _commitPhasePrice.add(_stagePriceIncrease.mul(i));
        }

        // UPDATE global STATS
        // The buy phase starts on the subsequent block of the commitPhase's (stage0) endBlock
        buyPhaseStartBlock = commitPhaseEndBlock.add(1);
        // The buy phase ends when the lat stage ends
        buyPhaseEndBlock = previousStageEndBlock;
        // The duration of buyPhase in blocks
        buyPhaseBlockCount = buyPhaseEndBlock.sub(buyPhaseStartBlock).add(1);

        // The contract is now initialized
        initialized = true;
    }

    /*
     * Public functions
     * ------------------------------------------------------------------------------------------------
     */

    /*
     * Public functions
     * The main way to interact with the rICO.
     */

    /**
     * @notice FALLBACK function: If the amount sent is smaller than `minContribution` it cancels all pending contributions.
     */
    function()
    external
    payable
    isInitialized
    isNotFrozen
    {
        require(msg.value < minContribution, 'To contribute, call the commit() function and send ETH along.');

        // Participant cancels pending contributions.
        cancelPendingContributions(msg.sender, msg.value);
    }

    /**
     * @notice ERC777TokensRecipient implementation for receiving ERC777 tokens.
     * @param _from Token sender.
     * @param _amount Token amount.
     */
    function tokensReceived(
        address,
        address _from,
        address,
        uint256 _amount,
        bytes calldata,
        bytes calldata
    )
    external
    isInitialized
    isNotFrozen
    {
        // rICO should only receive tokens from the rICO token contract.
        // Transactions from any other token contract revert
        require(msg.sender == tokenAddress, "Invalid token contract sent tokens.");

        // Project wallet adds tokens to the sale
        if (_from == projectAddress) {
            // increase the supply
            tokenSupply = tokenSupply.add(_amount);

            // rICO participant sends tokens back
        } else {
            withdraw(_from, _amount);
        }
    }

    /**
     * @notice Allows a participant to reserve tokens by committing ETH as contributions.
     */
    function commit()
    external
    payable
    isInitialized
    isNotFrozen
    isRunning
    {
        // Reject contributions lower than the minimum amount
        require(msg.value >= minContribution, "Value sent is less than minimum contribution.");

        // Participant initial state record
        Participant storage participantStats = participants[msg.sender];
        ParticipantStageDetails storage byStage = participantStats.stages[getCurrentStage()];

        // Check if participant already exists
        if (participantStats.contributions == 0) {
            // Identify the participants by their Id
            participantsById[participantCount] = msg.sender;
            // Increase participant count
            participantCount++;
        }

        // UPDATE PARTICIPANT STATS
        participantStats.contributions++;
        participantStats.pendingETH = participantStats.pendingETH.add(msg.value);
        byStage.pendingETH = byStage.pendingETH.add(msg.value);

        // UPDATE GLOBAL STATS
        pendingETH = pendingETH.add(msg.value);

        emit ApplicationEvent(
            uint8(ApplicationEventTypes.CONTRIBUTION_ADDED),
            uint32(participantStats.contributions),
            msg.sender,
            msg.value
        );

        // If whitelisted, process the contribution automatically
        if (participantStats.whitelisted == true) {
            acceptContributions(msg.sender);
        }
    }

    /**
     * @notice Allows a participant to cancel pending contributions
     */
    function cancel()
    external
    payable
    isInitialized
    isNotFrozen
    {
        cancelPendingContributions(msg.sender, msg.value);
    }

    /**
     * @notice Approves or rejects participants.
     * @param _addresses The list of participant address.
     * @param _approve Indicates if the provided participants are approved (true) or rejected (false).
     */
    function whitelist(address[] calldata _addresses, bool _approve)
    external
    onlyWhitelistingAddress
    isInitialized
    isNotFrozen
    isRunning
    {
        // Revert if the provided list is empty
        require(_addresses.length > 0, "No addresses given to whitelist.");

        for (uint256 i = 0; i < _addresses.length; i++) {
            address participantAddress = _addresses[i];

            Participant storage participantStats = participants[participantAddress];

            if (_approve) {
                if (!participantStats.whitelisted) {
                    // If participants are approved: whitelist them and accept their contributions
                    participantStats.whitelisted = true;
                    emit ApplicationEvent(uint8(ApplicationEventTypes.WHITELIST_APPROVED), getCurrentStage(), participantAddress, 0);
                }

                // accept any pending ETH
                acceptContributions(participantAddress);

            } else {
                emit ApplicationEvent(uint8(ApplicationEventTypes.WHITELIST_REJECTED), getCurrentStage(), participantAddress, 0);
                participantStats.whitelisted = false;

                // Cancel participants pending contributions.
                cancelPendingContributions(participantAddress, 0);
            }
        }
    }

    /**
     * @notice Allows for the project to withdraw ETH.
     * @param _ethAmount The ETH amount in wei.
     */
    function projectWithdraw(uint256 _ethAmount)
    external
    onlyProjectAddress
    isInitialized
    isNotFrozen
    {
        // UPDATE the locked/unlocked ratio for the project
        calcProjectAllocation();

        // Get current allocated ETH to the project
        uint256 availableForWithdraw = _projectUnlockedETH.sub(projectWithdrawnETH);

        require(_ethAmount <= availableForWithdraw, "Requested amount too high, not enough ETH unlocked.");

        // UPDATE global STATS
        projectWithdrawCount++;
        projectWithdrawnETH = projectWithdrawnETH.add(_ethAmount);

        // Event emission
        emit ApplicationEvent(
            uint8(ApplicationEventTypes.PROJECT_WITHDRAWN),
            uint32(projectWithdrawCount),
            projectAddress,
            _ethAmount
        );
        emit TransferEvent(
            uint8(TransferTypes.PROJECT_WITHDRAWN),
            projectAddress,
            _ethAmount
        );

        // Transfer ETH to project wallet
        address(uint160(projectAddress)).transfer(_ethAmount);
    }


    /*
    * Security functions.
    * If the rICO runs fine the freezer address can be set to 0x0, for the beginning its good to have a safe guard.
    */

    /**
     * @notice Freezes the rICO in case of emergency.
     */
    function freeze()
    external
    onlyFreezerAddress
    isNotFrozen
    {
        frozen = true;
        freezeStart = getCurrentBlockNumber();

        // Emit event
        emit ApplicationEvent(uint8(ApplicationEventTypes.FROZEN_FREEZE), uint32(getCurrentStage()), freezerAddress, getCurrentBlockNumber());
    }

    /**
     * @notice Un-freezes the rICO.
     */
    function unfreeze()
    external
    onlyFreezerAddress
    isFrozen
    {
        uint256 currentBlock = getCurrentBlockNumber();

        frozen = false;
        frozenPeriod = frozenPeriod.add(
            currentBlock.sub(freezeStart)
        );

        // Emit event
        emit ApplicationEvent(uint8(ApplicationEventTypes.FROZEN_UNFREEZE), uint32(getCurrentStage()), freezerAddress, currentBlock);
    }

    /**
     * @notice Sets the freeze address to 0x0
     */
    function disableEscapeHatch()
    external
    onlyFreezerAddress
    isNotFrozen
    {
        freezerAddress = address(0);
        rescuerAddress = address(0);

        // Emit event
        emit ApplicationEvent(uint8(ApplicationEventTypes.FROZEN_DISBALEHATCH), uint32(getCurrentStage()), freezerAddress, getCurrentBlockNumber());
    }

    /**
     * @notice Moves the funds to a safe place, in case of emergency. Only possible, when the the rICO is frozen.
     */
    function escapeHatch(address _to)
    external
    onlyRescuerAddress
    isFrozen
    {
        require(getCurrentBlockNumber() == freezeStart.add(18000), 'Let it cool.. Wait at least ~3 days (18000 blk) before moving anything.');

        uint256 tokenBalance = IERC777(tokenAddress).balanceOf(address(this));
        uint256 ethBalance = address(this).balance;

        // sent all tokens from the contract to the _to address
        // solium-disable-next-line security/no-send
        IERC777(tokenAddress).send(_to, tokenBalance, "");

        // sent all ETH from the contract to the _to address
        address(uint160(_to)).transfer(ethBalance);

        // Emit event
        emit ApplicationEvent(uint8(ApplicationEventTypes.FROZEN_ESCAPEHATCH), uint32(getCurrentStage()), _to, getCurrentBlockNumber());
        emit TransferEvent(uint8(TransferTypes.FROZEN_ESCAPEHATCH_TOKEN), _to, tokenBalance);
        emit TransferEvent(uint8(TransferTypes.FROZEN_ESCAPEHATCH_ETH), _to, ethBalance);
    }


    /*
     * Public view functions
     * ------------------------------------------------------------------------------------------------
     */

    /**
     * @notice Returns project's total unlocked ETH.
     * @return uint256 The amount of ETH unlocked over the whole rICO.
     */
    function getUnlockedProjectETH() public view returns (uint256) {

        // calc from the last known point on
        uint256 newlyUnlockedEth = calcUnlockedAmount(_projectCurrentlyReservedETH, _projectLastBlock);

        return _projectUnlockedETH
        .add(newlyUnlockedEth);
    }

    /**
     * @notice Returns project's current available unlocked ETH reduced by what was already withdrawn.
     * @return uint256 The amount of ETH available to the project for withdraw.
     */
    function getAvailableProjectETH() public view returns (uint256) {
        return getUnlockedProjectETH()
            .sub(projectWithdrawnETH);
    }

    /**
     * @notice Returns the participant's amount of locked tokens at the current block.
     * @param _participantAddress The participant's address.
     */
    function getParticipantReservedTokens(address _participantAddress) public view returns (uint256) {
        Participant storage participantStats = participants[_participantAddress];

        if(participantStats._currentReservedTokens == 0) {
            return 0;
        }

        return participantStats._currentReservedTokens.sub(
            calcUnlockedAmount(participantStats._currentReservedTokens, participantStats._lastBlock)
        );
    }

    /**
     * @notice Returns the participant's amount of unlocked tokens at the current block.
     * This function is used for internal sanity checks.
     * Note: this value can differ from the actual unlocked token balance of the participant, if he received tokens from other sources than the rICO.
     * @param _participantAddress The participant's address.
     */
    function getParticipantUnlockedTokens(address _participantAddress) public view returns (uint256) {
        Participant storage participantStats = participants[_participantAddress];

        return participantStats._unlockedTokens.add(
            calcUnlockedAmount(participantStats._currentReservedTokens, participantStats._lastBlock)
        );
    }

    /**
     * @notice Returns the current stage at the current block number.
     * @return The current stage ID
     */
    function getCurrentStage() public view returns (uint8) {
        uint blockNumber;
        if (frozen) {
            blockNumber = freezeStart;
        } else {
            blockNumber = getCurrentBlockNumber().add(frozenPeriod); // we add the frozenPeriod here, as we deduct it in getStageAtBlock()
        }
    return getStageAtBlock(blockNumber);
    }

    /**
     * @notice Returns the current token price at the current block number.
     * @return The current ETH price in wei.
     */
    function getCurrentPrice() public view returns (uint256) {
        uint blockNumber;
        if (frozen) {
            blockNumber = freezeStart;
        } else {
            blockNumber = getCurrentBlockNumber().add(frozenPeriod); // we add the frozenPeriod here, as we deduct it in getStageAtBlock()
        }
        return getPriceAtBlock(blockNumber);
    }

    /**
     * @notice Returns the token price at the specified block number.
     * @param _blockNumber the block number at which we want to retrieve the token price.
     * @return The ETH price in wei
     */
    function getPriceAtBlock(uint256 _blockNumber) public view returns (uint256) {
        return getPriceAtStage(getStageAtBlock(_blockNumber));
    }

    /**
     * @notice Returns the token price at the specified stage ID.
     * @param _stageId the stage ID at which we want to retrieve the token price.
     */
    function getPriceAtStage(uint8 _stageId) public view returns (uint256) {
        if (_stageId <= stageCount) {
            return stages[_stageId].tokenPrice;
        }
        revert("No price data found.");
    }

    /**
    * @notice Returns the stage which a given block belongs to.
    * @param _blockNumber The block number.
    * TODO check math
    */
    function getStageAtBlock(uint256 _blockNumber) public view returns (uint8) {

        uint256 blockNumber = _blockNumber.sub(frozenPeriod); // adjust the block by the frozen period

        require(blockNumber >= commitPhaseStartBlock && blockNumber <= buyPhaseEndBlock, "Block outside of rICO period.");

        if (blockNumber <= commitPhaseEndBlock) {
            return 0;
        }

        // This is the number of blocks starting from the first stage.
        uint256 distance = blockNumber - (commitPhaseEndBlock + 1);
        // Get the stageId (1..stageCount), commitPhase is stage 0
        // e.g. distance = 5, stageBlockCount = 5, stageID = 2
        uint256 stageID = 1 + (distance / stageBlockCount);

        return uint8(stageID);
    }

    /**
     * @notice Returns the rICOs available ETH to reserve tokens at a given stage.
     * @param _stageId the stage ID.
     * TODO we use such functions in the main commit calculations, are there chances of rounding errors?
     */
    function committableEthAtStage(uint8 _stageId) public view returns (uint256) {
        return getEthAmountForTokensAtStage(
            tokenSupply // instead of IERC777(tokenAddress).balanceOf(address(this)), as we need to deduct it BEFORE we sent everything
        , _stageId);
    }

    /**
     * @notice Returns the amount of tokens that given ETH would buy at a given stage.
     * @param _ethAmount The ETH amount in wei.
     * @param _stageId the stage ID.
     * @return The token amount in its smallest unit (token "wei")
     */
    function getTokenAmountForEthAtStage(uint256 _ethAmount, uint8 _stageId) public view returns (uint256) {
        return _ethAmount
        .mul(10 ** 18)
        .div(stages[_stageId].tokenPrice);
    }

    /**
     * @notice Returns the amount of ETH (in wei) for a given token amount at a given stage.
     * @param _tokenAmount The amount of token.
     * @param _stageId the stage ID.
     * @return The ETH amount in wei
     */
    function getEthAmountForTokensAtStage(uint256 _tokenAmount, uint8 _stageId) public view returns (uint256) {
        return _tokenAmount
        .mul(stages[_stageId].tokenPrice)
        .div(10 ** 18);
    }

    /**
     * @notice Returns the current block number: required in order to override when running tests.
     */
    function getCurrentBlockNumber() public view returns (uint256) {
        return uint256(block.number)
        .sub(frozenPeriod); // make sure we deduct any frozenPeriod from calculations
    }

    /**
     * @notice rICO HEART: Calculates the unlocked amount tokens/ETH beginning from the buy phase start or last block to the current block.
     * This function is used by the participants as well as the project, to calculate the current unlocked amount.
     *
     * @return the unlocked amount of tokens or ETH.
     */
    function calcUnlockedAmount(uint256 _amount, uint256 _lastBlock) public view returns (uint256) {

        uint256 currentBlock = getCurrentBlockNumber();

        if(_amount == 0) {
            return 0;
        }

        // Calculate WITHIN the buy phase
        if (currentBlock >= buyPhaseStartBlock && currentBlock < buyPhaseEndBlock) {

            // security/no-assign-params: "calcUnlockedAmount": Avoid assigning to function parameters.
            uint256 lastBlock = _lastBlock;
            if(lastBlock < buyPhaseStartBlock) {
                lastBlock = buyPhaseStartBlock.sub(1); // We need to reduce it by 1, as the startBlock is always already IN the period.
            }

            // get the number of blocks that have "elapsed" since the last block
            uint256 passedBlocks = currentBlock.sub(lastBlock);

            // number of blocks ( ie: start=4/end=10 => 10 - 4 => 6 )
            uint256 totalBlockCount = buyPhaseEndBlock.sub(lastBlock);

            return _amount.mul(
                passedBlocks.mul(10 ** 20)
                .div(totalBlockCount)
            ).div(10 ** 20);

            // Return everything AFTER the buy phase
        } else if (currentBlock >= buyPhaseEndBlock) {
            return _amount;
        }
        // Return nothing BEFORE the buy phase
        return 0;
    }

    /*
     * Internal functions
     * ------------------------------------------------------------------------------------------------
     */


    /**
    * @notice Checks the projects core variables and ETH amounts in the contract for correctness.
    */
    function sanityCheckProject() internal view {
        // PROJECT: The sum of reserved + unlocked has to be equal the committedETH.
        require(
            committedETH == _projectCurrentlyReservedETH.add(_projectUnlockedETH),
            'Project Sanity check failed! Reserved + Unlock must equal committedETH'
        );

//        DEBUG1 = address(this).balance;
//        DEBUG2 = _projectCurrentlyReservedETH;
//        DEBUG3 = pendingETH;

        // PROJECT: The ETH in the rICO has to be the total of unlocked + reserved - withdraw
        require(
            address(this).balance == _projectUnlockedETH.add(_projectCurrentlyReservedETH).add(pendingETH).sub(projectWithdrawnETH),
            'Project sanity check failed! balance = Unlock + Reserved - Withdrawn'
        );
    }

    /**
    * @notice Checks the projects core variables and ETH amounts in the contract for correctness.
    */
    function sanityCheckParticipant(address _participantAddress) internal view {
        Participant storage participantStats = participants[_participantAddress];

        //        DEBUG1 = participantStats.reservedTokens;
        //        DEBUG2 = participantStats._currentReservedTokens.add(participantStats._unlockedTokens);

        // PARTICIPANT: The sum of reserved + unlocked has to be equal the totalReserved.
        require(
            participantStats.reservedTokens == participantStats._currentReservedTokens.add(participantStats._unlockedTokens),
            'Participant Sanity check failed! Reser. + Unlock must equal totalReser'
        );
    }

    /**
     * @notice Calculates the projects allocation since the last calculation.
     */
    function calcProjectAllocation() internal {

        uint256 newlyUnlockedEth = calcUnlockedAmount(_projectCurrentlyReservedETH, _projectLastBlock);

        // UPDATE GLOBAL STATS
        _projectCurrentlyReservedETH = _projectCurrentlyReservedETH.sub(newlyUnlockedEth);
        _projectUnlockedETH = _projectUnlockedETH.add(newlyUnlockedEth);
        _projectLastBlock = getCurrentBlockNumber();

        sanityCheckProject();
    }

    /**
     * @notice Calculates the participants allocation since the last calculation.
     */
    function calcParticipantAllocation(address _participantAddress) internal {
        Participant storage participantStats = participants[_participantAddress];

        // UPDATE the locked/unlocked ratio for this participant
        participantStats._unlockedTokens = getParticipantUnlockedTokens(_participantAddress);
        participantStats._currentReservedTokens = getParticipantReservedTokens(_participantAddress);

        // RESET BLOCK NUMBER: Force the unlock calculations to start from this point in time.
        participantStats._lastBlock = getCurrentBlockNumber();

        // UPDATE the locked/unlocked ratio for the project as well
        calcProjectAllocation();
    }

    /**
     * @notice Cancels any participant's pending ETH contributions.
     * Pending is any ETH from participants that are not whitelisted yet.
     */
    function cancelPendingContributions(address _participantAddress, uint256 _sentValue)
    internal
    isInitialized
    isNotFrozen
    {
        Participant storage participantStats = participants[_participantAddress];
        uint256 participantPendingEth = participantStats.pendingETH;

        // Fail silently if no ETH are pending
        if(participantPendingEth == 0) {
            // sent at least back what he contributed
            if(_sentValue > 0) {
                address(uint160(_participantAddress)).transfer(_sentValue);
            }
            return;
        }

        // UPDATE PARTICIPANT STAGES
        for (uint8 stageId = 0; stageId <= getCurrentStage(); stageId++) {
            ParticipantStageDetails storage byStage = participantStats.stages[stageId];
            byStage.pendingETH = 0;
        }

        // UPDATE PARTICIPANT STATS
        participantStats.pendingETH = 0;

        // UPDATE GLOBAL STATS
        canceledETH = canceledETH.add(participantPendingEth);
        pendingETH = pendingETH.sub(participantPendingEth);

        // event emission
        emit TransferEvent(
            uint8(TransferTypes.CONTRIBUTION_CANCELED),
            _participantAddress,
            participantPendingEth
        );
        emit ApplicationEvent(
            uint8(ApplicationEventTypes.CONTRIBUTION_CANCELED),
            uint32(participantStats.contributions),
            _participantAddress,
            participantPendingEth
        );

        // transfer ETH back to participant including received value
        address(uint160(_participantAddress)).transfer(participantPendingEth.add(_sentValue));

        // SANITY check
        sanityCheckParticipant(_participantAddress);
        sanityCheckProject();
    }


    /**
    * @notice Accept a participant's contribution.
    * @param _participantAddress Participant's address.
    */
    function acceptContributions(address _participantAddress)
    internal
    isInitialized
    isNotFrozen
    isRunning
    {
        Participant storage participantStats = participants[_participantAddress];

        // Fail silently if no ETH are pending
        if (participantStats.pendingETH == 0) {
            return;
        }

        uint8 currentStage = getCurrentStage();
        uint256 totalRefundedETH;
        uint256 totalNewReservedTokens;

        calcParticipantAllocation(_participantAddress);

        // Iterate over all stages and their pending contributions
        for (uint8 stageId = 0; stageId <= currentStage; stageId++) {
            ParticipantStageDetails storage stages = participantStats.stages[stageId];

            // skip if not ETH is pending
            if (stages.pendingETH == 0) {
                continue;
            }

            uint256 maxCommittableEth = committableEthAtStage(stageId);
            uint256 newlyCommittedEth = stages.pendingETH;
            uint256 returnEth = 0;

            // If incoming value is higher than what we can accept,
            // just accept the difference and return the rest
            if (newlyCommittedEth > maxCommittableEth) {
                returnEth = newlyCommittedEth.sub(maxCommittableEth);
                newlyCommittedEth = maxCommittableEth;

                totalRefundedETH = totalRefundedETH.add(returnEth);
            }

            // convert ETH to TOKENS
            uint256 newTokenAmount = getTokenAmountForEthAtStage(
                newlyCommittedEth, stageId
            );

            totalNewReservedTokens = totalNewReservedTokens.add(newTokenAmount);

            // UPDATE PARTICIPANT STATS
            participantStats._currentReservedTokens = participantStats._currentReservedTokens.add(newTokenAmount);
            participantStats.reservedTokens = participantStats.reservedTokens.add(newTokenAmount);
            participantStats.committedETH = participantStats.committedETH.add(newlyCommittedEth);
            participantStats.pendingETH = participantStats.pendingETH.sub(newlyCommittedEth).sub(returnEth);

            stages.pendingETH = stages.pendingETH.sub(newlyCommittedEth).sub(returnEth);

            // UPDATE GLOBAL STATS
            tokenSupply = tokenSupply.sub(newTokenAmount);
            pendingETH = pendingETH.sub(newlyCommittedEth).sub(returnEth);
            committedETH = committedETH.add(newlyCommittedEth);
            _projectCurrentlyReservedETH = _projectCurrentlyReservedETH.add(newlyCommittedEth);

            // Emit event
            emit ApplicationEvent(uint8(ApplicationEventTypes.CONTRIBUTION_ACCEPTED), uint32(stageId), _participantAddress, newlyCommittedEth);
        }

        // Refund what couldn't be accepted
        if (totalRefundedETH > 0) {
            emit TransferEvent(uint8(TransferTypes.CONTRIBUTION_ACCEPTED_OVERFLOW), _participantAddress, totalRefundedETH);
            address(uint160(_participantAddress)).transfer(totalRefundedETH);
        }

        // Transfer tokens to the participant
        // solium-disable-next-line security/no-send
        IERC777(tokenAddress).send(_participantAddress, totalNewReservedTokens, "");

        // SANITY CHECK
        sanityCheckParticipant(_participantAddress);
        sanityCheckProject();
    }


    /**
     * @notice Allow a participant to withdraw by sending tokens back to rICO contract.
     * @param _participantAddress participant address.
     * @param _returnedTokenAmount The amount of tokens returned.
     */
    function withdraw(address _participantAddress, uint256 _returnedTokenAmount)
    internal
    isInitialized
    isNotFrozen
    isRunning
    {

        Participant storage participantStats = participants[_participantAddress];

        require(_returnedTokenAmount > 0, 'You can not withdraw without tokens.');
        require(participantStats._currentReservedTokens > 0 && participantStats.reservedTokens > 0, 'You can not withdraw, you have no locked tokens.');

        uint256 returnedTokenAmount = _returnedTokenAmount;
        uint256 overflowingTokenAmount;
        uint256 returnEthAmount;

        calcParticipantAllocation(_participantAddress);

        // Only allow reserved tokens be returned, return the overflow.
        if (returnedTokenAmount > participantStats._currentReservedTokens) {
            overflowingTokenAmount = returnedTokenAmount.sub(participantStats._currentReservedTokens);
            returnedTokenAmount = participantStats._currentReservedTokens;
        }

        // For STAGE 0, give back the price they put in
        if(getCurrentStage() == 0) {

            returnEthAmount = getEthAmountForTokensAtStage(returnedTokenAmount, 0);

        // For any other stage, calculate the avg price of all contributions
        } else {
            returnEthAmount = participantStats.committedETH.mul(
                returnedTokenAmount.mul(10 ** 20)
                .div(participantStats.reservedTokens)
            ).div(10 ** 20);
        }


        // UPDATE PARTICIPANT STATS
        participantStats.withdraws++;
        participantStats._currentReservedTokens = participantStats._currentReservedTokens.sub(returnedTokenAmount);
        participantStats.reservedTokens = participantStats.reservedTokens.sub(returnedTokenAmount);
        participantStats.committedETH = participantStats.committedETH.sub(returnEthAmount);

        // UPDATE global STATS
        tokenSupply = tokenSupply.add(returnedTokenAmount);
        withdrawnETH = withdrawnETH.add(returnEthAmount);
        committedETH = committedETH.sub(returnEthAmount);

        _projectCurrentlyReservedETH = _projectCurrentlyReservedETH.sub(returnEthAmount);


        // Return overflowing tokens received
        if (overflowingTokenAmount > 0) {
            // send tokens back to participant
            bytes memory data;

            emit TransferEvent(uint8(TransferTypes.PARTICIPANT_WITHDRAW_OVERFLOW), _participantAddress, overflowingTokenAmount);
            // solium-disable-next-line security/no-send
            IERC777(tokenAddress).send(_participantAddress, overflowingTokenAmount, data);
        }

        emit TransferEvent(uint8(TransferTypes.PARTICIPANT_WITHDRAW), _participantAddress, returnEthAmount);

        // Return ETH back to participant
        address(uint160(_participantAddress)).transfer(returnEthAmount);

        // SANITY CHECK
        sanityCheckParticipant(_participantAddress);
        sanityCheckProject();
    }

    /*
     *   Modifiers
     */

    /**
     * @notice Checks if the sender is the project.
     */
    modifier onlyProjectAddress() {
        require(msg.sender == projectAddress, "Only the project can call this method.");
        _;
    }

    /**
     * @notice Checks if the sender is the deployer.
     */
    modifier onlyDeployingAddress() {
        require(msg.sender == deployingAddress, "Only the deployer can call this method.");
        _;
    }

    /**
     * @notice Checks if the sender is the whitelist controller.
     */
    modifier onlyWhitelistingAddress() {
        require(msg.sender == whitelistingAddress, "Only the whitelist controller can call this method.");
        _;
    }

    /**
     * @notice Checks if the sender is the freezer controller address.
     */
    modifier onlyFreezerAddress() {
        require(msg.sender == freezerAddress, "Only the freezer address can call this method.");
        _;
    }

    /**
     * @notice Checks if the sender is the freezer controller address.
     */
    modifier onlyRescuerAddress() {
        require(msg.sender == rescuerAddress, "Only the rescuer address can call this method.");
        _;
    }

    /**
     * @notice Requires the contract to have been initialized.
     */
    modifier isInitialized() {
        require(initialized == true, "Contract must be initialized.");
        _;
    }

    /**
     * @notice Requires the contract to NOT have been initialized,
     */
    modifier isNotInitialized() {
        require(initialized == false, "Contract can not be initialized.");
        _;
    }

    /**
     * @notice @dev Requires the contract to be frozen.
     */
    modifier isFrozen() {
        require(frozen == true, "rICO has to be frozen!");
        _;
    }

    /**
     * @notice @dev Requires the contract not to be frozen.
     */
    modifier isNotFrozen() {
        require(frozen == false, "rICO is frozen!");
        _;
    }

    /**
     * @notice Checks if the rICO is running.
     */
    modifier isRunning() {
        uint256 blockNumber = getCurrentBlockNumber();
        require(blockNumber >= commitPhaseStartBlock && blockNumber <= buyPhaseEndBlock, "Current block is outside the rICO period.");
        _;
    }
}