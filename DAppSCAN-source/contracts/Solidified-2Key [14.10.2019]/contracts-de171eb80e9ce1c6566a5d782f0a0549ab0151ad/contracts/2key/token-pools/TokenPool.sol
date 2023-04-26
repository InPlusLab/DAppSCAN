pragma solidity ^0.4.24;

import "../interfaces/ITwoKeyMaintainersRegistry.sol";
import "../interfaces/ITwoKeySingletoneRegistryFetchAddress.sol";
import "../interfaces/IERC20.sol";
import "../upgradability/Upgradeable.sol";
import "../singleton-contracts/ITwoKeySingletonUtils.sol";
/**
 * @author Nikola Madjarevic
 * Created at 2/5/19
 */
contract TokenPool is Upgradeable, ITwoKeySingletonUtils {

    bool initialized = false;

    address public TWO_KEY_ECONOMY;

    function setInitialParameters(
        address _erc20address,
        address _twoKeySingletonesRegistry
    )
    internal
    {
        TWO_KEY_ECONOMY = _erc20address;
        TWO_KEY_SINGLETON_REGISTRY = _twoKeySingletonesRegistry;
    }

    modifier onlyMaintainer {
        address twoKeyMaintainersRegistry = getAddressFromTwoKeySingletonRegistry("TwoKeyMaintainersRegistry");
        require(ITwoKeyMaintainersRegistry(twoKeyMaintainersRegistry).onlyMaintainer(msg.sender));
        _;
    }

    modifier onlyTwoKeyAdmin {
        address twoKeyAdmin = getAddressFromTwoKeySingletonRegistry("TwoKeyAdmin");
        require(msg.sender == twoKeyAdmin);
        _;
    }

    /**
     * @notice Function to retrieve the balance of tokens on the contract
     */
    function getContractBalance()
    public
    view
    returns (uint)
    {
        return IERC20(TWO_KEY_ECONOMY).balanceOf(address(this));
    }

    /**
     * @notice Function to transfer tokens
     */
    function transferTokens(
        address receiver,
        uint amount
    )
    internal
    {
        IERC20(TWO_KEY_ECONOMY).transfer(receiver,amount);
    }

}
