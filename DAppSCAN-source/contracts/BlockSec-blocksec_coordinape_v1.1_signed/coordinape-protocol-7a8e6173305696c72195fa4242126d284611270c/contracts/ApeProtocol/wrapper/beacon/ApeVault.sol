// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.2;

import "../../../../interfaces/IApeVault.sol";
import "../../ApeDistributor.sol";
import "../../ApeAllowanceModule.sol";
import "../../ApeRegistry.sol";
import "../../FeeRegistry.sol";
import "../../ApeRouter.sol";

import "./BaseWrapperImplementation.sol";

abstract contract OwnableImplementation {
    address internal _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract ApeVaultWrapperImplementation is BaseWrapperImplementation, OwnableImplementation {
	using SafeERC20 for VaultAPI;
	using SafeERC20 for IERC20;

	uint256 constant TOTAL_SHARES = 10000;
	
	IERC20 public simpleToken;
	// SWC-135-Code With No Effects: L64
	mapping(address => bool) public hasAccess;

	bool internal setup;
	uint256 public underlyingValue;
	address public apeRegistry;
	VaultAPI public vault;
	// SWC-135-Code With No Effects: L71
	ApeAllowanceModule public allowanceModule;

	function init(
		address _apeRegistry,
		address _token,
		address _registry,
		address _simpleToken,
		address _newOwner) external {
		require(!setup);
		setup = true;
		apeRegistry = _apeRegistry;
		if (_token != address(0))
			vault = VaultAPI(RegistryAPI(_registry).latestVault(_token));
		simpleToken = IERC20(_simpleToken);

		// Recommended to use a token with a `Registry.latestVault(_token) != address(0)`
        token = IERC20(_token);
        // Recommended to use `v2.registry.ychad.eth`
        registry = RegistryAPI(_registry);
		_owner = _newOwner;
        emit OwnershipTransferred(address(0), _newOwner);
	}

	event ApeVaultFundWithdrawal(address indexed apeVault, address vault, uint256 _amount, bool underlying);

	modifier onlyDistributor() {
		require(msg.sender == ApeRegistry(apeRegistry).distributor());
		_;
	}

	modifier onlyRouter() {
		require(msg.sender == ApeRegistry(apeRegistry).router());
		_;
	}

	function _shareValue(uint256 numShares) internal view returns (uint256) {
		return vault.pricePerShare() * numShares / (10**uint256(vault.decimals()));
    }

    function _sharesForValue(uint256 amount) internal view returns (uint256) {
		return amount * (10**uint256(vault.decimals())) / vault.pricePerShare();
    }

	/**  
	 * @notice
	 * Used to measure profits made compared to funds send to the vault
	 * Returns 0 if negative
	 */
	function profit() public view returns(uint256) {
		uint256 totalValue = _shareValue(vault.balanceOf(address(this)));
		if (totalValue <= underlyingValue)
			return 0;
		else
			return totalValue - underlyingValue;
	}

	/**  
	 * @notice
	 * Used to withdraw non yield bearing tokens
	 * @param _amount Amount of simpleToken to withdraw
	 */
	// SWC-105-Unprotected Ether Withdrawal: L133-135
	function apeWithdrawSimpleToken(uint256 _amount) public {
		simpleToken.safeTransfer(msg.sender, _amount);
	}

	/**  
	 * @notice
	 * Used to withdraw yield bearing token
	 * @param _shareAmount Amount of yield bearing token to withdraw
	 * @param _underlying boolean to know if we redeem shares or not
	 */
	function apeWithdraw(uint256 _shareAmount, bool _underlying) external onlyOwner {
		uint256 underlyingAmount = _shareValue(_shareAmount);
		require(underlyingAmount <= underlyingValue, "underlying amount higher than vault value");

		address router = ApeRegistry(apeRegistry).router();
		underlyingValue -= underlyingAmount;
		vault.transfer(router, _shareAmount);
		ApeRouter(router).delegateWithdrawal(owner(), address(this), vault.token(), _shareAmount, _underlying);
	}

	/**  
	 * @notice
	 * Used to withdraw all yield bearing token
	 * @param _underlying boolean to know if we redeem shares or not
	 */
	function exitVaultToken(bool _underlying) external onlyOwner {
		underlyingValue = 0;
		uint256 totalShares = vault.balanceOf(address(this));
		address router = ApeRegistry(apeRegistry).router();
		vault.transfer(router, totalShares);
		ApeRouter(router).delegateWithdrawal(owner(), address(this), vault.token(), totalShares, _underlying);
	}

	/**  
	 * @notice
	 * Used to migrate yearn vault
	 */
	function apeMigrate() external onlyOwner returns(uint256 migrated){
		migrated = _migrate(address(this));
		vault = VaultAPI(registry.latestVault(address(token)));
	}

	/**  
	 * @notice
	 * Used to take funds from vault into the distributor (can only be called by distributor)
	 * @param _value Amount of funds to take
	 * @param _type The type of tap performed on the vault
	 */
	function tap(uint256 _value, uint8 _type) external onlyDistributor returns(uint256) {
		if (_type == uint8(0)) {
			_tapOnlyProfit(_value, msg.sender);
			return _value;
		}
		else if (_type == uint8(1)) {
			_tapBase(_value, msg.sender);
			return _value;
		}
		else if (_type == uint8(2))
			_tapSimpleToken(_value, msg.sender);
		return (0);
	}


	/**  
	 * @notice
	 * Used to take funds from vault purely from profit made from yearn yield
	 * @param _tapValue Amount of funds to take
	 * @param _recipient recipient of funds (always distributor)
	 */
	function _tapOnlyProfit(uint256 _tapValue, address _recipient) internal {
		uint256 fee = FeeRegistry(ApeRegistry(apeRegistry).feeRegistry()).getVariableFee(_tapValue, _tapValue);
		uint256 finalTapValue = _tapValue + _tapValue * fee / TOTAL_SHARES;
		require(_shareValue(finalTapValue) <= profit(), "Not enough profit to cover epoch");
		vault.safeTransfer(_recipient, _tapValue);
		vault.safeTransfer(ApeRegistry(apeRegistry).treasury(), _tapValue * fee / TOTAL_SHARES);
	}

	/**  
	 * @notice
	 * Used to take funds from vault by deducting a part from profits
	 * @param _tapValue Amount of funds to take
	 * @param _recipient recipient of funds (always distributor)
	 */
	function _tapBase(uint256 _tapValue, address _recipient) internal {
		uint256 underlyingTapValue = _shareValue(_tapValue);
		uint256 profit_ = profit();
		uint256 fee = FeeRegistry(ApeRegistry(apeRegistry).feeRegistry()).getVariableFee(profit_, underlyingTapValue);
		uint256 finalTapValue = underlyingTapValue + underlyingTapValue * fee / TOTAL_SHARES;
		if (finalTapValue > profit_)
			underlyingValue -= finalTapValue - profit_;
		vault.transfer(_recipient, _tapValue);
		vault.transfer(ApeRegistry(apeRegistry).treasury(), _tapValue * fee / TOTAL_SHARES);
	}

	/**  
	 * @notice
	 * Used to take funds simple token
	 * @param _tapValue Amount of funds to take
	 * @param _recipient recipient of funds (always distributor)
	 */
	function _tapSimpleToken(uint256 _tapValue, address _recipient) internal {
		uint256 feeAmount = _tapValue * FeeRegistry(ApeRegistry(apeRegistry).feeRegistry()).staticFee() / TOTAL_SHARES;
		simpleToken.transfer(_recipient, _tapValue);
		simpleToken.transfer(ApeRegistry(apeRegistry).treasury(), feeAmount);
	}

	/**  
	 * @notice
	 * Used to correct change the amount of underlying funds held by the ape Vault
	 */
	function syncUnderlying() external onlyOwner {
		underlyingValue = _shareValue(vault.balanceOf(address(this)));
	}

	/**  
	 * @notice
	 * Used to add the correct amount of funds from the router, only callable by router
	 * @param _amount amount of undelrying funds to add
	 */
	function addFunds(uint256 _amount) external onlyRouter {
		underlyingValue += _amount;
	}

	/**  
	 * @notice
	 * Used to approve an admin to fund/finalise epochs from this vault to a specific circle
	 * @param _circle Circle who will benefit from this vault
	 * @param _admin address that can finalise epochs
	 */
	function updateCircleAdmin(bytes32 _circle, address _admin) external onlyOwner {
		ApeDistributor(ApeRegistry(apeRegistry).distributor()).updateCircleAdmin(_circle, _admin);
	}

	/**  
	 * @notice
	 * Used to update the allowance of a circle that the vault funds
	 * @param _circle Circle who will benefit from this vault
	 * @param _amount Max amount of funds available per epoch
	 * @param _interval Seconds in between each epochs
	 * @param _epochAmount Amount of epochs to fund (0 means you're at least funding one epoch)
	 * If you want to stop funding a circle, set _amount to 0
	 * @param _intervalStart Unix timestamp fromw hich epoch starts (block.timestamp if 0)
	 */
	function updateAllowance(
		bytes32 _circle,
		address _token,
		uint256 _amount,
		uint256 _interval,
		uint256 _epochAmount,
		uint256 _intervalStart
		) external onlyOwner {
		ApeDistributor(
			ApeRegistry(apeRegistry).distributor()
		).setAllowance(_circle, _token, _amount, _interval, _epochAmount, _intervalStart);
	}
}