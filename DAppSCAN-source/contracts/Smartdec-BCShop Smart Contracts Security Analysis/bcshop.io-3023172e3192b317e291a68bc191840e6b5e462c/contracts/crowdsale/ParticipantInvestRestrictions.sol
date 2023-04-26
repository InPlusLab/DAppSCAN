pragma solidity ^0.4.10;

import './FloorInvestRestrictions.sol';
import './ICrowdsaleFormula.sol';

/**@dev In addition to 'floor' behavior restricts investments if there are already too many investors. 
Contract owner can reserve some places for future investments:
1. It is possible to reserve a place for unknown address using 'reserve' function. 
    When invest happens you should 'unreserve' that place manually
2. It is also possible to reserve a certain address using 'reserveFor'. 
    When such investor invests, the place becomes unreserved  */
contract ParticipantInvestRestrictions is FloorInvestRestrictions {

    struct ReservedInvestor {
        bool reserved;        
        uint256 tokens;
    }

    event ReserveKnown(bool state, address investor, uint256 weiAmount, uint256 tokens);
    event ReserveUnknown(bool state, uint32 index, uint256 weiAmount, uint256 tokens);

    /**@dev Array of unknown investors */
    ReservedInvestor[] public unknownInvestors;

    /**@dev Formula to calculate amount of tokens to buy*/
    ICrowdsaleFormula public formula;

    /**@dev Maximum number of allowed investors */
    uint32 public maxInvestors;    

    /**@dev Current number of investors */
    uint32 public investorsCount;

    /**@dev Current number of known reserved investors */
    uint32 public knownReserved;

    /**@dev Current number of unknown reserved investors */
    uint32 public unknownReserved;

    /**@dev If address is reserved, shows how much tokens reserved for him */
    mapping (address => uint256) public reservedInvestors;

    /**@dev How much tokens reserved */
    uint256 public tokensReserved;

    function ParticipantInvestRestrictions(uint256 _floor, uint32 _maxTotalInvestors)
        FloorInvestRestrictions(_floor)
    {
        maxInvestors = _maxTotalInvestors;
    }

    /**@dev Sets formula */
    function setFormula(ICrowdsaleFormula _formula) managerOnly {
        formula = _formula;        
    }

    /**@dev Returns true if there are still free places for investors */
    function hasFreePlaces() constant returns (bool) {
        return getInvestorCount() < maxInvestors;
    }

    /**@dev Returns number of investors, including reserved */
    function getInvestorCount() constant returns(uint32) {
        return investorsCount + knownReserved + unknownReserved;
    }

    /**@dev IInvestRestrictions override */
    function canInvest(address investor, uint amount, uint tokensLeft) constant returns (bool result) {
        //First check ancestor's restriction. 
        //Allow only if it is reserved investor or it invested earlier or there is still room for new investors
        if (super.canInvest(investor, amount, tokensLeft)) {
            if (reservedInvestors[investor] > 0) {
                return true;
            } else {
                var (tokens, excess) = formula.howManyTokensForEther(amount);
                if (tokensLeft >= tokensReserved + tokens) {
                    return investors[investor] || hasFreePlaces();
                }
            }
        }

        return false;
    }
 
    /**@dev IInvestRestrictions override */
    function investHappened(address investor, uint amount) managerOnly {
        if (!investors[investor]) {
            investors[investor] = true;
            investorsCount++;
            
            //if that investor was already reserved, unreserve the place
            if (reservedInvestors[investor] > 0) {
                unreserveFor(investor);
            }
        }
    }

    /**@dev Reserves a place for investor */
    function reserveFor(address investor, uint256 weiAmount) managerOnly {
        require(!investors[investor] && hasFreePlaces());

        uint256 tokenAmount = reserveTokens(weiAmount);
        require(tokenAmount > 0);

        if(reservedInvestors[investor] == 0) {
            knownReserved++;
        }

        reservedInvestors[investor] += tokenAmount;
        ReserveKnown(true, investor, weiAmount, reservedInvestors[investor]);
    }

    /**@dev Unreserves special address. For example if investor haven't sent ether */
    function unreserveFor(address investor) managerOnly {
        require(reservedInvestors[investor] != 0);

        knownReserved--;
        unreserveTokens(reservedInvestors[investor]);
        reservedInvestors[investor] = 0;

        ReserveKnown(false, investor, 0, 0);
    }

    /**@dev Reserves place for unknown address */
    function reserve(uint256 weiAmount) managerOnly {
        require(hasFreePlaces());
        unknownReserved++;
        uint32 id = uint32(unknownInvestors.length++);
        unknownInvestors[id].reserved = true;        
        unknownInvestors[id].tokens = reserveTokens(weiAmount);

        ReserveUnknown(true, id, weiAmount, unknownInvestors[id].tokens);
    }

    /**@dev Unreserves place for unknown address specified by an index in array */
    function unreserve(uint32 index) managerOnly {
        require(index < unknownInvestors.length && unknownInvestors[index].reserved);
        
        assert(unknownReserved > 0);
        unknownReserved--;
        unreserveTokens(unknownInvestors[index].tokens);        
        unknownInvestors[index].reserved = false;

        ReserveUnknown(false, index, 0, 0);
    }

    /**@dev Reserved tokens for given amount of ether, returns reserved amount */
    function reserveTokens(uint256 weiAmount) 
        internal 
        managerOnly 
        returns(uint256) 
    {
        uint256 tokens;
        uint256 excess;
        (tokens, excess) = formula.howManyTokensForEther(weiAmount);
        
        if (tokensReserved + tokens > formula.tokensLeft()) {
            tokens = formula.tokensLeft() - tokensReserved;
        }
        tokensReserved += tokens;

        return tokens;
    }

    /**@dev Unreserves specified amount of tokens */
    function unreserveTokens(uint256 tokenAmount) 
        internal 
        managerOnly 
    {
        if (tokenAmount > tokensReserved) {
            tokensReserved = 0;
        } else {
            tokensReserved = tokensReserved - tokenAmount;
        }
    }
}