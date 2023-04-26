pragma solidity ^0.5.7;

/**
 * @title   MassetStructs
 * @author  Stability Labs Pty. Ltd.
 * @notice  Structs used in the Masset contract and associated Libs
 */
interface MassetStructs {

    /** @dev Stores bAsset info. The struct takes 5 storage slots per Basset */
    struct Basset {

        /** @dev Address of the bAsset */
        address addr;

        /** @dev Status of the basset,  */
        BassetStatus status; // takes uint8 datatype (1 byte) in storage

        /** @dev An ERC20 can charge transfer fee, for example USDT, DGX tokens. */
        bool isTransferFeeCharged; // takes a byte in storage

        /**
         * @dev 1 Basset * ratio / ratioScale == x Masset (relative value)
         *      If ratio == 10e8 then 1 bAsset = 10 mAssets
         *      A ratio is divised as 10^(18-tokenDecimals) * measurementMultiple(relative value of 1 base unit)
         */
        uint256 ratio;

        /** @dev Target weights of the Basset (100% == 1e18) */
        uint256 maxWeight;

        /** @dev Amount of the Basset that is held in Collateral */
        uint256 vaultBalance;

    }

    /** @dev Status of the Basset - has it broken its peg? */
    enum BassetStatus {
        Default,
        Normal,
        BrokenBelowPeg,
        BrokenAbovePeg,
        Blacklisted,
        Liquidating,
        Liquidated,
        Failed
    }
}
