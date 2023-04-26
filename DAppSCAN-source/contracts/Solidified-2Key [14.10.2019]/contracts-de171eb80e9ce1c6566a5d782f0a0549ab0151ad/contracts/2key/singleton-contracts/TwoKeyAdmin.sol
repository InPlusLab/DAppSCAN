pragma solidity ^0.4.24;

import "../interfaces/IERC20.sol";
import "../interfaces/ITwoKeyReg.sol";
import "../upgradability/Upgradeable.sol";
import "./ITwoKeySingletonUtils.sol";
import "../interfaces/storage-contracts/ITwoKeyAdminStorage.sol";

//TODO: Add all the missing functions from other singletones which can be called by TwoKeyAdmin
contract TwoKeyAdmin is Upgradeable, ITwoKeySingletonUtils {

	bool initialized = false;

	ITwoKeyAdminStorage public PROXY_STORAGE_CONTRACT;
	address public twoKeyCongress;
	address twoKeyEconomy;


    /// @notice Modifier will revert if calling address is not a member of electorateAdmins
	modifier onlyTwoKeyCongress {
		require(msg.sender == twoKeyCongress);
	    _;
	}

    /// @notice Modifier will revert if caller is not TwoKeyUpgradableExchange
    modifier onlyTwoKeyUpgradableExchange {
		address twoKeyUpgradableExchange = getAddressFromTwoKeySingletonRegistry("TwoKeyUpgradableExchange");
        require(msg.sender == address(twoKeyUpgradableExchange));
        _;
    }

    /**
     * @notice Function to set initial parameters in the contract including singletones
     * @param _twoKeyCongress is the address of TwoKeyCongress
     * @param _economy is the address of TwoKeyEconomy
     * @dev This function can be called only once, which will be done immediately after deployment.
     */
    function setInitialParams(
		address _twoKeySingletonRegistry,
		address _proxyStorageContract,
        address _twoKeyCongress,
        address _economy,
		uint _twoKeyTokenReleaseDate
    ) external {
        require(initialized == false);

		TWO_KEY_SINGLETON_REGISTRY = _twoKeySingletonRegistry;
		PROXY_STORAGE_CONTRACT = ITwoKeyAdminStorage(_proxyStorageContract);
		twoKeyCongress = _twoKeyCongress;
		twoKeyEconomy = _economy;

		setUint("twoKeyIntegratorDefaultFeePercent",2);
		setUint("twoKeyNetworkTaxPercent",2);
		setUint("twoKeyTokenRate", 95);
		setUint("rewardReleaseAfter",_twoKeyTokenReleaseDate);

        initialized = true;
    }

    /// @notice Function where only elected admin can transfer tokens to an address
    /// @dev We're recurring to address different from address 0 and token amount greater than 0
    /// @param _to receiver's address
    /// @param _tokens is token amounts to be transfers
	function transferByAdmins(
		address _to,
		uint256 _tokens
	)
	external
	onlyTwoKeyCongress
	{
		require (_to != address(0));
		IERC20(twoKeyEconomy).transfer(_to, _tokens);
	}

    /// @notice Function where only elected admin can transfer ether to an address
    /// @dev We're recurring to address different from address 0 and amount greater than 0
    /// @param to receiver's address
    /// @param amount of ether to be transferred
	function transferEtherByAdmins(
		address to,
		uint256 amount
	)
	external
	onlyTwoKeyCongress
	{
		require(to != address(0));
		to.transfer(amount);
	}

    /// @notice Function will transfer contract balance to owner if contract was never replaced else will transfer the funds to the new Admin contract address
	function destroy()
	public
	onlyTwoKeyCongress
	{
        selfdestruct(twoKeyCongress);
	}

    /// @notice Function to add/update name - address pair from twoKeyAdmin
	/// @param _name is name of user
	/// @param _addr is address of user
    function addNameToReg(
		string _name,
		address _addr,
		string fullName,
		string email,
		bytes signature
	) external {
		address twoKeyRegistry = getAddressFromTwoKeySingletonRegistry("TwoKeyRegistry");
    	ITwoKeyReg(twoKeyRegistry).addName(_name, _addr, fullName, email, signature);
    }


	/// @notice Function to freeze all transfers for 2KEY token
	function freezeTransfersInEconomy()
	external
	onlyTwoKeyCongress
	{
		IERC20(address(twoKeyEconomy)).freezeTransfers();
	}

	/// @notice Function to unfreeze all transfers for 2KEY token
	function unfreezeTransfersInEconomy()
	external
	onlyTwoKeyCongress
	{
		IERC20(address(twoKeyEconomy)).unfreezeTransfers();
	}

	// Function to transfer 2key tokens
    function transfer2KeyTokens(
		address _to,
		uint256 _amount
	)
	public
	onlyTwoKeyCongress
	returns (bool)
	{
		bool completed = IERC20(twoKeyEconomy).transfer(_to, _amount);
		return completed;
	}

	// Public wrapper method
	function getUint(
		string key
	)
	internal
	view
	returns (uint)
	{
		return PROXY_STORAGE_CONTRACT.getUint(keccak256(key));
	}

	// Internal wrapper method
	function setUint(
		string key,
		uint value
	)
	internal
	{
		PROXY_STORAGE_CONTRACT.setUint(keccak256(key), value);
	}

	function getTwoKeyRewardsReleaseDate()
	external
	view
	returns(uint)
	{
		return getUint("rewardReleaseAfter");
	}


	function getDefaultIntegratorFeePercent()
	public
	view
	returns (uint)
	{
		return getUint("twoKeyIntegratorDefaultFeePercent");
	}


	function getDefaultNetworkTaxPercent()
	public
	view
	returns (uint)
	{
		return getUint("twoKeyNetworkTaxPercent");
	}


	function getTwoKeyTokenRate()
	public
	view
	returns (uint)
	{
		return getUint("twoKeyTokenRate");
	}


	/// @notice Fallback function will transfer payable value to new admin contract if admin contract is replaced else will be stored this the exist admin contract as it's balance
	/// @dev A payable fallback method
	function()
	external
	payable
	{

	}


}
