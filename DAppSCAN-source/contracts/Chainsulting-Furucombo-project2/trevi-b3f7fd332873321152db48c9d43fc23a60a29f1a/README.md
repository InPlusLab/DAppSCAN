# Trevi
Trevi is an ERC20-based staking system. 

# Usage
## Archangel
Archangel records the relationship between [Fountains](#fountains) and [Angels](#angels), and manages the configuration of flash loan related functions.
## Fountains
Fountains are the places people toss their coin, wishing for good fortune. Users may stake their assets in the corresponding fountain and receive the blessings from [Angels](#angels).
### FountainFactory
Only the fountain that is created from FountainFactory can be applied in Trevi. Each token can only have one fountain being created. Anyone can create a fountion for a token.
### Fountain
Assets being staked by users are kept in Fountain. 
#### Join / Quit angel
Users may choose the angel they want to join to receive the rewards. The stakings will be applied to all the joined angels equally.
#### Deposit / Withdraw / Harvest
User may deposit their assets in fountain. When user deposits the token, corresponding FTN token will be minted by fountain to the user. The token represent the ownership of the stakings and can be transferred. When user withdraws, the rewards of the withdrawn token will be recorded for the later harvest. The rewards from joined angels can be received by Harvest.
#### FlashLoan
The assets in the fountain can be flashLoaned by user, which is implemented through [ERC-3156](https://eips.ethereum.org/EIPS/eip-3156). The fee rate is set through [Archangel](#archangel), and fee can be aquired by [Archangel](#archangel).
## Angels
Angels give their blessings to people. Rewarders may manage their rewards schedule and configuration through angel.
### AngelFactory
Only the angel that is created from AngelFactory can be applied in Trevi. Each token can have multiple angels being created. Anyone can create an angel.
### Angel
Angel is a forked version of [MiniChefV2](https://github.com/sushiswap/sushiswap/blob/canary/contracts/MiniChefV2.sol) from [Sushiswap](https://github.com/sushiswap/sushiswap). All the functions remain the same except:
- Staking tokens are located in fountain.
- Deposit / Withdraw / Harvest / EmergencyWithdraw can only be called from corresponding fountain.
- Migrate related functions and harvestAndWithdraw are removed.

#### FlashLoan
The assets in the angel can be flashLoaned by user, which is implemented through [ERC-3156](https://eips.ethereum.org/EIPS/eip-3156). The fee rate is set through [Archangel](#archangel), and fee is collected at [Archangel](#archangel). 
