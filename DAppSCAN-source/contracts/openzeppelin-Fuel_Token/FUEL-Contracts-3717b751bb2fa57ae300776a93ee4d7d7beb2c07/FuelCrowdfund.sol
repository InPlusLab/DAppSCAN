pragma solidity ^0.4.15;

import 'zeppelin-solidity/contracts/math/SafeMath.sol';
import 'zeppelin-solidity/contracts/ownership/Ownable.sol';
import "./helpers/NonZero.sol";

contract FuelToken {    
    function transferFromCrowdfund(address _to, uint256 _amount) returns (bool success);
    function finalizeCrowdfund() returns (bool success);
}

contract FuelCrowdfund is NonZero, Ownable {
    
    using SafeMath for uint;

/////////////////////// VARIABLE INITIALIZATION ///////////////////////

    // Address of the deployed FUEL Token contract
    address public tokenAddress;
    // Address of secure wallet to send crowdfund contributions to
    address public wallet;

    // Amount of wei currently raised
    uint256 public weiRaised = 0;
    // UNIX timestamp of when the crowdfund starts
    uint256 public startsAt;
    // UNIX timestamp of when the crowdfund ends
    uint256 public endsAt;

    // Instance of the Fuel token contract
    FuelToken public token;
    
/////////////////////// EVENTS ///////////////////////

    // Emitted upon owner changing the wallet address
    event WalletAddressChanged(address _wallet);
    // Emitted upon crowdfund being finalized
    event AmountRaised(address beneficiary, uint amountRaised);
    // Emmitted upon purchasing tokens
    event TokenPurchase(address indexed purchaser, uint256 value, uint256 amount);

/////////////////////// MODIFIERS ///////////////////////

    // Ensure the crowdfund is ongoing
    modifier crowdfundIsActive() {
        assert(now >= startsAt && now <= endsAt);
        _;
    }

/////////////////////// CROWDFUND FUNCTIONS ///////////////////////
    
    // Constructor
    function FuelCrowdfund(address _tokenAddress) {
        wallet = 0x854f7424b2150bb4c3f42f04dd299318f84e98a5;    // Etherparty Wallet Address
        startsAt = 1505458800;                                  // Sept 15 2017
        endsAt = 1507852800;                                    // ~4 weeks / 28 days later: Oct 13, 00:00:00 UTC 2017
        tokenAddress = _tokenAddress;                           // FUEL token Address
        token = FuelToken(tokenAddress);
    }

    // Change main contribution wallet
    function changeWalletAddress(address _wallet) onlyOwner {
        wallet = _wallet;
        WalletAddressChanged(_wallet);
    }


    // Function to buy Fuel. One can also buy FUEL by calling this function directly and send 
    // it to another destination.
    function buyTokens(address _to) crowdfundIsActive nonZeroAddress(_to) payable {
        uint256 weiAmount = msg.value;
        uint256 tokens = weiAmount * getIcoPrice();
        weiRaised = weiRaised.add(weiAmount);
        wallet.transfer(weiAmount);
        if (!token.transferFromCrowdfund(_to, tokens)) {
            revert();
        }
        TokenPurchase(_to, weiAmount, tokens);
    }
//SWC-104-Unchecked Call Return Value:L84
    // Function to close the crowdfund. Any unsold FUEL will go to the platform to be sold at 1$
    function closeCrowdfund() external onlyOwner returns (bool success) {
        AmountRaised(wallet, weiRaised);
        token.finalizeCrowdfund();
        return true;
    }

/////////////////////// CONSTANT FUNCTIONS ///////////////////////

    // Returns FUEL disbursed per 1 ETH depending on current time
    function getIcoPrice() public constant returns (uint price) {
        if (now > (startsAt + 3 weeks)) {
           return 1275; // week 4
        } else if (now > (startsAt + 2 weeks)) {
           return 1700; // week 3
        } else if (now > (startsAt + 1 weeks)) {
           return 2250; // week 2
        } else {
           return 3000; // week 1
        }
    }

    // To contribute, send a value transaction to the Crowdfund Address.
    // Please include at least 100 000 gas.
    function () payable nonZeroValue {
        buyTokens(msg.sender);
    }
}