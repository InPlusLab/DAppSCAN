pragma solidity ^0.4.24;
import './TwoKeyContract.sol';
import './TwoKeySignedContract.sol';
import '../../contracts/2key/libraries/Call.sol';

contract TwoKeyWeightedVoteContract is TwoKeySignedPresellContract {
  constructor(TwoKeyReg _reg, TwoKeyEventSource _eventSource, string _name, string _symbol,
    uint256 _tSupply, uint256 _quota, uint256 _cost, uint256 _bounty,
    string _ipfs_hash, StandardToken _erc20_token_sell_contract)
  public
  TwoKeySignedPresellContract(_reg,_eventSource,_name,_symbol,_tSupply,_quota,_cost,_bounty,_ipfs_hash,_erc20_token_sell_contract)
  {
  }

  mapping(address => uint)  public voted_weight;
  mapping(address => bool)  public voted;
  uint public voted_yes;
  uint public voted_no;
  uint public total_vote;  // this can be bigger than voted_yes+voted_no because of abstain votes
  uint public weighted_yes;
  uint public weighted_no;
  int public total_weight;  // this can be bigger than weighted_yes+weighted_no because of lack of voting coins


  function transferSig(bytes sig) public returns (address[]) {
    // must use a sig which includes a cut (ie by calling free_join_take in sign.js
    require((sig.length-21) % (65+1+65+20) == 0, 'signature is not version 1 and/or does not include cut of last vote');
    // validate sig AND populate received_from and influencer2cut
    address[] memory voters = super.transferSig(sig);

    for (uint i = 0; i < voters.length; i++) {
      address influencer = voters[i];

      // extract the vote (yes/no) and the weight of the vote from cut
      uint256 cut = cutOf(influencer);
      bool new_votter = !voted[influencer];
      voted[influencer] = true;
      if (new_votter) {
        total_vote++;
      }
      bool yes;
      uint256 weight;
      if (0 < cut && cut <= 101) {
        yes = true;
        if (new_votter) {
          voted_yes++;
        }
        weight = cut-1;
      } else if (154 < cut && cut < 255) {
        yes = false;
        if (new_votter) {
          voted_no++;
        }
        weight = 255-cut;
      } else { // if cut == 255 then abstain
        weight = 0;
      }
      if (new_votter) {
        if (yes) {
          total_weight += int(weight);
        } else {
          total_weight -= int(weight);
        }
      }
      weight -= voted_weight[influencer];

      if (weight > 0) {
        uint tokens = weight.mul(cost);
        // make sure weight is not more than number of coins influencer has
        uint _units = Call.params1(erc20_token_sell_contract, "balanceOf(address)",uint(ethereumOf(influencer)));
        if (_units < tokens) {
          tokens = _units;
        }
        // make sure weight is not more than what coins allows this contract to take
        uint _allowance = Call.params2(erc20_token_sell_contract, "allowance(address,address)",uint(ethereumOf(influencer)),uint(this));
        if (_allowance < tokens) {
          tokens = _allowance;
        }
        // vote
        if (tokens > 0) {
          weight = tokens.div(cost);
          if (yes) {
            weighted_yes += weight;
          } else {
            weighted_no += weight;
          }
          voted_weight[influencer] += weight;

          // TODO its always a good idea to have external calls the last statement in code
          // transfer coins from influncer to the contract in the amount of the weight used for voting
          transferCoins(voters, i, tokens);
        }
      }
    }

    return voters;
  }

  function sqrt(uint x) public pure returns (uint y) {
    uint z = x.add(1).div(2);
    y = x;
    while (z < y) {
      y = z;
      z = x.div(z).add(z).div(2);
    }
  }

  function transferCoins(address[] voters, uint i, uint tokens) private {
    // send all tokens to this contract
    // send sone tokens as bounty from the contract back to influencers
    // any tokens left in the contract are lost forever
    address influencer = voters[i];
    require(address(erc20_token_sell_contract).call(bytes4(keccak256("transferFrom(address,address,uint256)")),
      ethereumOf(influencer), address(this), tokens));

    xbalances[owner_plasma] += tokens;

    // distribute some of the tokens back from the contract to the influencers
    for (uint j = 0; j < i; j++) {
      uint k = i - 1 - j;
      // We want to take the square root of the weight but not of cost.
      // tokens = weight*cost
      // sqrt(tokens*cost) = sqrt(weight*cost*cost) = sqrt(weight) * cost
      tokens = sqrt(tokens.mul(cost));
      if (tokens==0) {
        break;
      }
      address voter = voters[k];
      xbalances[plasmaOf(voter)] += tokens;
      xbalances[owner_plasma] -= tokens;

      require(address(erc20_token_sell_contract).call(bytes4(keccak256("transferFrom(address,address,uint256)")),
          this, ethereumOf(voters[k]), tokens),"failed to send coins");
    }
  }

  function redeem() public {
    revert("redeem not implemented");
  }

  function buyProduct() public payable {
    revert("buyProduct not implemented");
  }

  function votes() public view returns (uint256, uint256, uint256, uint256, uint256, int) {
    return (voted_yes, weighted_yes, voted_no, weighted_no, total_vote, total_weight);
  }
}
