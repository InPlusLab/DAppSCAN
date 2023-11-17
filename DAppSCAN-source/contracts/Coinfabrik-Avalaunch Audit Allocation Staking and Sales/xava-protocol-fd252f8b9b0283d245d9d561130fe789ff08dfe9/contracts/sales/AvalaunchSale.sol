//"SPDX-License-Identifier: UNLICENSED"
pragma solidity 0.6.12;

import "../interfaces/IAdmin.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../interfaces/ISalesFactory.sol";
import "../interfaces/IAllocationStaking.sol";

contract AvalaunchSale {

    using ECDSA for bytes32;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Pointer to Allocation staking contract, where burnXavaFromUser will be called.
    IAllocationStaking public allocationStakingContract;

    ISalesFactory public factory;

    // Admin contract
    IAdmin public admin;

    struct Sale {
        // Token being sold
        IERC20 token;
        // Is sale created
        bool isCreated;
        // Are earnings and leftover withdrawn
        bool earningsWithdrawn;
        // Have tokens been deposited
        bool tokensDeposited;
        // Address of sale owner
        address saleOwner;
        // Price of the token quoted in AVAX
        uint256 tokenPriceInAVAX;
        // Amount of tokens to sell
        uint256 amountOfTokensToSell;
        // Total tokens being sold
        uint256 totalTokensSold;
        // Total AVAX Raised
        uint256 totalAVAXRaised;
        // Sale end time
        uint256 saleEnd;
        // When tokens can be withdrawn
        uint256 tokensUnlockTime;
    }

    // Participation structure
    struct Participation {
        uint256 amountBought;
        uint256 amountAVAXPaid;
        uint256 timeParticipated;
        uint256 roundId;
        bool [] isPortionWithdrawn;
    }

    // Round structure
    struct Round {
        uint startTime;
        uint maxParticipation;
    }

    struct Registration {
        uint256 registrationTimeStarts;
        uint256 registrationTimeEnds;
        uint256 numberOfRegistrants;
    }

    // Sale
    Sale public sale;

    // Registration
    Registration public registration;

    // Number of users participated in the sale.
    uint256 public numberOfParticipants;
    // Array storing IDS of rounds (IDs start from 1, so they can't be mapped as array indexes
    uint256 [] public roundIds;
    // Mapping round Id to round
    mapping (uint256 => Round) public roundIdToRound;
    // Mapping user to his participation
    mapping (address => Participation) public userToParticipation;
    // User to round for which he registered
    mapping (address => uint256) public addressToRoundRegisteredFor;
    // mapping if user is participated or not
    mapping (address => bool) public isParticipated;
    // One ether in weis
    uint256 public constant one = 10**18;
    // Times when portions are getting unlocked
    uint256 [] public vestingPortionsUnlockTime;
    // Percent of the participation user can withdraw
    uint256 [] public vestingPercentPerPortion;


    // Restricting calls only to sale owner
    modifier onlySaleOwner {
        require(msg.sender == sale.saleOwner, 'OnlySaleOwner:: Restricted');
        _;
    }

    modifier onlyAdmin {
        require(admin.isAdmin(msg.sender), "Only admin can call this function.");
        _;
    }


    event TokensSold(address user, uint256 amount);
    event UserRegistered(address user, uint256 roundId);
    event TokenPriceSet(uint256 newPrice);
    event MaxParticipationSet(uint256 roundId, uint256 maxParticipation);
    event TokensWithdrawn(address user, uint256 amount);
    event SaleCreated(address saleOwner, uint256 tokenPriceInAVAX, uint256 amountOfTokensToSell,
        uint256 saleEnd, uint256 tokensUnlockTime);
    event RegistrationTimeSet(uint256 registrationTimeStarts, uint256 registrationTimeEnds);
    event RoundAdded(uint256 roundId, uint256 startTime, uint256 maxParticipation);

    constructor(address _admin, address _allocationStaking) public {
        require(_admin != address(0));
        require(_allocationStaking != address(0));
        admin = IAdmin(_admin);
        factory = ISalesFactory(msg.sender);
        allocationStakingContract = IAllocationStaking(_allocationStaking);
    }

    /// @notice         Function to set vesting params
    function setVestingParams(uint256 [] memory _unlockingTimes, uint256 [] memory _percents)
    external
    onlyAdmin
    {
        require(vestingPercentPerPortion.length == 0 && vestingPortionsUnlockTime.length == 0);
        require(_unlockingTimes.length == _percents.length);

        for(uint256 i = 0; i < _unlockingTimes.length; i++) {
            vestingPortionsUnlockTime.push(_unlockingTimes[i]);
            vestingPercentPerPortion.push(_percents[i]);
        }

    }

    /// @notice     Admin function to set sale parameters
    function setSaleParams(
        address _token,
        address _saleOwner,
        uint256 _tokenPriceInAVAX,
        uint256 _amountOfTokensToSell,
        uint256 _saleEnd,
        uint256 _tokensUnlockTime
    )
    external
    onlyAdmin
    {
        require(!sale.isCreated, "setSaleParams: Sale is already created.");
        require(_token != address(0), "setSaleParams: Token address can not be 0.");
        require(_saleOwner != address(0), "setSaleParams: Sale owner address can not be 0.");
        require(_tokenPriceInAVAX != 0 && _amountOfTokensToSell != 0 && _saleEnd > block.timestamp &&
            _tokensUnlockTime > block.timestamp, "setSaleParams: Bad input");

        // Set params
        sale.token = IERC20(_token);
        sale.isCreated = true;
        sale.saleOwner = _saleOwner;
        sale.tokenPriceInAVAX = _tokenPriceInAVAX;
        sale.amountOfTokensToSell = _amountOfTokensToSell;
        sale.saleEnd = _saleEnd;
        sale.tokensUnlockTime = _tokensUnlockTime;

        // Mark in factory
        factory.setSaleOwnerAndToken(sale.saleOwner, address(sale.token));

        // Emit event
        emit SaleCreated(sale.saleOwner, sale.tokenPriceInAVAX, sale.amountOfTokensToSell, sale.saleEnd, sale.tokensUnlockTime);
    }

    /// @notice     Function to set registration period parameters
    function setRegistrationTime(
        uint256 _registrationTimeStarts,
        uint256 _registrationTimeEnds
    )
    external
    onlyAdmin
    {
        require(sale.isCreated == true);
        require(registration.registrationTimeStarts == 0);
        require(_registrationTimeStarts >= block.timestamp && _registrationTimeEnds > _registrationTimeStarts);
        require(_registrationTimeEnds < sale.saleEnd);

        if (roundIds.length > 0) {
            require(_registrationTimeEnds < roundIdToRound[roundIds[0]].startTime);
        }

        registration.registrationTimeStarts = _registrationTimeStarts;
        registration.registrationTimeEnds = _registrationTimeEnds;

        emit RegistrationTimeSet(registration.registrationTimeStarts, registration.registrationTimeEnds);
    }

    function setRounds(
        uint256[] calldata startTimes,
        uint256[] calldata maxParticipations
    )
    external
    onlyAdmin
    {
        require(sale.isCreated == true);
        require(startTimes.length == maxParticipations.length, "setRounds: Bad input.");
        require(roundIds.length == 0, "setRounds: Rounds are already");
        require(startTimes.length > 0);

        uint256 lastTimestamp = 0;
        for(uint i = 0; i < startTimes.length; i++) {
            require(startTimes[i] > registration.registrationTimeEnds);
            require(startTimes[i] < sale.saleEnd);
            require(startTimes[i] >= block.timestamp);
            require(maxParticipations[i] > 0);
            require(startTimes[i] > lastTimestamp);
            lastTimestamp = startTimes[i];

            // Compute round Id
            uint roundId = i+1;

            // Push id to array of ids
            roundIds.push(roundId);
            // Create round
            Round memory round = Round(startTimes[i], maxParticipations[i]);

            // Map round id to round
            roundIdToRound[roundId] = round;

            // Fire event
            emit RoundAdded(roundId, round.startTime, round.maxParticipation);
        }
    }

    /// @notice     Registration for sale.
    /// @param      signature is the message signed by the backend
    /// @param      roundId is the round for which user expressed interest to participate
    function registerForSale(
        bytes memory signature,
        uint roundId
    )
    external
    {
        require(roundId != 0, "Round ID can not be 0.");
        require(roundId <= roundIds.length, "Invalid round id");
        require(block.timestamp >= registration.registrationTimeStarts && block.timestamp <= registration.registrationTimeEnds, "Registration gate is closed.");
        require(checkRegistrationSignature(signature, msg.sender, roundId), "Invalid signature");
        require(addressToRoundRegisteredFor[msg.sender] == 0, "User can not register twice.");

        // Rounds are 1,2,3
        addressToRoundRegisteredFor[msg.sender] = roundId;

        // Special cases for staking round
        if(roundId == 2) {
            // Lock users stake
            allocationStakingContract.setTokensUnlockTime(0, msg.sender, sale.saleEnd);
        }

        // Increment number of registered users
        registration.numberOfRegistrants++;

        // Emit Registration event
        emit UserRegistered(msg.sender, roundId);
    }


    /// @notice     Admin function, to update token price before sale to match the closest $ desired rate.
    function updateTokenPriceInAVAX(
        uint256 price
    )
    external
    onlyAdmin
    {
        require(block.timestamp < roundIdToRound[roundIds[0]].startTime, "1st round already started.");
        require(price > 0, "Price can not be 0.");

        // Set new price in AVAX
        sale.tokenPriceInAVAX = price;

        // Emit event token price is set
        emit TokenPriceSet(price);
    }


    // SWC-113-DoS with Failed Call: L294
    /// @notice     Admin function to postpone the sale
    function postponeSale(
        uint256 timeToShift
    )
    external
    onlyAdmin
    {
        require(block.timestamp < roundIdToRound[roundIds[0]].startTime, "1st round already started.");

        // Iterate through all registered rounds and postpone them
        for(uint i = 0; i < roundIds.length; i++) {
            Round storage round = roundIdToRound[roundIds[i]];
            // Postpone sale
            round.startTime = round.startTime.add(timeToShift);
        }
    }

    /// @notice     Function to extend registration period
    function extendRegistrationPeriod(
        uint256 timeToAdd
    )
    external
    onlyAdmin
    {
        require(registration.registrationTimeEnds.add(timeToAdd) < roundIdToRound[roundIds[0]].startTime,
            "Registration period overflows sale start.");

        registration.registrationTimeEnds = registration.registrationTimeEnds.add(timeToAdd);
    }


    /// @notice     Admin function to set max participation cap per round
    function setCapPerRound(
        uint256[] calldata rounds,
        uint256[] calldata caps
    )
    external
    onlyAdmin
    {
        require(block.timestamp < roundIdToRound[roundIds[0]].startTime, "1st round already started.");
        require(rounds.length == caps.length, "Arrays length is different.");

        for(uint i = 0; i < rounds.length; i++) {
            require(caps[i] > 0, "Can't set max participation to 0");

            Round storage round = roundIdToRound[rounds[i]];
            round.maxParticipation = caps[i];

            emit MaxParticipationSet(rounds[i], round.maxParticipation);
        }
    }


    // SWC-113-DoS with Failed Call: L346
    // Function for owner to deposit tokens, can be called only once.
    function depositTokens()
    external
    onlySaleOwner
    {
        require(sale.totalTokensSold == 0 && sale.token.balanceOf(address(this)) == 0, "Deposit can be done only once");
        require(block.timestamp < roundIdToRound[roundIds[0]].startTime, "Deposit too late. Round already started.");

        sale.token.safeTransferFrom(msg.sender, address(this), sale.amountOfTokensToSell);
        sale.tokensDeposited = true;
    }


    // Function to participate in the sales
    function participate(
        bytes memory signature,
        uint256 amount,
        uint256 amountXavaToBurn,
        uint256 roundId
    )
    external
    payable
    {
        // Disallow participation if no tokens deposited
        require(sale.tokensDeposited == true, "Tokens not deposited yet");

        require(roundId != 0, "Round can not be 0.");

        require(amount <= roundIdToRound[roundId].maxParticipation, "Overflowing maximal participation for this round.");

        // User must have registered for the round in advance
        require(addressToRoundRegisteredFor[msg.sender] == roundId, "Not registered for this round");

        // Verify the signature
        require(checkParticipationSignature(signature, msg.sender, amount, amountXavaToBurn, roundId), "Invalid signature. Verification failed");

        // Check user haven't participated before
        require(isParticipated[msg.sender] == false, "User can participate only once.");

        // Disallow contract calls.
        require(msg.sender == tx.origin, "Only direct contract calls.");

        // Get current active round
        uint256 currentRound = getCurrentRound();

        // Assert that
        require(roundId == currentRound, "You can not participate in this round.");

        // Compute the amount of tokens user is buying
        uint256 amountOfTokensBuying = (msg.value).mul(10**18).div(sale.tokenPriceInAVAX);

        // Must buy more than 0 tokens
        require(amountOfTokensBuying > 0, "Can't buy 0 tokens");

        // Check in terms of user allo
        require(amountOfTokensBuying <= amount, "Trying to buy more than allowed.");

        // Increase amount of sold tokens
        sale.totalTokensSold = sale.totalTokensSold.add(amountOfTokensBuying);

        // Increase amount of AVAX raised
        sale.totalAVAXRaised = sale.totalAVAXRaised.add(msg.value);

        // Create participation object
        Participation memory p;
        p.amountBought = amountOfTokensBuying;
        p.amountAVAXPaid = msg.value;
        p.timeParticipated = block.timestamp;
        p.roundId = roundId;

        // Staking round only.
        if(roundId == 2) {
            // Burn XAVA from this user.
            allocationStakingContract.redistributeXava(0, msg.sender, amountXavaToBurn);
        }

        // Add participation for user.
        userToParticipation[msg.sender] = p;

        // Mark user is participated
        isParticipated[msg.sender] = true;

        // Increment number of participants in the Sale.
        numberOfParticipants ++;

        emit TokensSold(msg.sender, amountOfTokensBuying);
    }


    /// Users can claim their participation
    function withdrawTokens(uint portionId) external {
        require(block.timestamp >= sale.tokensUnlockTime, "Tokens can not be withdrawn yet.");
        require(portionId < vestingPercentPerPortion.length);

        Participation storage p = userToParticipation[msg.sender];

        if(!p.isPortionWithdrawn[portionId] && vestingPortionsUnlockTime[portionId] >= block.timestamp) {
            p.isPortionWithdrawn[portionId];
            uint256 amountWithdrawing = p.amountBought.mul(vestingPercentPerPortion[portionId]).div(100);
            // Withdraw percent which is unlocked at that portion
            sale.token.safeTransfer(msg.sender, amountWithdrawing);
            emit TokensWithdrawn(msg.sender, amountWithdrawing);
        } else {
            revert("Tokens already withdrawn.");
        }
    }


    // Internal function to handle safe transfer
    function safeTransferAVAX(
        address to,
        uint value
    )
    internal
    {
        (bool success,) = to.call{value:value}(new bytes(0));
        require(success);
    }


    /// Function to withdraw all the earnings and the leftover of the sale contract.
    function withdrawEarningsAndLeftover(
        bool withBurn
    )
    external
    onlySaleOwner
    {
        // Make sure sale ended
        require(block.timestamp >= sale.saleEnd);

        // Make sure owner can't withdraw twice
        require(sale.earningsWithdrawn == false);
        sale.earningsWithdrawn = true;

        // Earnings amount of the owner in AVAX
        uint totalProfit = address(this).balance;

        // Amount of tokens which are not sold
        uint leftover = sale.amountOfTokensToSell.sub(sale.totalTokensSold);

        safeTransferAVAX(msg.sender, totalProfit);

        if(leftover > 0 && !withBurn) {
            sale.token.safeTransfer(msg.sender, leftover);
            return;
        }

        if(withBurn) {
            sale.token.safeTransfer(address(1), leftover);
        }
    }

    /// @notice     Get current round in progress.
    ///             If 0 is returned, means sale didn't start or it's ended.
    function getCurrentRound() public view returns (uint) {
        uint i = 0;
        if(block.timestamp < roundIdToRound[roundIds[0]].startTime) {
            return 0; // Sale didn't start yet.
        }

        while((i+1) < roundIds.length && block.timestamp > roundIdToRound[roundIds[i+1]].startTime) {
            i++;
        }

        if(block.timestamp >= sale.saleEnd) {
            return 0; // Means sale is ended
        }

        return roundIds[i];
    }

    /// @notice     Check signature user submits for registration.
    /// @param      signature is the message signed by the trusted entity (backend)
    /// @param      user is the address of user which is registering for sale
    /// @param      roundId is the round for which user is submitting registration
    function checkRegistrationSignature(
        bytes memory signature,
        address user,
        uint256 roundId
    )
    public
    view
    returns (bool)
    {
        bytes32 hash = keccak256(abi.encodePacked(user, roundId, address(this)));
        bytes32 messageHash = hash.toEthSignedMessageHash();
        return admin.isAdmin(messageHash.recover(signature));
    }


    // Function to check if admin was the message signer
    function checkParticipationSignature(
        bytes memory signature,
        address user,
        uint256 amount,
        uint256 amountXavaToBurn,
        uint256 round
    )
    public
    view
    returns (bool)
    {
        return admin.isAdmin(getParticipationSigner(signature, user, amount, amountXavaToBurn, round));
    }


    /// @notice     Check who signed the message
    /// @param      signature is the message allowing user to participate in sale
    /// @param      user is the address of user for which we're signing the message
    /// @param      amount is the maximal amount of tokens user can buy
    /// @param      roundId is the Id of the round user is participating.
    function getParticipationSigner(
        bytes memory signature,
        address user,
        uint256 amount,
        uint256 amountXavaToBurn,
        uint256 roundId
    )
    public
    view
    returns (address)
    {
        bytes32 hash = keccak256(abi.encodePacked(user, amount, amountXavaToBurn, roundId, address(this)));
        bytes32 messageHash = hash.toEthSignedMessageHash();
        return messageHash.recover(signature);
    }

    /// @notice     Function to get participation for passed user address
    function getParticipation(address _user) external view returns (uint256, uint256, uint256, uint256, bool[] memory) {
        Participation memory p = userToParticipation[_user];
        return (
            p.amountBought,
            p.amountAVAXPaid,
            p.timeParticipated,
            p.roundId,
            p.isPortionWithdrawn
        );
    }

    /// @notice     Function to get info about the registration
    function getRegistrationInfo() external view returns (uint256, uint256) {
        return (
            registration.registrationTimeEnds,
            registration.numberOfRegistrants
        );
    }

}
