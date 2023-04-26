// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.0;


import {SafeMath} from "../dependencies/openzeppelin/math/SafeMath.sol";
import {Address} from "../dependencies/openzeppelin/utils/Address.sol";
import {ERC20} from "../dependencies/openzeppelin/token/ERC20/ERC20.sol";
import {IGlobalAddressesProvider} from "../../interfaces/GlobalAddressesProvider/IGlobalAddressesProvider.sol";

contract SIGH is ERC20('SIGH: Simulated yield optimizer','SIGH') {

    using SafeMath for uint256;    // Time based calculations
    using Address for address;

    string _name_ = 'SIGH: Simulated yield optimizer';
    string _symbol_ = 'SIGH';
    address public _deployer;
    address public SpeedController;
    IGlobalAddressesProvider private globalAddressesProvider;

    mapping(address => bool) private blockList;

    uint256 private constant INITIAL_SUPPLY = 5 * 10**5 * 10**18; // 5 Million (with 18 decimals)
    uint256 private prize_amount = 500 * 10**18;

    uint256 private totalAmountBurnt;

    struct mintSnapshot {
        uint cycle;
        uint schedule;
        uint inflationRate;
        uint mintedAmount;
        uint mintSpeed;
        uint newTotalSupply;
        address minter;
        uint blockNumber;
    }

    mintSnapshot[] private mintSnapshots;

    uint256 public CYCLE_BLOCKS = 6500;  // 15 * 60 * 24 (KOVAN blocks minted per day)
    uint256 public constant FINAL_CYCLE = 1560; //

    uint256 private Current_Cycle;
    uint256 private Current_Schedule;
    uint256 private currentDivisibilityFactor = 100;

    bool private mintingActivated = false;
    uint256 private previousMintBlock;

    struct Schedule {
        uint256 startCycle;
        uint256 endCycle;
        uint256 divisibilityFactor;
    }

    Schedule[5] private _schedules;

    /// @notice A record of each accounts delegate
    mapping (address => address) public delegates;

    /// @notice A checkpoint for marking number of votes from a given block
    struct Checkpoint {
        uint32 fromBlock;
        uint96 votes;
    }

    /// @notice A record of votes checkpoints for each account, by index
    mapping (address => mapping (uint32 => Checkpoint)) public checkpoints;

    /// @notice The number of checkpoints for each account
    mapping (address => uint32) public numCheckpoints;

    /// @notice The EIP-712 type-hash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @notice The EIP-712 type-hash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH = keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    /// @notice A record of states for signing / validating signatures
    mapping (address => uint) public nonces;

    modifier onlySIGHFinanceManager {
        address sighFinanceManager =  globalAddressesProvider.getSIGHFinanceManager();
        require( sighFinanceManager == msg.sender, "The caller must be the SIGH FINANCE Manager" );
        _;
    }

    event MintingInitialized(address speedController);
    event NewSchedule(uint newSchedule, uint newDivisibilityFactor, uint timeStamp );
    event SIGHMinted( address minter, uint256 cycle, uint256 Schedule, uint inflationRate, uint256 amountMinted, uint mintSpeed, uint256 current_supply);

    /// @notice An event that's emitted when an account changes its delegate
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);

    /// @notice An event that's emitted when a delegate account's vote balance changes
    event DelegateVotesChanged(address indexed delegate, uint previousBalance, uint newBalance);

    event SIGHBurned( uint256 burntAmount, uint256 totalBurnedAmount, uint256 currentSupply);

    event accountBlocked(address _account, uint balance);
    event accountUnBlocked(address _account, uint balance);

    // constructing
    constructor () {
        _deployer = _msgSender();
    }

    // ################################################
    // #######   FUNCTIONS TO INITIATE MINTING  #######
    // ################################################

    function initMinting(address _globalAddressesProvider, address newSpeedController) public returns (bool) {
        require(_msgSender() == _deployer,"Mining can only be initialized by the Deployer." );
        require(newSpeedController != address(0), "Not a valid Speed Controller address");
        require(!mintingActivated, "Minting can only be initialized once" );

        SpeedController = newSpeedController;
        globalAddressesProvider = IGlobalAddressesProvider(_globalAddressesProvider);
        _initSchedules();
        mintingActivated = true;
        _mint(SpeedController,INITIAL_SUPPLY);
         _moveDelegates(delegates[address(0)], delegates[SpeedController], safe96(INITIAL_SUPPLY,'safe96: Overflow'));

        mintSnapshot  memory currentMintSnapshot = mintSnapshot({ cycle:Current_Cycle, schedule:Current_Schedule, inflationRate: uint(0), mintedAmount:INITIAL_SUPPLY, mintSpeed:uint(0), newTotalSupply:totalSupply(), minter: msg.sender, blockNumber: block.number });
        mintSnapshots.push(currentMintSnapshot);                                                    // MINT SNAPSHOT ADDED TO THE ARRAY

        emit MintingInitialized(SpeedController);
        emit SIGHMinted(currentMintSnapshot.minter, currentMintSnapshot.cycle, currentMintSnapshot.schedule, currentMintSnapshot.inflationRate, currentMintSnapshot.mintedAmount, currentMintSnapshot.mintSpeed, currentMintSnapshot.newTotalSupply);

        _deployer = address(0);

        return true;
    }

    function _initSchedules() private {
        _schedules[0] = Schedule(1, 96, 100 );              // Genesis Mint Schedule
        _schedules[1] = Schedule(97, 462, 200 );            // 1st Mint Schedule
        _schedules[2] = Schedule(463, 828, 400 );           // 2nd Mint Schedule
        _schedules[3] = Schedule(829, 1194, 800 );          // 3rd Mint Schedule
        _schedules[4] = Schedule(1195, 1560, 1600 );        // 4th Mint Schedule
    }

    function blockAnAccount(address _account) external onlySIGHFinanceManager returns (bool) {
        uint balance = balanceOf(_account);
        require(balance > 0,'Invalid balance');
        require( !blockList[_account],'Already Blocked');
        blockList[_account] = true;
        emit accountBlocked(_account, balance );
        return true;
    }

    function unBlockAnAccount(address _account) external onlySIGHFinanceManager returns (bool) {
        require( blockList[_account],'Account Not Blocked');
        blockList[_account] = false;
        emit accountUnBlocked(_account, balanceOf(_account) );
        return true;
    }

    function update(uint deltaBlocks) external onlySIGHFinanceManager returns (bool) {
        CYCLE_BLOCKS = deltaBlocks;
        return true;
    }

    // ############################################################
    // ############   OVER-LOADING TRANSFER FUNCTON    ############
    // ############################################################

    function _transfer(address sender, address recipient, uint256 amount) override internal {
        require(!blockList[sender],'Caller address freezed. SIGH cannot be moved from this account');
        require(!blockList[recipient],'Recepient address freezed. No new SIGH can be deposited to this account');
        if (isMintingPossible()) {
             mintNewCoins();
        }
        super._transfer(sender, recipient, amount);
        _moveDelegates(delegates[sender], delegates[recipient], safe96(amount,'safe96: Overflow'));
    }

    // ################################################
    // ############   MINT FUNCTONS    ############
    // ################################################

    function isMintingPossible() internal returns (bool) {
        if ( mintingActivated && Current_Cycle <= FINAL_CYCLE && _getElapsedBlocks(block.number, previousMintBlock) > CYCLE_BLOCKS ) {
            Current_Cycle = Current_Cycle.add(1);
            return true;
        }
        return false;
    }

    function mintCoins() external returns (bool) {
        if (isMintingPossible() ) {
            mintNewCoins();
            return true;
        }
        return false;
    }

    function mintNewCoins() internal returns (bool) {

        if ( Current_Schedule < _CalculateCurrentSchedule() ) {
            Current_Schedule = Current_Schedule.add(1);
            currentDivisibilityFactor = _schedules[Current_Schedule].divisibilityFactor;
            emit NewSchedule(Current_Schedule,currentDivisibilityFactor, block.timestamp);
        }

        uint currentSupply = totalSupply();
        uint256 newCoins = currentSupply.div(currentDivisibilityFactor);                        // Calculate the number of new tokens to be minted.
        uint newmintSpeed = newCoins.div(CYCLE_BLOCKS);                                         // mint speed, i.e tokens minted per block rate for this cycle
        if (newCoins > prize_amount) {
            newCoins = newCoins.sub(prize_amount);
        }
        else {
            prize_amount = uint(0);
        }

        _mint( msg.sender, prize_amount );                                                          // PRIZE AMOUNT AWARDED TO THE MINTER
        _moveDelegates(delegates[address(0)],delegates[msg.sender], safe96(prize_amount,'safe96: Overflow'));

        _mint( SpeedController, newCoins );                                                          // NEWLY MINTED SIGH TRANSFERRED TO SIGH SPEED CONTROLLER
        _moveDelegates(delegates[address(0)], delegates[SpeedController], safe96(newCoins,'safe96: Overflow'));


        mintSnapshot  memory currentMintSnapshot = mintSnapshot({ cycle:Current_Cycle, schedule:Current_Schedule, inflationRate: currentDivisibilityFactor, mintedAmount:newCoins, mintSpeed:newmintSpeed, newTotalSupply:totalSupply(), minter: msg.sender, blockNumber: block.number });
        mintSnapshots.push(currentMintSnapshot);                                                    // MINT SNAPSHOT ADDED TO THE ARRAY
        previousMintBlock = block.number;

        emit SIGHMinted(currentMintSnapshot.minter, currentMintSnapshot.cycle, currentMintSnapshot.schedule, currentMintSnapshot.inflationRate, newCoins.add(prize_amount), currentMintSnapshot.mintSpeed, currentMintSnapshot.newTotalSupply);
        return true;
    }

    function _getElapsedBlocks(uint256 currentBlock , uint256 prevBlock) internal pure returns(uint256) {
        uint deltaBlocks = currentBlock.sub(prevBlock);
        return deltaBlocks;
    }

    function _CalculateCurrentSchedule() internal view returns (uint256) {

        if (Current_Cycle <= 96) {
            return uint256(0);
        }

        uint256 C_Schedule_sub = Current_Cycle.sub(96);
        uint256 _newSchedule = C_Schedule_sub.div(365);

        if (_newSchedule < 4 ) {
            return uint256(_newSchedule.add(1) );
        }

        return uint256(5);
    }

    // ################################################
    // ############   BURN FUNCTION    #################
    // ################################################

    function burn(uint amount) external returns (bool) {
        _burn(msg.sender, amount);
        totalAmountBurnt = totalAmountBurnt.add(amount);
        emit SIGHBurned( amount, totalAmountBurnt, totalSupply() );
        _moveDelegates(delegates[msg.sender], delegates[address(0)], safe96(amount,'safe96: Overflow'));

        return true;
    }

    // ##############################################################
    // ############   VOTING DELEGATION FUNCTION    #################
    // ##############################################################

    /**
     * @notice Delegate votes from `msg.sender` to `delegatee`
     * @param delegatee The address to delegate votes to
     */
    function delegate(address delegatee) public {
        return _delegate(msg.sender, delegatee);
    }

    /**
     * @notice Delegates votes from signatory to `delegatee`
     * @param delegatee The address to delegate votes to
     * @param nonce The contract state required to match the signature
     * @param expiry The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function delegateBySig(address delegatee, uint nonce, uint expiry, uint8 v, bytes32 r, bytes32 s) public {
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(_name_)), getChainId(), address(this)));
        bytes32 structHash = keccak256(abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "SIGH::delegateBySig: invalid signature");
        require(nonce == nonces[signatory]++, "SIGH::delegateBySig: invalid nonce");
        require(block.timestamp <= expiry, "SIGH::delegateBySig: signature expired");
        return _delegate(signatory, delegatee);
    }

    function _delegate(address delegator, address delegatee) internal {
        require(balanceOf(delegator) > 0,'Invalid Delegator balance');
        address currentDelegate = delegates[delegator];
        uint96 delegatorBalance = safe96(balanceOf(delegator),'Balance exceeds max uint96');
        delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);
        _moveDelegates(currentDelegate, delegatee, delegatorBalance);
    }

    function _moveDelegates(address srcRep, address dstRep, uint96 amount) internal {
        if (srcRep != dstRep && amount > 0) {
            if (srcRep != address(0)) {
                uint32 srcRepNum = numCheckpoints[srcRep];
                uint96 srcRepOld = srcRepNum > 0 ? checkpoints[srcRep][srcRepNum - 1].votes : 0;
                uint96 srcRepNew = sub96(srcRepOld, amount, "SIGH::_moveVotes: vote amount underflows");
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                uint32 dstRepNum = numCheckpoints[dstRep];
                uint96 dstRepOld = dstRepNum > 0 ? checkpoints[dstRep][dstRepNum - 1].votes : 0;
                uint96 dstRepNew = add96(dstRepOld, amount, "SIGH::_moveVotes: vote amount overflows");
                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }

    function _writeCheckpoint(address delegatee, uint32 nCheckpoints, uint96 oldVotes, uint96 newVotes) internal {
      uint32 blockNumber = safe32(block.number, "SIGH::_writeCheckpoint: block number exceeds 32 bits");

      if (nCheckpoints > 0 && checkpoints[delegatee][nCheckpoints - 1].fromBlock == blockNumber) {
          checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
      }
      else {
          checkpoints[delegatee][nCheckpoints] = Checkpoint(blockNumber, newVotes);
          numCheckpoints[delegatee] = nCheckpoints + 1;
      }

      emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }

    // ################################################
    // ###########   MINT FUNCTONS (VIEW)   ###########
    // ################################################

    function isMintingActivated() external view returns(bool) {
        if (Current_Cycle > FINAL_CYCLE) {
            return false;
        }
        return mintingActivated;
    }

   function getCurrentSchedule() public view returns (uint256) {
        return Current_Schedule;
    }

   function getCurrentCycle() public view returns (uint256) {
        return Current_Cycle;
    }

    function getCurrentInflationRate() external view returns (uint256) {
        if (Current_Cycle > FINAL_CYCLE || !mintingActivated) {
            return uint(0);
        }
        return currentDivisibilityFactor;
    }

    function getBlocksRemainingToMint() external view returns (uint) {

        if (Current_Cycle > FINAL_CYCLE || !mintingActivated) {
            return uint(-1);
        }

        uint deltaBlocks = _getElapsedBlocks(block.number, previousMintBlock);

        if (deltaBlocks >= CYCLE_BLOCKS ) {
            return uint(0);
        }
        return CYCLE_BLOCKS.sub(deltaBlocks);
    }


    function getMintSnapshotForCycle(uint cycleNumber) public view returns (uint schedule,uint inflationRate, uint mintedAmount,uint mintSpeed, uint newTotalSupply,address minter, uint blockNumber ) {
        return ( mintSnapshots[cycleNumber].schedule,
                 mintSnapshots[cycleNumber].inflationRate,
                 mintSnapshots[cycleNumber].mintedAmount,
                 mintSnapshots[cycleNumber].mintSpeed,
                 mintSnapshots[cycleNumber].newTotalSupply,
                 mintSnapshots[cycleNumber].minter,
                 mintSnapshots[cycleNumber].blockNumber
                 );
    }

    function getLatestMintSnapshot() public view returns (uint cycle, uint schedule,uint inflationRate, uint mintedAmount,uint mintSpeed, uint newTotalSupply,address minter, uint blockNumber ) {
        uint len = mintSnapshots.length;
        return ( len,
                 mintSnapshots[len - 1].schedule,
                 mintSnapshots[len - 1].inflationRate,
                 mintSnapshots[len - 1].mintedAmount,
                 mintSnapshots[len - 1].mintSpeed,
                 mintSnapshots[len - 1].newTotalSupply,
                 mintSnapshots[len - 1].minter,
                 mintSnapshots[len - 1].blockNumber
                 );
    }


    function getCurrentMintSpeed() external view returns (uint) {
        if (Current_Cycle > FINAL_CYCLE || !mintingActivated) {
            return uint(0);
        }
        uint currentSupply = totalSupply();
        uint256 newCoins = currentSupply.div(currentDivisibilityFactor);                        // Calculate the number of new tokens to be minted.
        uint newmintSpeed = newCoins.div(CYCLE_BLOCKS);                                         // mint speed, i.e tokens minted per block rate for this cycle
        return newmintSpeed;
    }

    function getTotalSighBurnt() external view returns (uint) {
        return totalAmountBurnt;
    }

   function getSpeedController() external view returns (address) {
        return SpeedController;
    }

    // ##################################################
    // ###########   VOTING FUNCTONS (VIEW)   ###########
    // ##################################################

    /**
     * @notice Gets the current votes balance for `account`
     * @param account The address to get votes balance
     * @return The number of current votes for `account`
     */
    function getCurrentVotes(address account) external view returns (uint96) {
        uint32 nCheckpoints = numCheckpoints[account];
        return nCheckpoints > 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;
    }

    /**
     * @notice Determine the prior number of votes for an account as of a block number
     * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
     * @param account The address of the account to check
     * @param blockNumber The block number to get the vote balance at
     * @return The number of votes the account had as of the given block
     */
    function getPriorVotes(address account, uint blockNumber) public view returns (uint96) {
        require(blockNumber < block.number, "SIGH::getPriorVotes: not yet determined");

        uint32 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }

        // Next check implicit zero balance
        if (checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint32 lower = 0;
        uint32 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint32 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return checkpoints[account][lower].votes;
    }


    // ###################################################################
    // ###########   Internal helper functions for safe math   ###########
    // ###################################################################

    function add96(uint96 a, uint96 b, string memory errorMessage) internal pure returns (uint96) {
        uint96 c = a + b;
        require(c >= a, errorMessage);
        return c;
    }

    function sub96(uint96 a, uint96 b, string memory errorMessage) internal pure returns (uint96) {
        require(b <= a, errorMessage);
        return a - b;
    }

    function safe32(uint n, string memory errorMessage) internal pure returns (uint32) {
        require(n < 2**32, errorMessage);
        return uint32(n);
    }

    function safe96(uint n, string memory errorMessage) internal pure returns (uint96) {
        require(n < 2**96, errorMessage);
        return uint96(n);
    }

    function getChainId() internal pure returns (uint) {
        uint256 chainId;
        assembly { chainId := chainid() }
        return chainId;
    }

}




