// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;

/**
    This interface is used primarily with contracts that hold assets, such as farm, vault, staking, cross-chain, etc.
    While participating in activities, users can separate property rights and use rights through freezing. For example, mortgage lending after freezing.
 */
interface IAsset {
    event Approve(address indexed _owner, address indexed _spender, address indexed _asset, uint256 _amount);

    event FreezeAsset(address indexed _user, address indexed _asset, uint256 _amount);

    event UnfreezeAsset(address indexed _user, address indexed _asset, uint256 _amount);

    event TransferFrom(address indexed _from, address indexed _receiver, address indexed _asset, uint256 _amount);

    /**
        Allow _spender to freeze/unfreeze this _asset
     */
    function approve(
        address _spender,
        address _asset,
        uint256 _amount
    ) external returns (bool);

    /**
        Freeze the special asset
     */
    function freezeAsset(
        address _user,
        address _asset,
        uint256 _amount
    ) external returns (bool);

    /**
        Unfreeze the speical asset
     */
    function unfreezeAsset(
        address _user,
        address _asset,
        uint256 _amount
    ) external returns (bool);

    /**
        Transfer those frezon asset to the receiver
     */
    function transferFrom(
        address _from,
        address _receiver,
        address _asset,
        uint256 _amount
    ) external returns (bool);

    /**
        Get the available asset of user, except these frozen asset
     */
    function getUserAvailableAsset(address _user, address _asset) external view returns (uint256);

    /**
        Get the total asset of user, including these fronze asset
     */
    function getUserAsset(address _user, address _asset) external view returns (uint256);
}
