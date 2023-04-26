pragma solidity ^0.4.11;

/*
    Copyright 2017, Jordi Baylina

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

/// @title REALCrowdsale Contract
/// @author Jordi Baylina
/// @dev This contract will be the REAL controller during the crowdsale period.
///  This contract will determine the rules during this period.
///  Final users will generally not interact directly with this contract. ETH will
///  be sent to the REAL token contract. The ETH is sent to this contract and from here,
///  ETH is sent to the contribution walled and REALs are mined according to the defined
///  rules.


import "./Owned.sol";
import "./MiniMeToken.sol";
import "./SafeMath.sol";
import "./ERC20Token.sol";


contract REALCrowdsale is Owned, TokenController {
    using SafeMath for uint256;

    uint256 constant public fundingLimit = 100000 ether;
    uint256 constant public failSafeLimit = 200000 ether;
    uint256 constant public maxGuaranteedLimit = 30000 ether;
    uint256 constant public exchangeRate = 220;
    uint256 constant public maxGasPrice = 50000000000;
    uint256 constant public maxCallFrequency = 100;

    uint256 constant public bonus1cap = 25000 ether;
    uint256 constant public bonus1 = 25;
    uint256 constant public bonus2cap = 50000 ether;
    uint256 constant public bonus2 = 20;
    uint256 constant public bonus3cap = 100000 ether;
    uint256 constant public bonus3 = 15;
    uint256 constant public bonus4cap = 150000 ether;
    uint256 constant public bonus4 = 5;

    MiniMeToken public REAL;
    uint256 public startBlock;
    uint256 public endBlock;

    address public destEthTeam;

    address public destTokensTeam;
    address public destTokensReserve;
    address public destTokensBounties;

    address public realController;

    mapping (address => uint256) public guaranteedBuyersLimit;
    mapping (address => uint256) public guaranteedBuyersBought;

    uint256 public totalGuaranteedCollected;
    uint256 public totalNormalCollected;
    uint256 public reservedGuaranteed;

    uint256 public finalizedBlock;
    uint256 public finalizedTime;

    mapping (address => uint256) public lastCallBlock;

    bool public paused;

    modifier initialized() {
        require(address(REAL) != 0x0);
        _;
    }

    modifier contributionOpen() {
        require(getBlockNumber() >= startBlock &&
                getBlockNumber() <= endBlock &&
                finalizedBlock == 0 &&
                address(REAL) != 0x0);
        _;
    }

    modifier notPaused() {
        require(!paused);
        _;
    }

    function REALCrowdsale() {
        paused = false;
    }


    /// @notice This method should be called by the owner before the contribution
    ///  period starts This initializes most of the parameters
    /// @param _real Address of the REAL token contract
    /// @param _realController Token controller for the REAL that will be transferred after
    ///  the contribution finalizes.
    /// @param _startBlock Block when the contribution period starts
    /// @param _endBlock The last block that the contribution period is active
    /// @param _destEthTeam Destination address where the contribution ether is sent
    /// @param _destTokensReserve Address where the tokens for the reserve are sent
    function initialize(
        address _real,
        address _realController,
        uint256 _startBlock,
        uint256 _endBlock,
        address _destEthTeam,
        address _destTokensReserve,
        address _destTokensTeam,
        address _destTokensBounties
    ) public onlyOwner {
        // Initialize only once
        require(address(REAL) == 0x0);

        REAL = MiniMeToken(_real);
        require(REAL.totalSupply() == 0);
        require(REAL.controller() == address(this));
        require(REAL.decimals() == 18);  // Same amount of decimals as ETH

        require(_realController != 0x0);
        realController = _realController;

        require(_startBlock >= getBlockNumber());
        require(_startBlock < _endBlock);
        startBlock = _startBlock;
        endBlock = _endBlock;

        require(_destEthTeam != 0x0);
        destEthTeam = _destEthTeam;

        require(_destTokensReserve != 0x0);
        destTokensReserve = _destTokensReserve;

        require(_destTokensTeam != 0x0);
        destTokensTeam = _destTokensTeam;

        require(_destTokensBounties != 0x0);
        destTokensBounties = _destTokensBounties;
    }

    /// @notice Sets the limit for a guaranteed address. All the guaranteed addresses
    ///  will be able to get REALs during the contribution period with his own
    ///  specific limit.
    ///  This method should be called by the owner after the initialization
    ///  and before the contribution starts.
    /// @param _th Guaranteed address
    /// @param _limit Limit for the guaranteed address.
    function setGuaranteedAddress(address _th, uint256 _limit) public initialized onlyOwner {
        require(getBlockNumber() < startBlock);
        require(_limit > 0 && _limit <= maxGuaranteedLimit);
        guaranteedBuyersLimit[_th] = _limit;
        reservedGuaranteed = reservedGuaranteed + _limit;
        GuaranteedAddress(_th, _limit);
    }

    /// @notice If anybody sends Ether directly to this contract, consider he is
    ///  getting REALs.
    function () public payable notPaused {
        proxyPayment(msg.sender);
    }


    //////////
    // MiniMe Controller functions
    //////////

    /// @notice This method will generally be called by the REAL token contract to
    ///  acquire REALs. Or directly from third parties that want to acquire REALs in
    ///  behalf of a token holder.
    /// @param _th REAL holder where the REALs will be minted.
    function proxyPayment(address _th) public payable notPaused initialized contributionOpen returns (bool) {
        require(_th != 0x0);
        uint256 guaranteedRemaining = guaranteedBuyersLimit[_th].sub(guaranteedBuyersBought[_th]);
        /*LogGuaranteed(_th, guaranteedBuyersLimit[_th].div(10**18), guaranteedBuyersBought[_th].div(10**18), guaranteedRemaining.div(10**18), "  ");*/
        if (guaranteedRemaining > 0) {
            buyGuaranteed(_th);
        } else {
            buyNormal(_th);
        }
        return true;
    }

    function onTransfer(address, address, uint256) public returns (bool) {
        return false;
    }

    function onApprove(address, address, uint256) public returns (bool) {
        return false;
    }

    function buyNormal(address _th) internal {
        require(tx.gasprice <= maxGasPrice);

        // Antispam mechanism
        address caller;
        if (msg.sender == address(REAL)) {
            caller = _th;
        } else {
            caller = msg.sender;
        }

        // Do not allow contracts to game the system
        require(!isContract(caller));

        require(getBlockNumber().sub(lastCallBlock[caller]) >= maxCallFrequency);
        lastCallBlock[caller] = getBlockNumber();

        uint256 toCollect = failSafeLimit - totalNormalCollected; //This was fundingLimit - totalNormalCollected

        uint256 toFund;
        if (msg.value <= toCollect) {
            toFund = msg.value;
        } else {
            toFund = toCollect;
        }

        totalNormalCollected = totalNormalCollected.add(toFund);
        doBuy(_th, toFund, false);
    }

    function buyGuaranteed(address _th) internal {
        uint256 toCollect = guaranteedBuyersLimit[_th];

        uint256 toFund;
        if (guaranteedBuyersBought[_th].add(msg.value) > toCollect) {
            toFund = toCollect.sub(guaranteedBuyersBought[_th]);
        } else {
            toFund = msg.value;
        }

        guaranteedBuyersBought[_th] = guaranteedBuyersBought[_th].add(toFund);
        totalGuaranteedCollected = totalGuaranteedCollected.add(toFund);
        doBuy(_th, toFund, true);
    }

    function doBuy(address _th, uint256 _toFund, bool _guaranteed) internal {
        assert(msg.value >= _toFund);  // Not needed, but double check.
        assert(totalCollected() <= failSafeLimit);

        uint256 collected = totalCollected();
        uint256 totCollected = collected;
        collected = collected.sub(_toFund);

        if (_toFund > 0) {
            uint256 tokensGenerated = _toFund.mul(exchangeRate);
            uint256 tokensToBonusCap = 0;
            uint256 tokensToNextBonusCap = 0;
            uint256 bonusTokens = 0;

            //Guaranteed should be 25.000 plus some that could enter while we close the purchase, so we only control first and secon caps (second for the extra).
            if(_guaranteed) {
              uint256 guaranteedCollected = totalGuaranteedCollected - _toFund;
              if (guaranteedCollected < bonus1cap) {
                if (totalGuaranteedCollected < bonus1cap) {
                  tokensGenerated = tokensGenerated.add(tokensGenerated.percent(bonus1));
                } else {
                  bonusTokens = bonus1cap.sub(guaranteedCollected).percent(bonus1).mul(exchangeRate);
                  tokensToBonusCap = tokensGenerated.add(bonusTokens);
                  tokensToNextBonusCap = totalGuaranteedCollected.sub(bonus1cap).percent(bonus2).mul(exchangeRate);
                  tokensGenerated = tokensToBonusCap.add(tokensToNextBonusCap);
                }
              } else {
                if (totalGuaranteedCollected < bonus2cap) {
                  tokensGenerated = tokensGenerated.add(tokensGenerated.percent(bonus2));
                } else {
                  bonusTokens = bonus2cap.sub(guaranteedCollected).percent(bonus2).mul(exchangeRate);
                  tokensToBonusCap = tokensGenerated.add(bonusTokens);
                  tokensToNextBonusCap = totalGuaranteedCollected.sub(bonus2cap).percent(bonus3).mul(exchangeRate);
                  tokensGenerated = tokensToBonusCap.add(tokensToNextBonusCap);
                }
              }
            } else if (collected < bonus1cap) {
              if (collected.add(_toFund) < bonus1cap) {
                tokensGenerated = tokensGenerated.add(tokensGenerated.percent(bonus1));
                /*LogQuantity(tokensGenerated.div(10**18), "Tokens generated plus percentage cap 1");*/
              } else {
                bonusTokens = bonus1cap.sub(collected).percent(bonus1).mul(exchangeRate);
                /*LogQuantity(bonusTokens.div(10**18), "bonus cap 1");*/
                tokensToBonusCap = tokensGenerated.add(bonusTokens);
                /*LogQuantity(tokensToBonusCap.div(10**18), "tokens until cap 1");*/
                tokensToNextBonusCap = totCollected.sub(bonus1cap).percent(bonus2).mul(exchangeRate);
                /*LogQuantity(tokensToNextBonusCap.div(10**18), "tokens for cap 2");*/
                tokensGenerated = tokensToBonusCap.add(tokensToNextBonusCap);
                /*LogQuantity(tokensGenerated.div(10**18), "Final tokens generated");*/

              }
            } else if (collected < bonus2cap) {
              if (collected.add(_toFund) < bonus2cap) {
                tokensGenerated = tokensGenerated.add(tokensGenerated.percent(bonus2));
                /*LogQuantity(tokensGenerated.div(10**18), "Tokens generated plus percentage cap 2");*/

              } else {
                bonusTokens = bonus2cap.sub(collected).percent(bonus2).mul(exchangeRate);
                /*LogQuantity(bonusTokens.div(10**18), "bonus cap 2");*/
                tokensToBonusCap = tokensGenerated.add(bonusTokens);
                /*LogQuantity(tokensToBonusCap.div(10**18), "tokens until cap 2");*/
                tokensToNextBonusCap = totCollected.sub(bonus2cap).percent(bonus3).mul(exchangeRate);
                /*LogQuantity(tokensToNextBonusCap.div(10**18), "tokens for cap 3");*/
                tokensGenerated = tokensToBonusCap.add(tokensToNextBonusCap);
                /*LogQuantity(tokensGenerated.div(10**18), "Final tokens generated");*/

              }
            } else if (collected < bonus3cap) {
              if (collected.add(_toFund) < bonus3cap) {
                tokensGenerated = tokensGenerated.add(tokensGenerated.percent(bonus3));
                /*LogQuantity(tokensGenerated.div(10**18), "Tokens generated plus percentage cap 3");*/

              } else {
                bonusTokens = bonus3cap.sub(collected).percent(bonus3).mul(exchangeRate);
                /*LogQuantity(bonusTokens.div(10**18), "bonus cap 3");*/
                tokensToBonusCap = tokensGenerated.add(bonusTokens);
                /*LogQuantity(tokensToBonusCap.div(10**18), "tokens until cap 3");*/
                tokensToNextBonusCap = totCollected.sub(bonus3cap).percent(bonus4).mul(exchangeRate);
                /*LogQuantity(tokensToNextBonusCap.div(10**18), "tokens for cap 4");*/
                tokensGenerated = tokensToBonusCap.add(tokensToNextBonusCap);
                /*LogQuantity(tokensGenerated.div(10**18), "Final tokens generated");*/

              }
            } else if (collected < bonus4cap) {
              if (collected.add(_toFund) < bonus4cap) {
                tokensGenerated = tokensGenerated.add(tokensGenerated.percent(bonus4));
                /*LogQuantity(tokensGenerated.div(10**18), "Tokens generated plus percentage cap 4");*/

              } else {
                bonusTokens = bonus4cap.sub(collected).percent(bonus4).mul(exchangeRate);
                /*LogQuantity(bonusTokens.div(10**18), "bonus cap 4");*/
                tokensGenerated = tokensGenerated.add(bonusTokens);
                /*LogQuantity(tokensGenerated.div(10**18), "tokens until cap 4");*/
              }
            }

            assert(REAL.generateTokens(_th, tokensGenerated));
            destEthTeam.transfer(_toFund);

            NewSale(_th, _toFund, tokensGenerated, _guaranteed);
        }

        uint256 toReturn = msg.value.sub(_toFund);
        if (toReturn > 0) {
            // If the call comes from the Token controller,
            // then we return it to the token Holder.
            // Otherwise we return to the sender.
            if (msg.sender == address(REAL)) {
                _th.transfer(toReturn);
            } else {
                msg.sender.transfer(toReturn);
            }
        }
    }

    // NOTE on Percentage format
    // Right now, Solidity does not support decimal numbers. (This will change very soon)
    //  So in this contract we use a representation of a percentage that consist in
    //  expressing the percentage in "x per 10**18"
    // This format has a precision of 16 digits for a percent.
    // Examples:
    //  3%   =   3*(10**16)
    //  100% = 100*(10**16) = 10**18
    //
    // To get a percentage of a value we do it by first multiplying it by the percentage in  (x per 10^18)
    //  and then divide it by 10**18
    //
    //              Y * X(in x per 10**18)
    //  X% of Y = -------------------------
    //               100(in x per 10**18)
    //


    /// @notice This method will can be called by the owner before the contribution period
    ///  end or by anybody after the `endBlock`. This method finalizes the contribution period
    ///  by creating the remaining tokens and transferring the controller to the configured
    ///  controller.
    function finalize() public initialized {
        require(getBlockNumber() >= startBlock);
        require(msg.sender == owner || getBlockNumber() > endBlock);
        require(finalizedBlock == 0);

        // Allow premature finalization if final limit is reached
        if (getBlockNumber() <= endBlock) {
            require(totalNormalCollected >= fundingLimit);
        }

        finalizedBlock = getBlockNumber();
        finalizedTime = now;

        uint256 percentageToTeam = percent(20);

        uint256 percentageToContributors = percent(51);

        uint256 percentageToReserve = percent(15);

        uint256 percentageToBounties = percent(14);


        // REAL.totalSupply() -> Tokens minted during the contribution
        //  totalTokens  -> Total tokens that should be after the allocation
        //                   of devTokens and reserve
        //  percentageToContributors -> Which percentage should go to the
        //                               contribution participants
        //                               (x per 10**18 format)
        //  percent(100) -> 100% in (x per 10**18 format)
        //
        //                       percentageToContributors
        //  REAL.totalSupply() = -------------------------- * totalTokens  =>
        //                             percent(100)
        //
        //
        //                            percent(100)
        //  =>  totalTokens = ---------------------------- * REAL.totalSupply()
        //                      percentageToContributors
        //
        uint256 totalTokens = REAL.totalSupply().mul(percent(100)).div(percentageToContributors);


        //
        //                    percentageToBounties
        //  bountiesTokens = ----------------------- * totalTokens
        //                      percentage(100)
        //
        assert(REAL.generateTokens(
            destTokensBounties,
            totalTokens.mul(percentageToBounties).div(percent(100))));

        //
        //                    percentageToReserve
        //  reserveTokens = ----------------------- * totalTokens
        //                      percentage(100)
        //
        assert(REAL.generateTokens(
            destTokensReserve,
            totalTokens.mul(percentageToReserve).div(percent(100))));


        //
        //                   percentageToTeam
        //  teamTokens = ----------------------- * totalTokens
        //                   percentage(100)
        //
        assert(REAL.generateTokens(
            destTokensTeam,
            totalTokens.mul(percentageToTeam).div(percent(100))));

        REAL.changeController(realController);

        Finalized();
    }

    function percent(uint256 p) internal returns (uint256) {
        return p.mul(10**16);
    }

    /// @dev Internal function to determine if an address is a contract
    /// @param _sender the sender address
    /// @return True if tx.origin is not the sender (so smart contract involved)
    function isContract(address _sender) constant internal returns (bool) {
        return tx.origin != _sender;
        /*if (_addr == 0) return false;
        uint256 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);*/

    }


    //////////
    // Constant functions
    //////////

    /// @return Total tokens issued in weis.
    function tokensIssued() public constant returns (uint256) {
        return REAL.totalSupply();
    }

    /// @return Total Ether collected.
    function totalCollected() public constant returns (uint256) {
        return totalNormalCollected.add(totalGuaranteedCollected);
    }


    //////////
    // Testing specific methods
    //////////

    /// @notice This function is overridden by the test Mocks.
    function getBlockNumber() internal constant returns (uint256) {
        return block.number;
    }


    //////////
    // Safety Methods
    //////////

    /// @notice This method can be used by the controller to extract mistakenly
    ///  sent tokens to this contract.
    /// @param _token The address of the token contract that you want to recover
    ///  set to 0 in case you want to extract ether.
    function claimTokens(address _token) public onlyOwner {
        if (REAL.controller() == address(this)) {
            REAL.claimTokens(_token);
        }
        if (_token == 0x0) {
            owner.transfer(this.balance);
            return;
        }

        ERC20Token token = ERC20Token(_token);
        uint256 balance = token.balanceOf(this);
        token.transfer(owner, balance);
        ClaimedTokens(_token, owner, balance);
    }


    /// @notice Pauses the contribution if there is any issue
    function pauseContribution() onlyOwner {
        paused = true;
    }

    /// @notice Resumes the contribution
    function resumeContribution() onlyOwner {
        paused = false;
    }

    event ClaimedTokens(address indexed _token, address indexed _controller, uint256 _amount);
    event NewSale(address indexed _th, uint256 _amount, uint256 _tokens, bool _guaranteed);
    event GuaranteedAddress(address indexed _th, uint256 _limit);
    event Finalized();
    event LogQuantity(uint256 _amount, string _message);
    event LogGuaranteed(address _address, uint256 _buyersLimit, uint256 _buyersBought, uint256 _buyersRemaining, string _message);
}
