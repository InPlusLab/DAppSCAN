pragma solidity ^0.5.0;

import "@openzeppelin/upgrades/contracts/Initializable.sol";
import "solidity-util/lib/Strings.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/ownership/Ownable.sol";

import "../short-tokens/Abstract/InterfaceCashPool.sol"; //TODO: move to shared folder and update references?
import "../short-tokens/Abstract/InterfaceKYCVerifier.sol"; //TODO: move to shared folder and update references?
import "./Abstract/InterfaceCalculator.sol";
import "./Abstract/InterfaceERC20Index.sol"; 

import "./Abstract/InterfaceIndexToken.sol";
import "./Abstract/InterfaceStorageIndex.sol";
import "../shared/utils/Math.sol";


contract TokenSwapIndex is Initializable, Ownable {
    using Strings for string;
    using SafeMath for uint256;

    address public indexToken;

    InterfaceERC20Index public erc20;
    InterfaceKYCVerifier public kycVerifier;
    InterfaceCashPool public cashPool;
    InterfaceStorageIndex public persistentStorage;
    InterfaceCalculator public compositionCalculator;

    event SuccessfulOrder(
        string orderType,
        address whitelistedAddress,
        uint256 tokensGiven,
        uint256 tokensRecieved,
        address stablecoin,
        uint256 price
    );

    event RebalanceEvent(
        uint256 bestExecutionPrice,
        uint256 markPrice,
        uint256 notional,
        uint256 tokenValue,
        uint256 effectiveFundingRate
    );

    function initialize(
        address _owner,
        address _indexToken,
        address _cashPool,
        address _storage,
        address _compositionCalculator
    ) public initializer {
        initialize(_owner);

        require(
            _owner != address(0) &&
                _indexToken != address(0) &&
                _cashPool != address(0) &&
                _storage != address(0) &&
                _compositionCalculator != address(0),
            "addresses cannot be zero"
        );

        indexToken = _indexToken;

        cashPool = InterfaceCashPool(_cashPool);
        persistentStorage = InterfaceStorageIndex(_storage);
        kycVerifier = InterfaceKYCVerifier(address(cashPool.kycVerifier()));
        compositionCalculator = InterfaceCalculator(_compositionCalculator);
    }

    //////////////// Create + Redeem Order Request ////////////////
    //////////////// Create: Recieve Inverse Token   ////////////////
    //////////////// Redeem: Recieve Stable Coin ////////////////

    function createOrder(
        bool success,
        uint256 tokensGiven,
        uint256 tokensRecieved,
        uint256 mintingPrice,
        address whitelistedAddress,
        address stablecoin,
        uint256 gasFee
    ) public onlyOwnerOrBridge() notPausedOrShutdown() returns (bool retVal) {
        // Require is Whitelisted
        require(
            kycVerifier.isAddressWhitelisted(whitelistedAddress),
            "only whitelisted address may place orders"
        );

        // Return Funds if Bridge Pass an Error
        if (!success) {
            transferTokenFromPool(
                stablecoin,
                whitelistedAddress,
                normalizeStablecoin(tokensGiven, stablecoin)
            );
            return false;
        }

        // Check Tokens Recieved with Composition Calculator
        uint256 _tokensRecieved = compositionCalculator.getTokensCreatedByCash(
            mintingPrice,
            tokensGiven,
            gasFee
        );
        require(
            _tokensRecieved == tokensRecieved,
            "tokens created must equal tokens recieved"
        );

        // Save Order to Storage and Lock Funds for 1 Hour
        persistentStorage.setOrderByUser(
            whitelistedAddress,
            "CREATE",
            tokensGiven,
            tokensRecieved,
            mintingPrice,
            0,
            false
        );

        // Write Successful Order to Log
        writeOrderResponse(
            "CREATE",
            whitelistedAddress,
            tokensGiven,
            tokensRecieved,
            stablecoin,
            mintingPrice
        );

        // Mint Tokens to Address
        InterfaceIndexToken token = InterfaceIndexToken(indexToken);
        token.mintTokens(whitelistedAddress, tokensRecieved);

        return true;
    }

    function redeemOrder(
        bool success,
        uint256 tokensGiven,
        uint256 tokensRecieved,
        uint256 burningPrice,
        address whitelistedAddress,
        address stablecoin,
        uint256 gasFee,
        uint256 elapsedTime
    ) public onlyOwnerOrBridge() notPausedOrShutdown() returns (bool retVal) {
        // Require Whitelisted
        require(
            kycVerifier.isAddressWhitelisted(whitelistedAddress),
            "only whitelisted address may place orders"
        );

        // Return Funds if Bridge Pass an Error
        if (!success) {
            transferTokenFromPool(
                indexToken,
                whitelistedAddress,
                tokensGiven
            );
            return false;
        }

        // Check Cash Recieved with Composition Calculator
        uint256 _tokensRecieved = compositionCalculator.getCashCreatedByTokens(
            burningPrice,
            elapsedTime,
            tokensGiven,
            gasFee
        );
        require(
            _tokensRecieved == tokensRecieved,
            "cash redeemed must equal tokens recieved"
        );

        // Save To Storage
        persistentStorage.setOrderByUser(
            whitelistedAddress,
            "REDEEM",
            tokensGiven,
            tokensRecieved,
            burningPrice,
            0,
            false
        );

        // Redeem Stablecoin or Perform Delayed Settlement
        redeemFunds(
            tokensGiven,
            tokensRecieved,
            whitelistedAddress,
            stablecoin,
            burningPrice
        );

        // Burn Tokens to Address
        InterfaceIndexToken token = InterfaceIndexToken(indexToken);
        token.burnTokens(address(cashPool), tokensGiven);

        return true;
    }

    function writeOrderResponse(
        string memory orderType,
        address whiteListedAddress,
        uint256 tokensGiven,
        uint256 tokensRecieved,
        address stablecoin,
        uint256 price
    ) internal {
        require(
            tokensGiven != 0 && tokensRecieved != 0,
            "amount must be greater than 0"
        );

        emit SuccessfulOrder(
            orderType,
            whiteListedAddress,
            tokensGiven,
            tokensRecieved,
            stablecoin,
            price
        );
    }

    function settleDelayedFunds(
        uint256 tokensToRedeem,
        address whitelistedAddress,
        address stablecoin
    ) public onlyOwnerOrBridge notPausedOrShutdown {
        require(
            kycVerifier.isAddressWhitelisted(whitelistedAddress),
            "only whitelisted may redeem funds"
        );

        bool isSufficientFunds = isHotWalletSufficient(
            tokensToRedeem,
            stablecoin
        );
        require(
            isSufficientFunds == true,
            "not enough funds in the hot wallet"
        );

        uint256 tokensOutstanding = persistentStorage.delayedRedemptionsByUser(
            whitelistedAddress
        );
        uint256 tokensRemaining = DSMath.sub(tokensOutstanding, tokensToRedeem);

        persistentStorage.setDelayedRedemptionsByUser(
            tokensRemaining,
            whitelistedAddress
        );
        transferTokenFromPool(
            stablecoin,
            whitelistedAddress,
            normalizeStablecoin(tokensToRedeem, stablecoin)
        );
    }

    function redeemFunds(
        uint256 tokensGiven,
        uint256 tokensToRedeem,
        address whitelistedAddress,
        address stablecoin,
        uint256 price
    ) internal {
        bool isSufficientFunds = isHotWalletSufficient(
            tokensToRedeem,
            stablecoin
        );

        if (isSufficientFunds) {
            transferTokenFromPool(
                stablecoin,
                whitelistedAddress,
                normalizeStablecoin(tokensToRedeem, stablecoin)
            );
            writeOrderResponse(
                "REDEEM",
                whitelistedAddress,
                tokensGiven,
                tokensToRedeem,
                stablecoin,
                price
            );
        } else {
            uint256 tokensOutstanding = persistentStorage
                .delayedRedemptionsByUser(whitelistedAddress);
            tokensOutstanding = DSMath.add(tokensOutstanding, tokensToRedeem);
            persistentStorage.setDelayedRedemptionsByUser(
                tokensOutstanding,
                whitelistedAddress
            );
            writeOrderResponse(
                "REDEEM_NO_SETTLEMENT",
                whitelistedAddress,
                tokensGiven,
                tokensToRedeem,
                stablecoin,
                price
            );
        }
    }

    function isHotWalletSufficient(uint256 tokensToRedeem, address stablecoin)
        internal
        returns (bool)
    {
        InterfaceIndexToken _stablecoin = InterfaceIndexToken(stablecoin);
        uint256 stablecoinBalance = _stablecoin.balanceOf(address(cashPool));

        if (normalizeStablecoin(tokensToRedeem, stablecoin) > stablecoinBalance)
            return false;
        return true;
    }

    function normalizeStablecoin(uint256 stablecoinValue, address stablecoin)
        internal
        returns (uint256)
    {
        erc20 = InterfaceERC20Index(stablecoin);
        uint256 exponent = 18 - erc20.decimals();
        return stablecoinValue / 10**exponent; // 6 decimal stable coin = 10**12
    }

    ////////////////    Daily Rebalance     ////////////////
    //////////////// Threshold Rebalance    ////////////////

    /**
     * @dev Saves results of rebalance calculations in persistent storages
     * @param _bestExecutionPrice The best execution price for rebalancing
     * @param _markPrice The Mark Price
     * @param _notional The new notional amount after rebalance
     * @param _tokenValue The targetLeverage
     * @param _effectiveFundingRate The effectiveFundingRate
     */

    function rebalance(
        uint256 _bestExecutionPrice,
        uint256 _markPrice,
        uint256 _notional,
        uint256 _tokenValue,
        uint256 _effectiveFundingRate
    ) public onlyOwnerOrBridge() notPausedOrShutdown() {
        persistentStorage.setAccounting(
            _bestExecutionPrice,
            _markPrice,
            _notional,
            _tokenValue,
            _effectiveFundingRate
        );
        emit RebalanceEvent(
            _bestExecutionPrice,
            _markPrice,
            _notional,
            _tokenValue,
            _effectiveFundingRate
        );
    }

    //////////////// Transfer Stablecoin Out of Pool   ////////////////
    //////////////// Transfer Stablecoin In of Pool    ////////////////
    //////////////// Transfer IndexToken Out of Pool ////////////////
    //////////////// Transfer IndexToken In of Pool  ////////////////

    function transferTokenToPool(
        address tokenContract,
        address whiteListedAddress,
        uint256 orderAmount
    ) internal returns (bool) {
        // Check orderAmount <= availableAmount
        // Transfer USDC to Stablecoin Cash Pool
        return
            cashPool.moveTokenToPool(
                tokenContract,
                whiteListedAddress,
                orderAmount
            );
    }

    function transferTokenFromPool(
        address tokenContract,
        address destinationAddress,
        uint256 orderAmount
    ) internal returns (bool) {
        // Check orderAmount <= availableAmount
        // Transfer USDC to Destination Address
        return
            cashPool.moveTokenfromPool(
                tokenContract,
                destinationAddress,
                orderAmount
            );
    }

    function setCashPool(address _cashPool) public onlyOwner {
        require(_cashPool != address(0), "adddress must not be empty");
        cashPool = InterfaceCashPool(_cashPool);
    }

    function setStorage(address _storage) public onlyOwner {
        require(_storage != address(0), "adddress must not be empty");
        persistentStorage = InterfaceStorageIndex(_storage);
    }

    function setKycVerfier(address _kycVerifier) public onlyOwner {
        require(_kycVerifier != address(0), "adddress must not be empty");
        kycVerifier = InterfaceKYCVerifier(_kycVerifier);
    }

    function setCalculator(address _calculator) public onlyOwner {
        require(_calculator != address(0), "adddress must not be empty");
        compositionCalculator = InterfaceCalculator(_calculator);
    }

    modifier onlyOwnerOrBridge() {
        require(
            isOwner() || _msgSender() == persistentStorage.bridge(),
            "caller is not the owner or bridge"
        );
        _;
    }

    modifier notPausedOrShutdown() {
        require(persistentStorage.isPaused() == false, "contract is paused");
        require(
            persistentStorage.isShutdown() == false,
            "contract is shutdown"
        );
        _;
    }
}
