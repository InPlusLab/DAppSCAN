pragma solidity ^0.4.24;

import "./TokenPool.sol";
import "../interfaces/storage-contracts/ITwoKeyLongTermTokenPoolStorage.sol";
/**
 * @author Nikola Madjarevic
 * Created at 2/5/19
 */
contract TwoKeyLongTermTokenPool is TokenPool {

    ITwoKeyLongTermTokenPoolStorage public PROXY_STORAGE_CONTRACT;

    modifier onlyAfterReleaseDate {
        uint releaseDate = PROXY_STORAGE_CONTRACT.getUint(keccak256("releaseDate"));
        require(block.timestamp > releaseDate);
        _;
    }

    function setInitialParams(
        address _twoKeySingletonesRegistry,
        address _erc20Address,
        address _proxyStorage
    )
    public
    {
        require(initialized == false);

        PROXY_STORAGE_CONTRACT = ITwoKeyLongTermTokenPoolStorage(_proxyStorage);

        setInitialParameters(_erc20Address, _twoKeySingletonesRegistry);
        PROXY_STORAGE_CONTRACT.setUint(keccak256("releaseDate"), block.timestamp + 3 * (1 years));

        initialized = true;
    }

    /**
     * @notice Long term pool will hold the tokens for 3 years after that they can be transfered by TwoKeyAdmin
     * @param _receiver is the receiver of the tokens
     * @param _amount is the amount of the tokens
     */
    function transferTokensFromContract(
        address _receiver,
        uint _amount
    )
    public
    onlyTwoKeyAdmin onlyAfterReleaseDate
    {
        super.transferTokens(_receiver, _amount);
    }
}
