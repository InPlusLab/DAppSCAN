// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import { GTokenType0 } from "./GTokenType0.sol";
import { GCTokenType1 } from "./GCTokenType1.sol";
import { GCTokenType2 } from "./GCTokenType2.sol";
import { GATokenType2 } from "./GATokenType2.sol";
import { GTokenType3 } from "./GTokenType3.sol";

import { $ } from "./network/$.sol";

/**
 * @notice Definition of gDAI. As a gToken Type 0, it uses DAI as reserve and
 * distributes to other gToken types.
 */
contract gDAI is GTokenType0
{
	constructor ()
		GTokenType0("growth DAI", "gDAI", 18, $.GRO, $.DAI) public
	{
	}
}

/**
 * @notice Definition of gUSDC. As a gToken Type 0, it uses USDC as reserve and
 * distributes to other gToken types.
 */
contract gUSDC is GTokenType0
{
	constructor ()
		GTokenType0("growth USDC", "gUSDC", 6, $.GRO, $.USDC) public
	{
	}
}

/**
 * @notice Definition of gUSDT. As a gToken Type 0, it uses USDT as reserve and
 * distributes to other gToken types.
 */
contract gUSDT is GTokenType0
{
	constructor ()
		GTokenType0("growth USDT", "gUSDT", 6, $.GRO, $.USDT) public
	{
	}
}

/**
 * @notice Definition of gETH. As a gToken Type 0, it uses WETH as reserve and
 * distributes to other gToken types.
 */
contract gETH is GTokenType0
{
	constructor ()
		GTokenType0("growth ETH", "gETH", 18, $.GRO, $.WETH) public
	{
	}
}

/**
 * @notice Definition of gWBTC. As a gToken Type 0, it uses WBTC as reserve and
 * distributes to other gToken types.
 */
contract gWBTC is GTokenType0
{
	constructor ()
		GTokenType0("growth WBTC", "gWBTC", 8, $.GRO, $.WBTC) public
	{
	}
}

/**
 * @notice Definition of gBAT. As a gToken Type 0, it uses BAT as reserve and
 * distributes to other gToken types.
 */
contract gBAT is GTokenType0
{
	constructor ()
		GTokenType0("growth BAT", "gBAT", 18, $.GRO, $.BAT) public
	{
	}
}

/**
 * @notice Definition of gZRX. As a gToken Type 0, it uses ZRX as reserve and
 * distributes to other gToken types.
 */
contract gZRX is GTokenType0
{
	constructor ()
		GTokenType0("growth ZRX", "gZRX", 18, $.GRO, $.ZRX) public
	{
	}
}

/**
 * @notice Definition of gUNI. As a gToken Type 0, it uses UNI as reserve and
 * distributes to other gToken types.
 */
contract gUNI is GTokenType0
{
	constructor ()
		GTokenType0("growth UNI", "gUNI", 18, $.GRO, $.UNI) public
	{
	}
}

/**
 * @notice Definition of gCOMP. As a gToken Type 0, it uses COMP as reserve and
 * distributes to other gToken types.
 */
contract gCOMP is GTokenType0
{
	constructor ()
		GTokenType0("growth COMP", "gCOMP", 18, $.GRO, $.COMP) public
	{
	}
}

/**
 * @notice Definition of gENJ. As a gToken Type 0, it uses ENJ as reserve and
 * distributes to other gToken types.
 */
contract gENJ is GTokenType0
{
	constructor ()
		GTokenType0("growth ENJ", "gENJ", 18, $.GRO, $.ENJ) public
	{
	}
}

/**
 * @notice Definition of gKNC. As a gToken Type 0, it uses KNC as reserve and
 * distributes to other gToken types.
 */
contract gKNC is GTokenType0
{
	constructor ()
		GTokenType0("growth KNC", "gKNC", 18, $.GRO, $.KNC) public
	{
	}
}

/**
 * @notice Definition of gAAVE. As a gToken Type 0, it uses AAVE as reserve and
 * distributes to other gToken types.
 */
contract gAAVE is GTokenType0
{
	constructor ()
		GTokenType0("growth AAVE", "gAAVE", 18, $.GRO, $.AAVE) public
	{
	}
}

/**
 * @notice Definition of gLINK. As a gToken Type 0, it uses LINK as reserve and
 * distributes to other gToken types.
 */
contract gLINK is GTokenType0
{
	constructor ()
		GTokenType0("growth LINK", "gLINK", 18, $.GRO, $.LINK) public
	{
	}
}

/**
 * @notice Definition of gMANA. As a gToken Type 0, it uses MANA as reserve and
 * distributes to other gToken types.
 */
contract gMANA is GTokenType0
{
	constructor ()
		GTokenType0("growth MANA", "gMANA", 18, $.GRO, $.MANA) public
	{
	}
}

/**
 * @notice Definition of gREN. As a gToken Type 0, it uses REN as reserve and
 * distributes to other gToken types.
 */
contract gREN is GTokenType0
{
	constructor ()
		GTokenType0("growth REN", "gREN", 18, $.GRO, $.REN) public
	{
	}
}

/**
 * @notice Definition of gSNX. As a gToken Type 0, it uses SNX as reserve and
 * distributes to other gToken types.
 */
contract gSNX is GTokenType0
{
	constructor ()
		GTokenType0("growth SNX", "gSNX", 18, $.GRO, $.SNX) public
	{
	}
}

/**
 * @notice Definition of gYFI. As a gToken Type 0, it uses YFI as reserve and
 * distributes to other gToken types.
 */
contract gYFI is GTokenType0
{
	constructor ()
		GTokenType0("growth YFI", "gYFI", 18, $.GRO, $.YFI) public
	{
	}
}

/**
 * @notice Definition of gcDAI. As a gcToken Type 1, it uses cDAI as reserve
 * and employs leverage to maximize returns.
 */
contract gcDAI is GCTokenType1
{
	constructor ()
		GCTokenType1("growth cDAI", "gcDAI", 8, $.GRO, $.cDAI, $.COMP) public
	{
	}
}

/**
 * @notice Definition of gcUSDC. As a gcToken Type 1, it uses cUSDC as reserve
 * and employs leverage to maximize returns.
 */
contract gcUSDC is GCTokenType1
{
	constructor ()
		GCTokenType1("growth cUSDC", "gcUSDC", 8, $.GRO, $.cUSDC, $.COMP) public
	{
	}
}

/**
 * @notice Definition of gcUSDT. As a gcToken Type 1, it uses cUSDT as reserve
 * and employs leverage to maximize returns.
 */
contract gcUSDT is GCTokenType1
{
	constructor ()
		GCTokenType1("growth cUSDT", "gcUSDT", 8, $.GRO, $.cUSDT, $.COMP) public
	{
	}
}

/**
 * @notice Definition of gcETH. As a gcToken Type 2, it uses cETH as reserve
 * which serves as collateral for minting gDAI.
 */
contract gcETH is GCTokenType2
{
	constructor (address _growthToken)
		GCTokenType2("growth cETH", "gcETH", 8, $.GRO, $.cETH, $.COMP, $.cDAI, _growthToken) public
	{
	}

	receive() external payable {} // not to be used directly
}

/**
 * @notice Definition of gcWBTC. As a gcToken Type 2, it uses cWBTC as reserve
 * which serves as collateral for minting gDAI.
 */
contract gcWBTC is GCTokenType2
{
	constructor (address _growthToken)
		GCTokenType2("growth cWBTC", "gcWBTC", 8, $.GRO, $.cWBTC, $.COMP, $.cDAI, _growthToken) public
	{
	}
}

/**
 * @notice Definition of gcBAT. As a gcToken Type 2, it uses cBAT as reserve
 * which serves as collateral for minting gDAI.
 */
contract gcBAT is GCTokenType2
{
	constructor (address _growthToken)
		GCTokenType2("growth cBAT", "gcBAT", 8, $.GRO, $.cBAT, $.COMP, $.cDAI, _growthToken) public
	{
	}
}

/**
 * @notice Definition of gcZRX. As a gcToken Type 2, it uses cZRX as reserve
 * which serves as collateral for minting gDAI.
 */
contract gcZRX is GCTokenType2
{
	constructor (address _growthToken)
		GCTokenType2("growth cZRX", "gcZRX", 8, $.GRO, $.cZRX, $.COMP, $.cDAI, _growthToken) public
	{
	}
}

/**
 * @notice Definition of gcUNI. As a gcToken Type 2, it uses cUNI as reserve
 * which serves as collateral for minting gDAI.
 */
contract gcUNI is GCTokenType2
{
	constructor (address _growthToken)
		GCTokenType2("growth cUNI", "gcUNI", 8, $.GRO, $.cUNI, $.COMP, $.cDAI, _growthToken) public
	{
	}
}

/**
 * @notice Definition of gcCOMP. As a gcToken Type 2, it uses cCOMP as reserve
 * which serves as collateral for minting gDAI.
 */
contract gcCOMP is GCTokenType2
{
	constructor (address _growthToken)
		GCTokenType2("growth cCOMP", "gcCOMP", 8, $.GRO, $.cCOMP, $.COMP, $.cDAI, _growthToken) public
	{
	}
}

/**
 * @notice Definition of gacENJ. As a gaToken Type 2, it uses aENJ as reserve
 * which serves as collateral for minting gDAI.
 */
contract gacENJ is GATokenType2
{
	constructor (address _growthToken)
		GATokenType2("growth aENJ", "gacENJ", 18, $.GRO, $.aENJ, $.aDAI, _growthToken) public
	{
	}
}

/**
 * @notice Definition of gacKNC. As a gaToken Type 2, it uses aKNC as reserve
 * which serves as collateral for minting gDAI.
 */
contract gacKNC is GATokenType2
{
	constructor (address _growthToken)
		GATokenType2("growth aKNC", "gacKNC", 18, $.GRO, $.aKNC, $.aDAI, _growthToken) public
	{
	}
}

/**
 * @notice Definition of gacAAVE. As a gaToken Type 2, it uses aAAVE as reserve
 * which serves as collateral for minting gDAI.
 */
contract gacAAVE is GATokenType2
{
	constructor (address _growthToken)
		GATokenType2("growth aAAVE", "gacAAVE", 18, $.GRO, $.aAAVE, $.aDAI, _growthToken) public
	{
	}
}

/**
 * @notice Definition of gacLINK. As a gaToken Type 2, it uses aLINK as reserve
 * which serves as collateral for minting gDAI.
 */
contract gacLINK is GATokenType2
{
	constructor (address _growthToken)
		GATokenType2("growth aLINK", "gacLINK", 18, $.GRO, $.aLINK, $.aDAI, _growthToken) public
	{
	}
}

/**
 * @notice Definition of gacMANA. As a gaToken Type 2, it uses aMANA as reserve
 * which serves as collateral for minting gDAI.
 */
contract gacMANA is GATokenType2
{
	constructor (address _growthToken)
		GATokenType2("growth aMANA", "gacMANA", 18, $.GRO, $.aMANA, $.aDAI, _growthToken) public
	{
	}
}

/**
 * @notice Definition of gacREN. As a gaToken Type 2, it uses aREN as reserve
 * which serves as collateral for minting gDAI.
 */
contract gacREN is GATokenType2
{
	constructor (address _growthToken)
		GATokenType2("growth aREN", "gacREN", 18, $.GRO, $.aREN, $.aDAI, _growthToken) public
	{
	}
}

/**
 * @notice Definition of gacSNX. As a gaToken Type 2, it uses aSNX as reserve
 * which serves as collateral for minting gDAI.
 */
contract gacSNX is GATokenType2
{
	constructor (address _growthToken)
		GATokenType2("growth aSNX", "gacSNX", 18, $.GRO, $.aSNX, $.aDAI, _growthToken) public
	{
	}
}

/**
 * @notice Definition of gacYFI. As a gaToken Type 2, it uses aYFI as reserve
 * which serves as collateral for minting gDAI.
 */
contract gacYFI is GATokenType2
{
	constructor (address _growthToken)
		GATokenType2("growth aYFI", "gacYFI", 18, $.GRO, $.aYFI, $.aDAI, _growthToken) public
	{
	}
}

/**
 * @notice Definition of stkGRO. As a gToken Type 3, it uses GRO as reserve and
 * burns both reserve and supply with each operation.
 */
contract stkGRO is GTokenType3
{
	constructor ()
		GTokenType3("staked GRO", "stkGRO", 18, $.GRO) public
	{
	}
}
