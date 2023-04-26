pragma solidity 0.5.10;

import "./OptionsContract.sol";
import "./OptionsUtils.sol";
import "./lib/StringComparator.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract OptionsFactory is Ownable {
    using StringComparator for string;

    // keys saved in front-end -- look at the docs if needed
    mapping (string => IERC20) public tokens;
    address[] public optionsContracts;

    // The contract which interfaces with the exchange + oracle
    OptionsExchange public optionsExchange;

    event OptionsContractCreated(address addr);
    event AssetAdded(string indexed asset, address indexed addr);
    event AssetChanged(string indexed asset, address indexed addr);
    event AssetDeleted(string indexed asset);

    /**
     * @param _optionsExchangeAddr: The contract which interfaces with the exchange + oracle
     */
    constructor(OptionsExchange _optionsExchangeAddr) public {
        optionsExchange = OptionsExchange(_optionsExchangeAddr);
    }

    /**
     * @notice creates a new Option Contract
     * @param _collateralType The collateral asset. Eg. "ETH"
     * @param _collateralExp The number of decimals the collateral asset has
     * @param _underlyingType The underlying asset. Eg. "DAI"
     * @param _oTokenExchangeExp Units of underlying that 1 oToken protects
     * @param _strikePrice The amount of strike asset that will be paid out
     * @param _strikeExp The precision of the strike asset (-18 if ETH)
     * @param _strikeAsset The asset in which the insurance is calculated
     * @param _expiry The time at which the insurance expires
     * @param _windowSize UNIX time. Exercise window is from `expiry - _windowSize` to `expiry`.
     */
    function createOptionsContract(
        string memory _collateralType,
        int32 _collateralExp,
        string memory _underlyingType,
        int32 _oTokenExchangeExp,
        uint256 _strikePrice,
        int32 _strikeExp,
        string memory _strikeAsset,
        uint256 _expiry,
        uint256 _windowSize
    )
        public
        returns (address)
    {
        require(supportsAsset(_collateralType), "Collateral type not supported");
        require(supportsAsset(_underlyingType), "Underlying type not supported");
        require(supportsAsset(_strikeAsset), "Strike asset type not supported");

        OptionsContract optionsContract = new OptionsContract(
            tokens[_collateralType],
            _collateralExp,
            tokens[_underlyingType],
            _oTokenExchangeExp,
            _strikePrice,
            _strikeExp,
            tokens[_strikeAsset],
            _expiry,
            optionsExchange,
            _windowSize
        );

        optionsContracts.push(address(optionsContract));
        emit OptionsContractCreated(address(optionsContract));

        // Set the owner for the options contract.
        optionsContract.transferOwnership(owner());

        return address(optionsContract);
    }

    /**
     * @notice The number of Option Contracts that the Factory contract has stored
     */
    function getNumberOfOptionsContracts() public view returns (uint256) {
        return optionsContracts.length;
    }

    /**
     * @notice The owner of the Factory Contract can add a new asset to be supported
     * @dev admin don't add ETH. ETH is set to 0x0.
     * @param _asset The ticker symbol for the asset
     * @param _addr The address of the asset
     */
    function addAsset(string memory _asset, address _addr) public onlyOwner {
        require(!supportsAsset(_asset), "Asset already added");
        require(_addr != address(0), "Cannot set to address(0)");

        tokens[_asset] = IERC20(_addr);
        emit AssetAdded(_asset, _addr);
    }

    /**
     * @notice The owner of the Factory Contract can change an existing asset's address
     * @param _asset The ticker symbol for the asset
     * @param _addr The address of the asset
     */
    function changeAsset(string memory _asset, address _addr) public onlyOwner {
        require(tokens[_asset] != IERC20(0), "Trying to replace a non-existent asset");
        require(_addr != address(0), "Cannot set to address(0)");

        tokens[_asset] = IERC20(_addr);
        emit AssetChanged(_asset, _addr);
    }

    /**
     * @notice The owner of the Factory Contract can delete an existing asset's address
     * @param _asset The ticker symbol for the asset
     */
    function deleteAsset(string memory _asset) public onlyOwner {
        require(tokens[_asset] != IERC20(0), "Trying to delete a non-existent asset");

        tokens[_asset] = IERC20(0);
        emit AssetDeleted(_asset);
    }

    /**
     * @notice Check if the Factory contract supports a specific asset
     * @param _asset The ticker symbol for the asset
     */
    function supportsAsset(string memory _asset) public view returns (bool) {
        if (_asset.compareStrings("ETH")) {
            return true;
        }

        return tokens[_asset] != IERC20(0);
    }
}
