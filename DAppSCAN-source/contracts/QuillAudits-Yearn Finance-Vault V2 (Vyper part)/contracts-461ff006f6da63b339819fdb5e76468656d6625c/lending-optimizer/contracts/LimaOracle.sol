pragma solidity >=0.6.6;

import {ChainlinkClient} from "@chainlink/contracts/src/v0.6/ChainlinkClient.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.6/interfaces/LinkTokenInterface.sol";
import { Chainlink } from "@chainlink/contracts/src/v0.6/Chainlink.sol";
import {ILimaOracleReceiver} from "./interfaces/ILimaOracleReceiver.sol";

/**
 * @title LimaOracle is an contract which is responsible for requesting data from
 * the Chainlink network
 */
contract LimaOracle is ChainlinkClient {

    address public oracle;
    bytes32 public jobId;
    uint256 private fee;
    string private uri;

    mapping(bytes32 => ILimaOracleReceiver) public pendingRequests;

    /**
     * @notice Deploy the contract with a specified address for the LINK
     * and Oracle contract addresses
     */
    constructor(address _oracle, address link, bytes32 _jobId, string memory _uri) public {
        oracle = _oracle;
        fee = LINK / 10; // 0.1 LINK
        jobId = _jobId;
        uri = _uri;
        setChainlinkToken(link);
    }

    function requestDeliveryStatus(address _receiver) public returns  (bytes32 requestId) 
    {
        Chainlink.Request memory req = buildChainlinkRequest(
            jobId,
            address(this),
            this.fulfill.selector
        );

        //Set the URL to perform the GET request on
        req.add(
            "get",
            uri
        );

        //Set the path to find the desired data in the API response, where the response format is:
        req.add("path", "address");
        requestId = sendChainlinkRequestTo(oracle, req, fee);

        //Save callback function & receiver
        pendingRequests[requestId] = ILimaOracleReceiver(_receiver);

        return requestId;
    }

    /**
     * @notice The fulfill method from requests created by this contract
     * @dev The recordChainlinkFulfillment protects this function from being called
     * by anyone other than the oracle address that the request was sent to
     * @param _requestId The ID that was generated for the request
     * @param _data The answer provided by the oracle
     */
    function fulfill(bytes32 _requestId, bytes32 _data)
        public
        recordChainlinkFulfillment(_requestId)
    {
        ILimaOracleReceiver receiver = pendingRequests[_requestId];
        
        receiver.receiveOracleData(_requestId, _data);
        
        delete pendingRequests[_requestId];
    }
}
