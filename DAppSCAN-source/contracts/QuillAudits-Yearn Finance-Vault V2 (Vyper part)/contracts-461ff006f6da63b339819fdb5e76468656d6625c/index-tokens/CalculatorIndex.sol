pragma solidity ^0.5.0;

import "@openzeppelin/upgrades/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";

import "../shared/utils/Math.sol";
import "../shared/utils/DateTimeLibrary.sol";
import "./Abstract/InterfaceStorageIndex.sol";
import "./Abstract/InterfaceIndexToken.sol";


/**
 * @dev uint256 are expected to use last 18 numbers as decimal points except when specifid differently in @params
 */
contract CalculatorIndex is Initializable {
    using SafeMath for uint256;

    InterfaceStorageIndex public persistentStorage;
    InterfaceIndexToken public indexToken;

    function initialize(
        address _persistentStorageAddress,
        address _indexTokenAddress
    ) public initializer {
        persistentStorage = InterfaceStorageIndex(_persistentStorageAddress);
        indexToken = InterfaceIndexToken(_indexTokenAddress);
    }

    // Start fill in the values
    // Creation 3x Long

    function getTokensCreatedByCash(
        uint256 mintingPrice,
        uint256 cash,
        uint256 gasFee
    ) public view returns (uint256 tokensCreated) {
        // Cash Remove Gas Fee
        // Cash Remove Minting Fee (Cash Proceeds)
        // Cash Proceeds / Minting Price (# of Tokens to Mint)

        uint256 cashAfterGas = DSMath.sub(cash, gasFee);
        uint256 cashAfterFee = removeCurrentMintingFeeFromCash(cashAfterGas);

        uint256 tokensMinted = DSMath.wdiv(cashAfterFee, mintingPrice);

        return tokensMinted;
    }

    function getCashCreatedByTokens(
        uint256 burningPrice,
        uint256 elapsedTime,
        uint256 tokens,
        uint256 gasFee
    ) public view returns (uint256 stablecoinAfterFees) {
        uint256 stablecoin = DSMath.wmul(tokens, burningPrice);
        uint256 stablecoinAfterGas = DSMath.sub(stablecoin, gasFee);
        uint256 stablecoinRedeemed = removeCurrentMintingFeeFromCash(
            stablecoinAfterGas
        );
        uint256 managementFeeDaily = DSMath.wdiv(
            persistentStorage.managementFee(),
            365 ether
        );
        uint256 managementFeeHourly = DSMath.wdiv(
            DSMath.wmul(managementFeeDaily, elapsedTime),
            24 ether
        );
        uint256 normalizedManagementFee = DSMath.sub(
            1 ether,
            DSMath.wdiv(managementFeeHourly, 100 ether)
        );

        stablecoinAfterFees = DSMath.wmul(
            stablecoinRedeemed,
            normalizedManagementFee
        );
    }

    function removeCurrentMintingFeeFromCash(uint256 _cash)
        public
        view
        returns (uint256 cashAfterFee)
    {
        uint256 creationFee = persistentStorage.getMintingFee(_cash);
        uint256 minimumMintingFee = persistentStorage.minimumMintingFee();
        cashAfterFee = removeMintingFeeFromCash(
            _cash,
            creationFee,
            minimumMintingFee
        );
    }

    function removeMintingFeeFromCash(
        uint256 _cash,
        uint256 _mintingFee,
        uint256 _minimumMintingFee
    ) public pure returns (uint256 cashAfterFee) {
        uint256 creationFeeInCash = DSMath.wmul(_cash, _mintingFee);
        if (_minimumMintingFee > creationFeeInCash) {
            creationFeeInCash = _minimumMintingFee;
        }
        cashAfterFee = DSMath.sub(_cash, creationFeeInCash);
    }

    int256 constant WAD = 10**18;

    function addInt256(int256 x, int256 y) internal pure returns (int256 z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }

    function mulInt256(int256 x, int256 y) internal pure returns (int256 z) {
        require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
    }

    function wmulInt256(int256 x, int256 y) internal pure returns (int256 z) {
        z = addInt256(mulInt256(x, y), WAD / 2) / WAD;
    }
}
