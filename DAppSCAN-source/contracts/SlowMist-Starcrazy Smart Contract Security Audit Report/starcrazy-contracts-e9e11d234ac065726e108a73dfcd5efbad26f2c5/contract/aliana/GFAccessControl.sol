pragma solidity ^0.5.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title A facet of AlianaCore that manages special access privileges.
/// @dev See the AlianaCore contract documentation to understand how the various contract facets are arranged.
contract GFAccessControl {
    mapping(address => bool) public whitelist;

    event WhitelistedAddressAdded(address addr);
    event WhitelistedAddressRemoved(address addr);

    /**
     * @dev Throws if called by any account that's not whitelisted.
     */
    modifier onlyWhitelisted() {
        require(whitelist[msg.sender], "not whitelisted");
        _;
    }

    /**
     * @dev add an address to the whitelist
     * @param addr address
     * @return true if the address was added to the whitelist, false if the address was already in the whitelist
     */
    function addAddressToWhitelist(address addr)
        external
        onlyCEO
        returns (bool success)
    {
        return _addAddressToWhitelist(addr);
    }

    /**
     * @dev add an address to the whitelist
     * @param addr address
     * @return true if the address was added to the whitelist, false if the address was already in the whitelist
     */
    function _addAddressToWhitelist(address addr)
        private
        onlyCEO
        returns (bool success)
    {
        if (!whitelist[addr]) {
            whitelist[addr] = true;
            emit WhitelistedAddressAdded(addr);
            success = true;
        }
    }

    /**
     * @dev add addresses to the whitelist
     * @param addrs addresses
     * @return true if at least one address was added to the whitelist,
     * false if all addresses were already in the whitelist
     */
    function addAddressesToWhitelist(address[] calldata addrs)
        external
        onlyCEO
        returns (bool success)
    {
        for (uint256 i = 0; i < addrs.length; i++) {
            if (_addAddressToWhitelist(addrs[i])) {
                success = true;
            }
        }
    }

    /**
     * @dev remove an address from the whitelist
     * @param addr address
     * @return true if the address was removed from the whitelist,
     * false if the address wasn't in the whitelist in the first place
     */
    function removeAddressFromWhitelist(address addr)
        external
        onlyCEO
        returns (bool success)
    {
        return _removeAddressFromWhitelist(addr);
    }

    /**
     * @dev remove an address from the whitelist
     * @param addr address
     * @return true if the address was removed from the whitelist,
     * false if the address wasn't in the whitelist in the first place
     */
    function _removeAddressFromWhitelist(address addr)
        private
        onlyCEO
        returns (bool success)
    {
        if (whitelist[addr]) {
            whitelist[addr] = false;
            emit WhitelistedAddressRemoved(addr);
            success = true;
        }
    }

    /**
     * @dev remove addresses from the whitelist
     * @param addrs addresses
     * @return true if at least one address was removed from the whitelist,
     * false if all addresses weren't in the whitelist in the first place
     */
    function removeAddressesFromWhitelist(address[] calldata addrs)
        external
        onlyCEO
        returns (bool success)
    {
        for (uint256 i = 0; i < addrs.length; i++) {
            if (_removeAddressFromWhitelist(addrs[i])) {
                success = true;
            }
        }
    }

    // This facet controls access control for GameAlianas. There are four roles managed here:
    //
    //     - The CEO: The CEO can reassign other roles and change the addresses of our dependent smart
    //         contracts. It is also the only role that can unpause the smart contract. It is initially
    //         set to the address that created the smart contract in the AlianaCore constructor.
    //
    //     - The CFO: The CFO can withdraw funds from AlianaCore and its auction contracts.
    //
    //     - The COO: The COO can release gen0 alianas to auction, and mint promo cats.
    //
    // It should be noted that these roles are distinct without overlap in their access abilities, the
    // abilities listed for each role above are exhaustive. In particular, while the CEO can assign any
    // address to any role, the CEO address itself doesn't have the ability to act in those roles. This
    // restriction is intentional so that we aren't tempted to use the CEO address frequently out of
    // convenience. The less we use an address, the less likely it is that we somehow compromise the
    // account.

    /// @dev Emited when contract is upgraded - See README.md for updgrade plan
    event ContractUpgrade(address newContract);

    // The addresses of the accounts (or contracts) that can execute actions within each roles.
    address public ceoAddress;
    address public candidateCEOAddress;

    address public cfoAddress;
    address public cooAddress;

    event SetCandidateCEO(address addr);
    event AcceptCEO(address addr);
    event SetCFO(address addr);
    event SetCOO(address addr);

    event Pause(address operator);
    event Unpause(address operator);

    // @dev Keeps track whether the contract is paused. When that is true, most actions are blocked
    bool public paused = false;

    /**
     * @dev The Ownable constructor sets the original `ceoAddress` of the contract to the sender
     * account.
     */
    constructor() public {
        ceoAddress = msg.sender;
        emit AcceptCEO(ceoAddress);
    }

    /// @dev Access modifier for CEO-only functionality
    modifier onlyCEO() {
        require(msg.sender == ceoAddress, "not ceo");
        _;
    }

    /// @dev Access modifier for CFO-only functionality
    modifier onlyCFO() {
        require(msg.sender == cfoAddress, "not cfo");
        _;
    }

    /// @dev Access modifier for COO-only functionality
    modifier onlyCOO() {
        require(msg.sender == cooAddress, "not coo");
        _;
    }

    modifier onlyCLevel() {
        require(
            msg.sender == cooAddress ||
                msg.sender == ceoAddress ||
                msg.sender == cfoAddress,
            "not c level"
        );
        _;
    }

    modifier onlyCLevelOrWhitelisted() {
        require(
            msg.sender == cooAddress ||
                msg.sender == ceoAddress ||
                msg.sender == cfoAddress ||
                whitelist[msg.sender],
            "not c level or whitelisted"
        );
        _;
    }

    /// @dev Assigns a new address to act as the CEO. Only available to the current CEO.
    /// @param _candidateCEO The address of the new CEO
    function setCandidateCEO(address _candidateCEO) external onlyCEO {
        require(_candidateCEO != address(0), "addr can't be 0");

        candidateCEOAddress = _candidateCEO;
        emit SetCandidateCEO(candidateCEOAddress);
    }

    /// @dev Accept CEO invite.
    function acceptCEO() external {
        require(msg.sender == candidateCEOAddress, "you are not the candidate");

        ceoAddress = candidateCEOAddress;
        emit AcceptCEO(ceoAddress);
    }

    /// @dev Assigns a new address to act as the CFO. Only available to the current CEO.
    /// @param _newCFO The address of the new CFO
    function setCFO(address _newCFO) external onlyCEO {
        require(_newCFO != address(0), "addr can't be 0");

        cfoAddress = _newCFO;
        emit SetCFO(cfoAddress);
    }

    /// @dev Assigns a new address to act as the COO. Only available to the current CEO.
    /// @param _newCOO The address of the new COO
    function setCOO(address _newCOO) external onlyCEO {
        require(_newCOO != address(0), "addr can't be 0");

        cooAddress = _newCOO;
        emit SetCOO(cooAddress);
    }

    /*** Pausable functionality adapted from OpenZeppelin ***/

    /// @dev Modifier to allow actions only when the contract IS NOT paused
    modifier whenNotPaused() {
        require(!paused, "paused");
        _;
    }

    /// @dev Modifier to allow actions only when the contract IS paused
    modifier whenPaused() {
        require(paused, "not paused");
        _;
    }

    /// @dev Called by any "C-level" role to pause the contract. Used only when
    ///  a bug or exploit is detected and we need to limit damage.
    function pause() external onlyCEO whenNotPaused {
        paused = true;
        emit Pause(msg.sender);
    }

    /// @dev Unpauses the smart contract. Can only be called by the CEO, since
    ///  one reason we may pause the contract is when CFO or COO accounts are
    ///  compromised.
    /// @notice This is public rather than external so it can be called by
    ///  derived contracts.
    function unpause() public onlyCEO whenPaused {
        // can't unpause if contract was upgraded
        paused = false;
        emit Unpause(msg.sender);
    }

    // Set in case the core contract is broken and an upgrade is required
    address public newContractAddress;

    /// @dev Used to mark the smart contract as upgraded, in case there is a serious
    ///  breaking bug. This method does nothing but keep track of the new contract and
    ///  emit a message indicating that the new address is set. It's up to clients of this
    ///  contract to update to the new contract address in that case. (This contract will
    ///  be paused indefinitely if such an upgrade takes place.)
    /// @param _v2Address new address
    function setNewAddress(address _v2Address) external onlyCEO whenPaused {
        // See README.md for updgrade plan
        newContractAddress = _v2Address;
        emit ContractUpgrade(_v2Address);
    }

    //////////
    // Safety Methods
    //////////

    /// @notice This method can be used by the owner to extract mistakenly
    ///  sent tokens to this contract.
    /// @param token_ The address of the token contract that you want to recover
    ///  set to 0 in case you want to extract ether.
    function claimTokens(address token_) external onlyCEO {
        if (token_ == address(0)) {
            address(msg.sender).transfer(address(this).balance);
            return;
        }

        IERC20 token = IERC20(token_);
        uint256 balance = token.balanceOf(address(this));
        token.transfer(address(msg.sender), balance);

        emit ClaimedTokens(token_, address(msg.sender), balance);
    }

    function withdrawTokens(
        IERC20 token_,
        address to_,
        uint256 amount_
    ) external onlyCEO {
        assert(token_.transfer(to_, amount_));
        emit WithdrawTokens(address(token_), address(msg.sender), to_, amount_);
    }

    ////////////////
    // Events
    ////////////////

    event ClaimedTokens(
        address indexed token_,
        address indexed controller_,
        uint256 amount_
    );

    event WithdrawTokens(
        address indexed token_,
        address indexed controller_,
        address indexed to_,
        uint256 amount_
    );
}
