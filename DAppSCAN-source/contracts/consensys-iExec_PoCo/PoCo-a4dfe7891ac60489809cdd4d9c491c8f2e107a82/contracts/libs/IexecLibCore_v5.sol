pragma solidity ^0.6.0;


library IexecLibCore_v5
{
	/**
	* Tools
	*/
	struct Account
	{
		uint256 stake;
		uint256 locked;
	}
	struct Category
	{
		string  name;
		string  description;
		uint256 workClockTimeRef;
	}

	/**
	 * Clerk - Deals
	 */
	struct Resource
	{
		address pointer;
		address owner;
		uint256 price;
	}
	struct Deal
	{
		// Ressources
		Resource app;
		Resource dataset;
		Resource workerpool;
		uint256 trust;
		uint256 category;
		bytes32 tag;
		// execution details
		address requester;
		address beneficiary;
		address callback;
		string  params;
		// execution settings
		uint256 startTime;
		uint256 botFirst;
		uint256 botSize;
		// consistency
		uint256 workerStake;
		uint256 schedulerRewardRatio;
	}

	/**
	 * Tasks
	 */
	enum TaskStatusEnum
	{
		UNSET,     // Work order not yet initialized (invalid address)
		ACTIVE,    // Marketed → constributions are open
		REVEALING, // Starting consensus reveal
		COMPLETED, // Concensus achieved
		FAILLED    // Failled consensus
	}
	struct Task
	{
		TaskStatusEnum status;
		bytes32   dealid;
		uint256   idx;
		uint256   timeref;
		uint256   contributionDeadline;
		uint256   revealDeadline;
		uint256   finalDeadline;
		bytes32   consensusValue;
		uint256   revealCounter;
		uint256   winnerCounter;
		address[] contributors;
		bytes32   resultDigest;
		bytes     results;
		uint256   resultsTimestamp;
	}

	/**
	 * Consensus
	 */
	struct Consensus
	{
		mapping(bytes32 => uint256) group;
		uint256                     total;
	}

	/**
	 * Consensus
	 */
	enum ContributionStatusEnum
	{
		UNSET,
		CONTRIBUTED,
		PROVED,
		REJECTED
	}
	struct Contribution
	{
		ContributionStatusEnum status;
		bytes32 resultHash;
		bytes32 resultSeal;
		address enclaveChallenge;
		uint256 weight;
	}

}
