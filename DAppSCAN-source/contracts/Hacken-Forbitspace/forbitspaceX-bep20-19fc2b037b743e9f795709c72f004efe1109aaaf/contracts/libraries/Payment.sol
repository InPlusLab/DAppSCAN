// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import { SafeBEP20, IBEP20, Address } from "./SafeBEP20.sol";
import { SafeMath } from "./SafeMath.sol";
import { Ownable } from "./Ownable.sol";
import { IPayment } from "../interfaces/IPayment.sol";
import { IWBNB } from "../interfaces/IWBNB.sol";

abstract contract Payment is IPayment, Ownable {
	using SafeMath for uint;
	using SafeBEP20 for IBEP20;

	address public constant BNB_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

	address public immutable WBNB_ADDRESS;
	address public admin;
	receive() external payable {}

	constructor(address _WBNB, address _admin) {
		WBNB_ADDRESS = _WBNB;
		admin = _admin;
	}

	function approve(
		address addressToApprove,
		address token,
		uint amount
	) internal {
		if (IBEP20(token).allowance(address(this), addressToApprove) < amount) {
			IBEP20(token).safeApprove(addressToApprove, 0);
			IBEP20(token).safeIncreaseAllowance(addressToApprove, amount);
		}
	}

	function balanceOf(address token) internal view returns (uint bal) {
		if (token == BNB_ADDRESS) {
			token = WBNB_ADDRESS;
		}

		bal = IBEP20(token).balanceOf(address(this));
	}

	function pay(
		address recipient,
		address token,
		uint amount
	) internal {
		if (amount > 0) {
			if (recipient == address(this)) {
				if (token == BNB_ADDRESS) {
					IWBNB(WBNB_ADDRESS).deposit{ value: amount }();
				} else {
					IBEP20(token).safeTransferFrom(_msgSender(), address(this), amount);
				}
			} else {
				if (token == BNB_ADDRESS) {
					if (balanceOf(WBNB_ADDRESS) > 0) IWBNB(WBNB_ADDRESS).withdraw(balanceOf(WBNB_ADDRESS));
					Address.sendValue(payable(recipient), amount);
				} else {
					IBEP20(token).safeTransfer(recipient, amount);
				}
			}
		}
	}

	function collectBNB() public override returns (uint amount) {
		if (balanceOf(WBNB_ADDRESS) > 0) {
			IWBNB(WBNB_ADDRESS).withdraw(balanceOf(WBNB_ADDRESS));
		}
		if ((amount = address(this).balance) > 0) {
			Address.sendValue(payable(admin), amount);
		}
	}

	function collectTokens(address token) public override returns (uint amount) {
		if (token == BNB_ADDRESS) {
			amount = collectBNB();
		} else if ((amount = balanceOf(token)) > 0) {
			IBEP20(token).safeTransfer(admin, amount);
		}
	}

// SWC-100-Function Default Visibility: L85
	function setAdmin(address newAdmin) public override onlyOwner {
		require(newAdmin != admin, "A_I_E"); // Admin is exist
		admin = newAdmin;
	}
}
