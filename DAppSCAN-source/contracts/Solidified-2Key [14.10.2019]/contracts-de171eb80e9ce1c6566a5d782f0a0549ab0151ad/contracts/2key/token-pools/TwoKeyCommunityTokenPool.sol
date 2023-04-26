pragma solidity ^0.4.24;

import "./TokenPool.sol";
import "../interfaces/ITwoKeyRegistry.sol";
import "../interfaces/storage-contracts/ITwoKeyCommunityTokenPoolStorage.sol";
/**
 * @author Nikola Madjarevic
 * Created at 2/5/19
 */
contract TwoKeyCommunityTokenPool is TokenPool {

    ITwoKeyCommunityTokenPoolStorage public PROXY_STORAGE_CONTRACT;


    mapping(uint => uint) yearToStartingDate;
    mapping(uint => uint) yearToTransferedThisYear;



    function setInitialParams(
        address twoKeySingletonesRegistry,
        address _erc20Address,
        address _proxyStorage
    )
    external
    {
        require(initialized == false);

        setInitialParameters(_erc20Address, TWO_KEY_SINGLETON_REGISTRY);

        PROXY_STORAGE_CONTRACT = ITwoKeyCommunityTokenPoolStorage(_proxyStorage);

        setUint("totalAmount2keys", 200000000);
        setUint("annualTransferAmountLimit", 20000000);
        setUint("startingDate", block.timestamp);

        for(uint i=1; i<=10; i++) {
            bytes32 key1 = keccak256("yearToStartingDate", i);
            bytes32 key2 = keccak256("yearToTransferedThisYear", i);

            PROXY_STORAGE_CONTRACT.setUint(key1, block.timestamp + i*(1 years));
            PROXY_STORAGE_CONTRACT.setUint(key2, 0);
        }

        initialized = true;
    }

    /**
     * @notice Function to validate if the user is properly registered in TwoKeyRegistry
     */
    function validateRegistrationOfReceiver(
        address _receiver
    )
    internal
    view
    returns (bool)
    {
        address twoKeyRegistry = getAddressFromTwoKeySingletonRegistry("TwoKeyRegistry");
        return ITwoKeyRegistry(twoKeyRegistry).checkIfUserExists(_receiver);
    }

    /**
     * @notice Function which does transfer with special requirements with annual limit
     * @param _receiver is the receiver of the tokens
     * @param _amount is the amount of tokens sent
     * @dev Only TwoKeyAdmin contract can issue this call
     */
    function transferTokensToAddress(
        address _receiver,
        uint _amount
    )
    public
    onlyTwoKeyAdmin
    {
        require(validateRegistrationOfReceiver(_receiver) == true);
        require(_amount > 0);

        uint year = checkInWhichYearIsTheTransfer();
        require(year >= 1 && year <= 10);

        bytes32 keyTransferedThisYear = keccak256("yearToTransferedThisYear",year);
        bytes32 keyAnnualTransferAmountLimit = keccak256("annualTransferAmountLimit");

        uint transferedThisYear = PROXY_STORAGE_CONTRACT.getUint(keyTransferedThisYear);
        uint annualTransferAmountLimit = PROXY_STORAGE_CONTRACT.getUint(keyAnnualTransferAmountLimit);

        require(transferedThisYear + _amount <= annualTransferAmountLimit);
        super.transferTokens(_receiver,_amount);

        PROXY_STORAGE_CONTRACT.setUint(keyTransferedThisYear, transferedThisYear + _amount);

    }

    function checkInWhichYearIsTheTransfer()
    public
    view
    returns (uint)
    {
        uint startingDate = getUint("startingDate");

        if(block.timestamp > startingDate && block.timestamp < startingDate + 1 years) {
            return 1;
        } else {
            uint counter = 1;
            uint start = startingDate + 1 years; //means we're checking for the second year
            while(block.timestamp > start || counter == 10) {
                start = start + 1 years;
                counter ++;
            }
            return counter;
        }
    }

    // Internal wrapper method
    function setUint(
        string key,
        uint value
    )
    internal
    {
        PROXY_STORAGE_CONTRACT.setUint(keccak256(key), value);
    }

    function getUint(
        string key
    )
    public
    view
    returns (uint)
    {
        return PROXY_STORAGE_CONTRACT.getUint(keccak256(key));
    }

}
