pragma solidity 0.6.12;

import "@openzeppelin/contracts/GSN/Context.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/IERC20Burnable.sol";

contract Transmuter is Context {
    using SafeMath for uint256;
    using SafeERC20 for IERC20Burnable;
    using Address for address;

    address public constant ZERO_ADDRESS = address(0);
    uint256 public TRANSMUTATION_PERIOD;

    address public NToken;
    address public Token;

    mapping(address => uint256) public depositedNTokens;
    mapping(address => uint256) public tokensInBucket;
    mapping(address => uint256) public realisedTokens;
    mapping(address => uint256) public lastDividendPoints;

    mapping(address => bool) public userIsKnown;
    mapping(uint256 => address) public userList;
    uint256 public nextUser;

    uint256 public totalSupplyNtokens;
    uint256 public buffer;
    uint256 public lastDepositBlock;

    ///@dev values needed to calculate the distribution of base asset in proportion for nTokens staked
    uint256 public pointMultiplier = 10e18;

    uint256 public totalDividendPoints;
    uint256 public unclaimedDividends;

    uint256 public USDT_CONST;

    /// @dev formation addresses whitelisted
    mapping(address => bool) public whiteList;

    /// @dev The address of the account which currently has administrative capabilities over this contract.
    address public governance;

    /// @dev The address of the pending governance.
    address public pendingGovernance;

    event GovernanceUpdated(address governance);

    event PendingGovernanceUpdated(address pendingGovernance);

    event TransmuterPeriodUpdated(uint256 newTransmutationPeriod);

    constructor(
        address _NToken,
        address _Token,
        address _governance
    ) public {
        require(_NToken != ZERO_ADDRESS, "Transmuter: NToken address cannot be 0x0");
        require(_Token != ZERO_ADDRESS, "Transmuter: Token address cannot be 0x0");
        require(_governance != ZERO_ADDRESS, "Transmuter: 0 gov");
        require(IERC20Burnable(_Token).decimals() <= IERC20Burnable(_NToken).decimals(), "Transmuter: xtoken decimals should be larger than token decimals");
        USDT_CONST = uint256(10)**(uint256(IERC20Burnable(_NToken).decimals()).sub(uint256(IERC20Burnable(_Token).decimals())));
        governance = _governance;
        NToken = _NToken;
        Token = _Token;

        TRANSMUTATION_PERIOD = 50;
    }

    ///@return displays the user's share of the pooled nTokens.
    function dividendsOwing(address account) public view returns (uint256) {
        uint256 newDividendPoints = totalDividendPoints.sub(lastDividendPoints[account]);
        return depositedNTokens[account].mul(newDividendPoints).div(pointMultiplier);
    }

    ///@dev modifier to fill the bucket and keep bookkeeping correct incase of increase/decrease in shares
    modifier updateAccount(address account) {
        uint256 owing = dividendsOwing(account);
        if (owing > 0) {
            unclaimedDividends = unclaimedDividends.sub(owing);
            tokensInBucket[account] = tokensInBucket[account].add(owing);
        }
        lastDividendPoints[account] = totalDividendPoints;
        _;
    }
    ///@dev modifier add users to userlist. Users are indexed in order to keep track of when a bond has been filled
    modifier checkIfNewUser() {
        if (!userIsKnown[msg.sender]) {
            userList[nextUser] = msg.sender;
            userIsKnown[msg.sender] = true;
            nextUser++;
        }
        _;
    }

    ///@dev run the phased distribution of the buffered funds
    modifier runPhasedDistribution() {
        uint256 _lastDepositBlock = lastDepositBlock;
        uint256 _currentBlock = block.number;
        uint256 _toDistribute = 0;
        uint256 _buffer = buffer;

        // check if there is something in bufffer
        if (_buffer > 0) {
            // NOTE: if last deposit was updated in the same block as the current call
            // then the below logic gates will fail

            //calculate diffrence in time
            uint256 deltaTime = _currentBlock.sub(_lastDepositBlock);

            // distribute all if bigger than timeframe
            if (deltaTime >= TRANSMUTATION_PERIOD) {
                _toDistribute = _buffer;
            } else {
                //needs to be bigger than 0 cuzz solidity no decimals
                if (_buffer.mul(deltaTime) > TRANSMUTATION_PERIOD) {
                    _toDistribute = _buffer.mul(deltaTime).div(TRANSMUTATION_PERIOD);
                }
            }

            // factually allocate if any needs distribution
            if (_toDistribute > 0) {
                // remove from buffer
                buffer = _buffer.sub(_toDistribute);

                // increase the allocation
                increaseAllocations(_toDistribute);
            }
        }

        // current timeframe is now the last
        lastDepositBlock = _currentBlock;
        _;
    }

    /// @dev A modifier which checks if whitelisted for minting.
    modifier onlyWhitelisted() {
        require(whiteList[msg.sender], "Transmuter: !whitelisted");
        _;
    }

    /// @dev Checks that the current message sender or caller is the governance address.
    ///
    ///
    modifier onlyGov() {
        require(msg.sender == governance, "Transmuter: !governance");
        _;
    }

    ///@dev set the TRANSMUTATION_PERIOD variable
    ///
    /// sets the length (in blocks) of one full distribution phase
    function setTransmutationPeriod(uint256 newTransmutationPeriod) public onlyGov {
        require(newTransmutationPeriod > 0, "Transmuter: transmutation period cannot be 0");
        TRANSMUTATION_PERIOD = newTransmutationPeriod;
        emit TransmuterPeriodUpdated(TRANSMUTATION_PERIOD);
    }

    ///@dev claims the base token after it has been transmuted
    ///
    ///This function reverts if there is no realisedToken balance
    function claim() public {
        address sender = msg.sender;
        require(realisedTokens[sender] > 0);
        uint256 value = realisedTokens[sender];
        realisedTokens[sender] = 0;
        IERC20Burnable(Token).safeTransfer(sender, value);
    }

    ///@dev Withdraws staked nTokens from the transmuter
    ///
    /// This function reverts if you try to draw more tokens than you deposited
    ///
    ///@param amount the amount of nTokens to unstake
    function unstake(uint256 amount) public updateAccount(msg.sender) {
        // by calling this function before transmuting you forfeit your gained allocation
        address sender = msg.sender;

        // normalize amount to fit the digit of token
        amount = amount.div(USDT_CONST).mul(USDT_CONST);

        require(depositedNTokens[sender] >= amount, "Transmuter: unstake amount exceeds deposited amount");
        depositedNTokens[sender] = depositedNTokens[sender].sub(amount);
        totalSupplyNtokens = totalSupplyNtokens.sub(amount);
        IERC20Burnable(NToken).safeTransfer(sender, amount);
    }

    ///@dev Deposits nTokens into the transmuter
    ///
    ///@param amount the amount of nTokens to stake
    function stake(uint256 amount) public runPhasedDistribution updateAccount(msg.sender) checkIfNewUser {
        // requires approval of NToken first
        address sender = msg.sender;

        // normalize amount to fit the digit of token
        amount = amount.div(USDT_CONST).mul(USDT_CONST);

        //require tokens transferred in;
        IERC20Burnable(NToken).safeTransferFrom(sender, address(this), amount);
        totalSupplyNtokens = totalSupplyNtokens.add(amount);
        depositedNTokens[sender] = depositedNTokens[sender].add(amount);
    }

    /// @dev Converts the staked nTokens to the base tokens in amount of the sum of pendingdivs and tokensInBucket
    ///
    /// once the NToken has been converted, it is burned, and the base token becomes realisedTokens which can be recieved using claim()
    ///
    /// reverts if there are no pendingdivs or tokensInBucket
    function transmute() public runPhasedDistribution updateAccount(msg.sender) {
        address sender = msg.sender;
        uint256 pendingz_USDT;
        uint256 pendingz = tokensInBucket[sender];
        uint256 diff;

        require(pendingz > 0, "need to have pending in bucket");

        tokensInBucket[sender] = 0;

        // check bucket overflow
        if (pendingz.mul(USDT_CONST) > depositedNTokens[sender]) {
            diff = pendingz.mul(USDT_CONST).sub(depositedNTokens[sender]);

            // remove overflow
            pendingz = depositedNTokens[sender].div(USDT_CONST);
        }

        pendingz_USDT = pendingz.mul(USDT_CONST);
        // decrease ntokens
        depositedNTokens[sender] = depositedNTokens[sender].sub(pendingz_USDT);

        // BURN ntokens
        IERC20Burnable(NToken).burn(pendingz_USDT);

        // adjust total
        totalSupplyNtokens = totalSupplyNtokens.sub(pendingz_USDT);

        // reallocate overflow
        increaseAllocations(diff.div(USDT_CONST));

        // add payout
        realisedTokens[sender] = realisedTokens[sender].add(pendingz);
    }

    /// @dev Executes transmute() on another account that has had more base tokens allocated to it than nTokens staked.
    ///
    /// The caller of this function will have the surlus base tokens credited to their tokensInBucket balance, rewarding them for performing this action
    ///
    /// This function reverts if the address to transmute is not over-filled.
    ///
    /// @param toTransmute address of the account you will force transmute.
    function forceTransmute(address toTransmute) public runPhasedDistribution updateAccount(msg.sender) updateAccount(toTransmute) checkIfNewUser {
        //load into memory
        uint256 pendingz_USDT;
        uint256 pendingz = tokensInBucket[toTransmute];

        // check restrictions
        require(pendingz.mul(USDT_CONST) > depositedNTokens[toTransmute], "Transmuter: !overflow");

        // empty bucket
        tokensInBucket[toTransmute] = 0;

        // calculaate diffrence
        uint256 diff = pendingz.mul(USDT_CONST).sub(depositedNTokens[toTransmute]);
        // remove overflow
        pendingz = depositedNTokens[toTransmute].div(USDT_CONST);
        pendingz_USDT = pendingz.mul(USDT_CONST);
        // decrease ntokens
        depositedNTokens[toTransmute] = depositedNTokens[toTransmute].sub(pendingz_USDT);

        // BURN ntokens
        IERC20Burnable(NToken).burn(pendingz_USDT);

        // adjust total
        totalSupplyNtokens = totalSupplyNtokens.sub(pendingz_USDT);

        // reallocate overflow
        tokensInBucket[msg.sender] = tokensInBucket[msg.sender].add(diff.div(USDT_CONST));

        // add payout
        realisedTokens[toTransmute] = realisedTokens[toTransmute].add(pendingz);

        // force payout of realised tokens of the toTransmute address
        if (realisedTokens[toTransmute] > 0) {
            uint256 value = realisedTokens[toTransmute];
            realisedTokens[toTransmute] = 0;
            IERC20Burnable(Token).safeTransfer(toTransmute, value);
        }
    }

    /// @dev Transmutes and unstakes all nTokens
    ///
    /// This function combines the transmute and unstake functions for ease of use
    function exit() public {
        transmute();
        uint256 toWithdraw = depositedNTokens[msg.sender];
        unstake(toWithdraw);
    }

    /// @dev Transmutes and claims all converted base tokens.
    ///
    /// This function combines the transmute and claim functions while leaving your remaining nTokens staked.
    function transmuteAndClaim() public {
        transmute();
        claim();
    }

    /// @dev Transmutes, claims base tokens, and withdraws nTokens.
    ///
    /// This function helps users to exit the transmuter contract completely after converting their nTokens to the base pair.
    function transmuteClaimAndWithdraw() public {
        transmute();
        claim();
        uint256 toWithdraw = depositedNTokens[msg.sender];
        unstake(toWithdraw);
    }

    /// @dev Distributes the base token proportionally to all NToken stakers.
    ///
    /// This function is meant to be called by the Formation contract for when it is sending yield to the transmuter.
    /// Anyone can call this and add funds, idk why they would do that though...
    ///
    /// @param origin the account that is sending the tokens to be distributed.
    /// @param amount the amount of base tokens to be distributed to the transmuter.
    function distribute(address origin, uint256 amount) public onlyWhitelisted runPhasedDistribution {
        IERC20Burnable(Token).safeTransferFrom(origin, address(this), amount);
        buffer = buffer.add(amount);
    }

    /// @dev Allocates the incoming yield proportionally to all NToken stakers.
    ///
    /// @param amount the amount of base tokens to be distributed in the transmuter.
    function increaseAllocations(uint256 amount) internal {
        if (totalSupplyNtokens > 0 && amount > 0) {
            totalDividendPoints = totalDividendPoints.add(amount.mul(pointMultiplier).div(totalSupplyNtokens));
            unclaimedDividends = unclaimedDividends.add(amount);
        } else {
            buffer = buffer.add(amount);
        }
    }

    /// @dev Gets the status of a user's staking position.
    ///
    /// The total amount allocated to a user is the sum of pendingdivs and inbucket.
    ///
    /// @param user the address of the user you wish to query.
    ///
    /// returns user status

    function userInfo(address user)
        public
        view
        returns (
            uint256 depositedAl,
            uint256 pendingdivs,
            uint256 inbucket,
            uint256 realised
        )
    {
        uint256 _depositedN = depositedNTokens[user];
        uint256 _toDistribute = buffer.mul(block.number.sub(lastDepositBlock)).div(TRANSMUTATION_PERIOD);
        if (block.number.sub(lastDepositBlock) > TRANSMUTATION_PERIOD) {
            _toDistribute = buffer;
        }
        uint256 _pendingdivs = _toDistribute.mul(depositedNTokens[user]).div(totalSupplyNtokens);
        uint256 _inbucket = tokensInBucket[user].add(dividendsOwing(user));
        uint256 _realised = realisedTokens[user];
        return (_depositedN, _pendingdivs, _inbucket, _realised);
    }

    /// @dev Gets the status of multiple users in one call
    ///
    /// This function is used to query the contract to check for
    /// accounts that have overfilled positions in order to check
    /// who can be force transmuted.
    ///
    /// @param from the first index of the userList
    /// @param to the last index of the userList
    ///
    /// returns the userList with their staking status in paginated form.
    function getMultipleUserInfo(uint256 from, uint256 to) public view returns (address[] memory theUserList, uint256[] memory theUserData) {
        uint256 i = from;
        uint256 delta = to - from;
        address[] memory _theUserList = new address[](delta); //user
        uint256[] memory _theUserData = new uint256[](delta * 2); //deposited-bucket
        uint256 y = 0;
        uint256 _toDistribute = buffer.mul(block.number.sub(lastDepositBlock)).div(TRANSMUTATION_PERIOD);
        if (block.number.sub(lastDepositBlock) > TRANSMUTATION_PERIOD) {
            _toDistribute = buffer;
        }
        for (uint256 x = 0; x < delta; x += 1) {
            _theUserList[x] = userList[i];
            _theUserData[y] = depositedNTokens[userList[i]];
            _theUserData[y + 1] = dividendsOwing(userList[i]).add(tokensInBucket[userList[i]]).add(_toDistribute.mul(depositedNTokens[userList[i]]).div(totalSupplyNtokens));
            y += 2;
            i += 1;
        }
        return (_theUserList, _theUserData);
    }

    /// @dev Gets info on the buffer
    ///
    /// This function is used to query the contract to get the
    /// latest state of the buffer
    ///
    /// @return _toDistribute the amount ready to be distributed
    /// @return _deltaBlocks the amount of time since the last phased distribution
    /// @return _buffer the amount in the buffer
    function bufferInfo()
        public
        view
        returns (
            uint256 _toDistribute,
            uint256 _deltaBlocks,
            uint256 _buffer
        )
    {
        _deltaBlocks = block.number.sub(lastDepositBlock);
        _buffer = buffer;
        _toDistribute = _buffer.mul(_deltaBlocks).div(TRANSMUTATION_PERIOD);
    }

    /// @dev Sets the pending governance.
    ///
    /// This function reverts if the new pending governance is the zero address or the caller is not the current
    /// governance. This is to prevent the contract governance being set to the zero address which would deadlock
    /// privileged contract functionality.
    ///
    /// @param _pendingGovernance the new pending governance.
    function setPendingGovernance(address _pendingGovernance) external onlyGov {
        require(_pendingGovernance != ZERO_ADDRESS, "Transmuter: 0 gov");

        pendingGovernance = _pendingGovernance;

        emit PendingGovernanceUpdated(_pendingGovernance);
    }

    /// @dev Accepts the role as governance.
    ///
    /// This function reverts if the caller is not the new pending governance.
    function acceptGovernance() external {
        require(msg.sender == pendingGovernance, "!pendingGovernance");

        governance = pendingGovernance;

        emit GovernanceUpdated(pendingGovernance);
    }

    /// This function reverts if the caller is not governance
    ///
    /// @param _toWhitelist the account to mint tokens to.
    /// @param _state the whitelist state.

    function setWhitelist(address _toWhitelist, bool _state) external onlyGov {
        whiteList[_toWhitelist] = _state;
    }
}
