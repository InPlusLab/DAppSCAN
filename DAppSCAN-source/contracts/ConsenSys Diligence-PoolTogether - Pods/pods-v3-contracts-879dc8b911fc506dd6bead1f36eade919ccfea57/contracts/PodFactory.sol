// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.8.0;

// Libraries
import "./external/ProxyFactory.sol";

// Internal Interfaces
import "./TokenDropFactory.sol";

// Clone Contracts
import "./Pod.sol";
import "./TokenDrop.sol";

/**
 * @title PodFactory (ProxyFactory) - Clones a Pod Instance
 * @notice Reduces gas costs and collectively increases that chances winning for PoolTogether users, while keeping user POOL distributions to users.
 * @dev The PodFactory creates/initializes connected Pod and TokenDrop smart contracts. Pods stores tokens, tickets, prizePool and other essential references.
 * @author Kames Geraghty
 */
contract PodFactory is ProxyFactory {
    /**
     * @notice TokenDropFactory reference
     */
    TokenDropFactory public tokenDropFactory;

    /**
     * @notice Contract template for deploying proxied Pods
     */
    Pod public podInstance;

    /**
     * @notice Contract template for deploying proxied TokenDrop
     */
    TokenDrop public tokenDropInstance;

    /***********************************|
    |   Events                          |
    |__________________________________*/
    /**
     * @dev Emitted when use deposits into batch backlog
     */
    event LogCreatedPodAndTokenDrop(address pod, address tokenDrop);

    /***********************************|
    |   Constructor                     |
    |__________________________________*/
    /**
     * @notice Initializes the Pod Factory with an instance of the Pod and TokenDropFactory reference.
     * @dev Initializes the Pod Factory with an instance of the Pod and TokenDropFactory reference.
     * @param _tokenDropFactory Target PrizePool for deposits and withdraws
     */
    constructor(TokenDropFactory _tokenDropFactory) {
        // Pod Instance
        podInstance = new Pod();

        // Reference TokenDropFactory
        tokenDropFactory = _tokenDropFactory;
    }

    /**
     * @notice Create a new Pod Clone using the Pod instance.
     * @dev The Pod Smart Contact is created and initialized using the PodFactory.
     * @param _prizePoolTarget Target PrizePool for deposits and withdraws
     * @param _ticket Non-sponsored PrizePool ticket - is verified during initialization.
     * @param _pool PoolTogether Goverance token - distributed for users with active deposits.
     * @param _faucet TokenFaucet reference that distributes POOL token for deposits
     * @param _manager Liquidates the Pod's "bonus" tokens for the Pod's token.
     * @return (address, address) Pod and TokenDrop addresses
     */
    function create(
        address _prizePoolTarget,
        address _ticket,
        address _pool,
        address _faucet,
        address _manager
    ) external returns (address, address) {
        // Pod Deploy
        Pod pod = Pod(deployMinimal(address(podInstance), ""));

        // Pod Initialize
        pod.initialize(_prizePoolTarget, _ticket, _pool, _faucet, _manager);

        // Update Owner
        pod.transferOwnership(msg.sender);

        TokenDrop tokenDrop = tokenDropFactory.create(address(pod), _pool);

        // TokenDrop Pod Initialize - Add Pod.token() to TokenDrop
        pod.setTokenDrop(address(pod.token()), address(tokenDrop));

        // Emit LogCreatedPodAndTokenDrop
        emit LogCreatedPodAndTokenDrop(address(pod), address(tokenDrop));

        // Return Pod/TokenDrop addresses
        return (address(pod), address(tokenDrop));
    }
}
