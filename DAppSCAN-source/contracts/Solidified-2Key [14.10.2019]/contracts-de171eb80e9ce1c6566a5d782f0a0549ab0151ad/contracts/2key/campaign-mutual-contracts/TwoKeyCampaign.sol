pragma solidity ^0.4.24;

import "../interfaces/ITwoKeySingletoneRegistryFetchAddress.sol";
import "../interfaces/IUpgradableExchange.sol";
import "../interfaces/IERC20.sol";

import "../singleton-contracts/TwoKeyEventSource.sol";
import "../libraries/SafeMath.sol";
import "../libraries/Call.sol";
import "./ArcERC20.sol";

/**
 * @title Contract which describes all 2key campaigns
 * @author Nikola Madjarevic (https://github.com/madjarevicn)
 */
contract TwoKeyCampaign is ArcERC20 {

	using SafeMath for uint256;
	using Call for *;

	TwoKeyEventSource twoKeyEventSource; // Address of TwoKeyEventSource contract

	address twoKeySingletonesRegistry; // Address of Registry of all singleton contracts
	address twoKeyEconomy; // Address of twoKeyEconomy contract
	address ownerPlasma; //contractor plasma address

	address public contractor; //contractor address
	address public moderator; //moderator address

	bool isKYCRequired;
    bool mustConvertToReferr;

	uint256 conversionQuota;  // maximal ARC tokens that can be passed in transferFrom
	uint256 contractorBalance; // Contractor balance
	uint256 contractorTotalProceeds; // Contractor total earnings
	uint256 maxReferralRewardPercent; // maxReferralRewardPercent is actually bonus percentage in ETH
	uint256 moderatorTotalEarnings2key; //Total earnings of the moderator all time
	uint256 reservedAmount2keyForRewards; //Reserved amount of 2key tokens for rewards distribution


	string public publicMetaHash; // Ipfs hash of json campaign object
	string public privateMetaHash; // Ipfs hash of json sensitive (contractor) information

	mapping(address => uint256) internal referrerPlasma2Balances2key; // balance of EthWei for each influencer that he can withdraw

	mapping(address => address) public public_link_key;
	mapping(address => address) internal received_from; // referral graph, who did you receive the referral from

    // @notice Modifier which allows only contractor to call methods
    modifier onlyContractor() {
        require(msg.sender == contractor);
        _;
    }

	/**
     * @dev Transfer tokens from one address to another
     * @param _from address The address which you want to send tokens from ALREADY converted to plasma
     * @param _to address The address which you want to transfer to ALREADY converted to plasma
     * @param _value uint256 the amount of tokens to be transferred
     */
	function transferFrom(
		address _from,
		address _to,
		uint256 _value
	)
	internal
	returns (bool)
	{
		// _from and _to are assumed to be already converted to plasma address (e.g. using plasmaOf)
		require(_value == 1);
		require(balances[_from] > 0);

		balances[_from] = balances[_from].sub(1);
		balances[_to] = balances[_to].add(conversionQuota);
		totalSupply_ = totalSupply_.add(conversionQuota.sub(1));

		if (received_from[_to] == 0) {
			twoKeyEventSource.joined(this, _from, _to);
		}

		received_from[_to] = _from;
		return true;
	}


    /**
     * @notice Private function to set public link key to plasma address
     * @param me is the ethereum address
     * @param new_public_key is the new key user want's to set as his public key
     */
    function setPublicLinkKeyOf(
		address me,
		address new_public_key
	)
	internal
	{
        me = twoKeyEventSource.plasmaOf(me);
        require(balanceOf(me) > 0);
        address old_address = public_link_key[me];
        if (old_address == address(0)) {
            public_link_key[me] = new_public_key;
        } else {
            require(old_address == new_public_key);
        }
        public_link_key[me] = new_public_key;
    }


	/**
 	 * @notice Function which will unpack signature and get referrers, keys, and weights from it
 	 * @param sig is signature
 	 */
	function getInfluencersKeysAndWeightsFromSignature(
		bytes sig,
		address _converter
	)
	internal
	returns (address[],address[],uint8[],address)
	{
		// move ARCs and set public_link keys and weights/cuts based on signature information
		// returns the last address in the sig

		// sig structure:
		// 1 byte version 0 or 1
		// 20 bytes are the address of the contractor or the influencer who created sig.
		//  this is the "anchor" of the link
		//  It must have a public key aleady stored for it in public_link_key
		// Begining of a loop on steps in the link:
		// * 65 bytes are step-signature using the secret from previous step
		// * message of the step that is going to be hashed and used to compute the above step-signature.
		//   message length depend on version 41 (version 0) or 86 (version 1):
		//   * 1 byte cut (percentage) each influencer takes from the bounty. the cut is stored in influencer2cut or weight for voting
		//   * 20 bytes address of influencer (version 0) or 65 bytes of signature of cut using the influencer address to sign
		//   * 20 bytes public key of the last secret
		// In the last step the message can be optional. If it is missing the message used is the address of the sender
		address old_address;
		/**
           old address -> plasma address
           old key -> publicLinkKey[plasma]
         */
		assembly
		{
			old_address := mload(add(sig, 21))
		}

		old_address = twoKeyEventSource.plasmaOf(old_address);
		address old_key = public_link_key[old_address];

		address[] memory influencers;
		address[] memory keys;
		uint8[] memory weights;
		(influencers, keys, weights) = Call.recoverSig(sig, old_key, twoKeyEventSource.plasmaOf(_converter));

		// check if we exactly reached the end of the signature. this can only happen if the signature
		// was generated with free_join_take and in this case the last part of the signature must have been
		// generated by the caller of this method
		require(// influencers[influencers.length-1] == msg.sender ||
			influencers[influencers.length-1] == twoKeyEventSource.plasmaOf(_converter) ||
			contractor == msg.sender
		);

		return (influencers, keys, weights, old_address);
	}

    /**
     * @notice Function to set public link key
     * @param new_public_key is the new public key
     */
    function setPublicLinkKey(
		address new_public_key
	)
	public
	{
        setPublicLinkKeyOf(msg.sender, new_public_key);
    }


	/**
     * @notice Function to set or update public meta hash
     * @param _publicMetaHash is the hash of the campaign
     * @dev Only contractor can call this
     */
	function startCampaignWithInitialParams(
		string _publicMetaHash,
		string _privateMetaHash,
		address new_public_key
	)
	public
	onlyContractor
	{
		//TODO: Handle option to update only one of 3 and other setters
		publicMetaHash = _publicMetaHash;
		privateMetaHash = _privateMetaHash;
		setPublicLinkKeyOf(msg.sender, new_public_key);
	}


	/**
 	 * @notice Private function which will be executed at the withdraw time to buy 2key tokens from upgradable exchange contract
 	 * @param amountOfMoney is the ether balance person has on the contract
 	 * @param receiver is the address of the person who withdraws money
 	 */
	function buyTokensFromUpgradableExchange(
		uint amountOfMoney,
		address receiver
	)
	internal
	returns (uint)
	{
		address upgradableExchange = getContractProxyAddress("TwoKeyUpgradableExchange");
		uint amountBought = IUpgradableExchange(upgradableExchange).buyTokens.value(amountOfMoney)(receiver);
		return amountBought;
	}


	/**
     * @notice Getter for the referral chain
     * @param _receiver is address we want to check who he has received link from
     */
	function getReceivedFrom(
		address _receiver
	)
	public
	view
	returns (address)
	{
		return received_from[_receiver];
	}

	/**
     * @notice Function to get public link key of an address
     * @param me is the address we're checking public link key
     */
	function publicLinkKeyOf(
		address me
	)
	public
	view
	returns (address)
	{
		return public_link_key[twoKeyEventSource.plasmaOf(me)];
	}

    /**
     * @notice Function to return the constants from the contract
     */
    function getConstantInfo()
	public
	view
	returns (uint,uint,bool)
	{
        return (conversionQuota, maxReferralRewardPercent, isKYCRequired);
    }

    /**
     * @notice Function to fetch moderator balance in ETH and his total earnings
     * @dev only contractor or moderator are eligible to call this function
     * @return value of his balance in ETH
     */
    function getModeratorTotalEarnings()
	public
	view
	returns (uint)
	{
        return (moderatorTotalEarnings2key);
    }

    /**
     * @notice Function to fetch contractor balance in ETH
     * @dev only contractor can call this function, otherwise it will revert
     * @return value of contractor balance in ETH WEI
     */
    function getContractorBalanceAndTotalProceeds()
	external
	onlyContractor
	view
	returns (uint,uint)
	{
        return (contractorBalance, contractorTotalProceeds);
    }


    /**
     * @notice Function where contractor can withdraw his funds
     * @dev onlyContractor can call this method
     * @return true if successful otherwise will 'revert'
     */
    function withdrawContractor()
	public
	onlyContractor
	{
        uint balance = contractorBalance;
        contractorBalance = 0;
        /**
         * In general transfer by itself prevents against reentrancy attack since it will throw if more than 2300 gas
         * but however it's not bad to practice this pattern of firstly reducing balance and then doing transfer
         */
        contractor.transfer(balance);
    }

	function getContractProxyAddress(string contractName) internal returns (address) {
		return ITwoKeySingletoneRegistryFetchAddress(twoKeySingletonesRegistry).getContractProxyAddress(contractName);
	}


	/**
 	 * @notice Function where moderator or referrer can withdraw their available funds
 	 * @param _address is the address we're withdrawing funds to
 	 * @dev It can be called by the address specified in the param or by the one of two key maintainers
 	 */
	function referrerWithdraw(
		address _address,
		bool _withdrawAsStable
	)
	public
	{
		require(msg.sender == _address || twoKeyEventSource.isAddressMaintainer(msg.sender));
		address twoKeyAdminAddress;
		address twoKeyUpgradableExchangeContract;

		uint balance;
		address _referrer = twoKeyEventSource.plasmaOf(_address);

		if(referrerPlasma2Balances2key[_referrer] != 0) {
			twoKeyAdminAddress = getContractProxyAddress("TwoKeyAdmin");
			twoKeyUpgradableExchangeContract = getContractProxyAddress("TwoKeyUpgradableExchange");

			balance = referrerPlasma2Balances2key[_referrer];
			referrerPlasma2Balances2key[_referrer] = 0;

			if(_withdrawAsStable == true) {
				IERC20(twoKeyEconomy).approve(twoKeyUpgradableExchangeContract, balance);
				IUpgradableExchange(twoKeyUpgradableExchangeContract).buyStableCoinWith2key(balance, _address);
			}
			else if (block.timestamp >= ITwoKeyAdmin(twoKeyAdminAddress).getTwoKeyRewardsReleaseDate()) {
				IERC20(twoKeyEconomy).transfer(_address, balance);
			}
			else {
				revert();
			}

		}
        reservedAmount2keyForRewards -= balance;
	}
}

