//"SPDX-License-Identifier: UNLICENSED"
pragma solidity ^0.6.12;

import "./math/SafeMath.sol";
import "./IERC20.sol";

/// ParticipationVesting smart contract
contract ParticipationVestingPrivate {

    using SafeMath for *;

    uint public totalTokensToDistribute;
    uint public totalTokensWithdrawn;

    struct Participation {
        uint256 initialPortion;
        uint256 vestedAmount;
        uint256 amountPerPortion;
        bool initialPortionWithdrawn;
        bool [] isVestedPortionWithdrawn;
    }

    IERC20 public token;

    address public adminWallet;
    mapping(address => Participation) public addressToParticipation;
    mapping(address => bool) public hasParticipated;

    uint public initialPortionUnlockingTime;
    uint public numberOfPortions;
    uint [] distributionDates;

    modifier onlyAdmin {
        require(msg.sender == adminWallet, "OnlyAdmin: Restricted access.");
        _;
    }

    /// Load initial distribution dates
    constructor (
        uint _numberOfPortions,
        uint timeBetweenPortions,
        uint distributionStartDate,
        uint _initialPortionUnlockingTime,
        address _adminWallet,
        address _token
    )
    public
    {
        // Set admin wallet
        adminWallet = _adminWallet;
        // Store number of portions
        numberOfPortions = _numberOfPortions;

        // Time when initial portion is unlocked
        initialPortionUnlockingTime = _initialPortionUnlockingTime;

        // Set distribution dates
        for(uint i = 0 ; i < _numberOfPortions; i++) {
            distributionDates.push(distributionStartDate + i*timeBetweenPortions);
        }
        // Set the token address
        token = IERC20(_token);
    }

    // Function to register multiple participants at a time
    function registerParticipants(
        address [] memory participants,
        uint256 [] memory participationAmounts
    )
    external
    onlyAdmin
    {
        for(uint i = 0; i < participants.length; i++) {
            registerParticipant(participants[i], participationAmounts[i]);
        }
    }


    /// Register participant
    function registerParticipant(
        address participant,
        uint participationAmount
    )
    internal
    {
        require(totalTokensToDistribute.sub(totalTokensWithdrawn).add(participationAmount) <= token.balanceOf(address(this)),
            "Safeguarding existing token buyers. Not enough tokens."
        );

        totalTokensToDistribute = totalTokensToDistribute.add(participationAmount);

        require(!hasParticipated[participant], "User already registered as participant.");

        uint initialPortionAmount = participationAmount.mul(20).div(100);
        // Vested 80%
        uint vestedAmount = participationAmount.sub(initialPortionAmount);

        // Compute amount per portion
        uint portionAmount = vestedAmount.div(numberOfPortions);
        bool[] memory isPortionWithdrawn = new bool[](numberOfPortions);

        // Create new participation object
        Participation memory p = Participation({
            initialPortion: initialPortionAmount,
            vestedAmount: vestedAmount,
            amountPerPortion: portionAmount,
            initialPortionWithdrawn: false,
            isVestedPortionWithdrawn: isPortionWithdrawn
        });

        // Map user and his participation
        addressToParticipation[participant] = p;
        // Mark that user have participated
        hasParticipated[participant] = true;
    }


    // User will always withdraw everything available
    function withdraw()
    external
    {
        address user = msg.sender;
        require(hasParticipated[user] == true, "Withdraw: User is not a participant.");

        Participation storage p = addressToParticipation[user];

        uint256 totalToWithdraw = 0;

        // Initial portion can be withdrawn
        if(!p.initialPortionWithdrawn && block.timestamp >= initialPortionUnlockingTime) {
            totalToWithdraw = totalToWithdraw.add(p.initialPortion);
            // Mark initial portion as withdrawn
            p.initialPortionWithdrawn = true;
        }


        // For loop instead of while
        for(uint i = 0 ; i < numberOfPortions ; i++) {
            if(isPortionUnlocked(i) == true && i < distributionDates.length) {
                if(!p.isVestedPortionWithdrawn[i]) {
                    // Add this portion to withdraw amount
                    totalToWithdraw = totalToWithdraw.add(p.amountPerPortion);

                    // Mark portion as withdrawn
                    p.isVestedPortionWithdrawn[i] = true;
                }
            }
        }

        // Account total tokens withdrawn.
        totalTokensWithdrawn = totalTokensWithdrawn.add(totalToWithdraw);
        // Transfer all tokens to user
        token.transfer(user, totalToWithdraw);
    }

    function isPortionUnlocked(uint portionId)
    public
    view
    returns (bool)
    {
        return block.timestamp >= distributionDates[portionId];
    }


    function getParticipation(address account)
    external
    view
    returns (uint256, uint256, uint256, bool, bool [] memory)
    {
        Participation memory p = addressToParticipation[account];
        bool [] memory isVestedPortionWithdrawn = new bool [](numberOfPortions);

        for(uint i=0; i < numberOfPortions; i++) {
            isVestedPortionWithdrawn[i] = p.isVestedPortionWithdrawn[i];
        }

        return (
            p.initialPortion,
            p.vestedAmount,
            p.amountPerPortion,
            p.initialPortionWithdrawn,
            isVestedPortionWithdrawn
        );
    }

    // Get all distribution dates
    function getDistributionDates()
    external
    view
    returns (uint256 [] memory)
    {
        return distributionDates;
    }
}
