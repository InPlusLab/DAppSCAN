pragma solidity ^0.4.24;
import "./StandardTokenModified.sol";
import "../interfaces/ITwoKeySingletoneRegistryFetchAddress.sol";


contract TwoKeyEconomy is StandardTokenModified {
    string public name = 'TwoKeyEconomy';
    string public symbol= '2KEY';
    uint8 public decimals= 18;

    address public twoKeyAdmin;
    address public twoKeySingletonRegistry;

    modifier onlyTwoKeyAdmin {
        require(msg.sender == twoKeyAdmin);
        _;
    }

    constructor (
        address _twoKeyAdmin,
        address _twoKeySingletonRegistry
    )
    public
    {
        twoKeySingletonRegistry = _twoKeySingletonRegistry;

        twoKeyAdmin = ITwoKeySingletoneRegistryFetchAddress(twoKeySingletonRegistry).
        getContractProxyAddress("TwoKeyAdmin");

        address twoKeyUpgradableExchange = ITwoKeySingletoneRegistryFetchAddress(twoKeySingletonRegistry).
            getContractProxyAddress("TwoKeyUpgradableExchange");
        address twoKeyCommunityTokenPool = ITwoKeySingletoneRegistryFetchAddress(twoKeySingletonRegistry).
            getContractProxyAddress("TwoKeyCommunityTokenPool");
        address twoKeyLongTermTokenPool = ITwoKeySingletoneRegistryFetchAddress(twoKeySingletonRegistry).
            getContractProxyAddress("TwoKeyLongTermTokenPool");

        totalSupply_= 1000000000000000000000000000; // 1B tokens total minted supply

        // Updating balances
        balances[twoKeyUpgradableExchange] = totalSupply_.mul(5).div(100);
        balances[twoKeyCommunityTokenPool] = totalSupply_.mul(20).div(100);
        balances[twoKeyLongTermTokenPool] = totalSupply_.mul(40).div(100);
        balances[_twoKeyAdmin] = totalSupply_.mul(35).div(100);
    }

    function changeAdmin(
        address _newAdmin
    )
    public
    onlyTwoKeyAdmin
    {
        require(_newAdmin != address(0));
        twoKeyAdmin = _newAdmin;
    }

    /// @notice TwoKeyAmin is available to freeze all transfers on ERC for some period of time
    /// @dev in TwoKeyAdmin only Congress can call this
    function freezeTransfers()
    public
    onlyTwoKeyAdmin
    {
        transfersFrozen = true;
    }

    /// @notice TwoKeyAmin is available to unfreeze all transfers on ERC for some period of time
    /// @dev in TwoKeyAdmin only Congress can call this
    function unfreezeTransfers()
    public
    onlyTwoKeyAdmin
    {
        transfersFrozen = false;
    }

}
