// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


/// @title HoldefiCollaterals
/// @author Holdefi Team
/// @notice Collaterals is held by this contract
/// @dev The address of ETH asset considered as 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
contract HoldefiCollaterals {

	address constant public ethAddress = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

	address public holdefiContract;

	/// @dev Initializes the main Holdefi contract address
	constructor() public {
		holdefiContract = msg.sender;
	}

	/// @notice Modifier to check that only Holdefi contract interacts with the function
    modifier onlyHoldefiContract() {
        require (msg.sender == holdefiContract, "Sender should be holdefi contract");
        _;
    }

	/// @notice Only Holdefi contract can send ETH to this contract
    receive() external payable onlyHoldefiContract {
	}

	/// @notice Holdefi contract withdraws collateral from this contract to recipient account
	/// @param collateral Address of the given collateral
	/// @param recipient Address of the recipient
	/// @param amount Amount to be withdrawn
	function withdraw (address collateral, address recipient, uint256 amount)
		external
		onlyHoldefiContract
	{
		bool success = false;
		if (collateral == ethAddress){
			(success, ) = recipient.call{value:amount}("");
		}
		else {
			IERC20 token = IERC20(collateral);
			success = token.transfer(recipient, amount);
		}
		require (success, "Cannot Transfer");
	}

}