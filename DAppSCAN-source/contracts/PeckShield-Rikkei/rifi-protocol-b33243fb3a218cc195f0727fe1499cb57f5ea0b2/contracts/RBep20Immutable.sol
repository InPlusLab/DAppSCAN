pragma solidity ^0.5.16;

import "./RBep20.sol";

/**
 * @title Rifi's RBep20Immutable Contract
 * @notice RTokens which wrap an EIP-20 underlying and are immutable
 * @author Rifi
 */
contract RBep20Immutable is RBep20 {
    /**
     * @notice Construct a new money market
     * @param underlying_ The address of the underlying asset
     * @param cointroller_ The address of the Cointroller
     * @param interestRateModel_ The address of the interest rate model
     * @param initialExchangeRateMantissa_ The initial exchange rate, scaled by 1e18
     * @param name_ BEP-20 name of this token
     * @param symbol_ BEP-20 symbol of this token
     * @param decimals_ BEP-20 decimal precision of this token
     * @param admin_ Address of the administrator of this token
     */
    constructor(address underlying_,
                CointrollerInterface cointroller_,
                InterestRateModel interestRateModel_,
                uint initialExchangeRateMantissa_,
                string memory name_,
                string memory symbol_,
                uint8 decimals_,
                address payable admin_) public {
        // Creator of the contract is admin during initialization
        admin = msg.sender;

        // Initialize the market
        initialize(underlying_, cointroller_, interestRateModel_, initialExchangeRateMantissa_, name_, symbol_, decimals_);

        // Set the proper admin now that initialization is done
        admin = admin_;
    }
}
