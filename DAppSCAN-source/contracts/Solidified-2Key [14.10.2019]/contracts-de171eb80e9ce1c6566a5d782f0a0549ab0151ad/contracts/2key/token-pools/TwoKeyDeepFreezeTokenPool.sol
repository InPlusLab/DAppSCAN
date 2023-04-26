pragma solidity ^0.4.24;

import "./TokenPool.sol";
import "../interfaces/storage-contracts/ITwoKeyDeepFreezeTokenPoolStorage.sol";
/**
 * @author Nikola Madjarevic
 * Created at 2/5/19
 */
contract TwoKeyDeepFreezeTokenPool is TokenPool {

    ITwoKeyDeepFreezeTokenPoolStorage public PROXY_STORAGE_CONTRACT;

    address public twoKeyCommunityTokenPool;

    function setInitialParams(
        address _twoKeySingletonesRegistry,
        address _erc20Address,
        address _twoKeyCommunityTokenPool,
        address _proxyStorage
    )
    public
    {
        require(initialized == false);

        setInitialParameters(_erc20Address, _twoKeySingletonesRegistry);

        PROXY_STORAGE_CONTRACT = ITwoKeyDeepFreezeTokenPoolStorage(_proxyStorage);
        twoKeyCommunityTokenPool = _twoKeyCommunityTokenPool;

        PROXY_STORAGE_CONTRACT.setUint(keccak256("tokensReleaseDate"), block.timestamp + 10 * (1 years));

        initialized = true;
    }

    /**
     * @notice Function can transfer tokens only after 10 years to community token pool
     * @param amount is the amount of tokens we're sending
     * @dev only two key admin can issue a call to this method
     */
    function transferTokensToCommunityPool(
        uint amount
    )
    public
    onlyTwoKeyAdmin
    {
        uint tokensReleaseDate = PROXY_STORAGE_CONTRACT.getUint(keccak256("tokensReleaseDate"));

        require(getContractBalance() >= amount);
        require(block.timestamp > tokensReleaseDate);
        super.transferTokens(twoKeyCommunityTokenPool,amount);
    }

}
