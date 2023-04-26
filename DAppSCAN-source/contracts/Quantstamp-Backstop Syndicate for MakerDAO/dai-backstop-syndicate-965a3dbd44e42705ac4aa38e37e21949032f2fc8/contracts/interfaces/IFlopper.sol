pragma solidity 0.5.16;

interface IFlopper {
    // --- Auth ---
    // caller authorization (1 = authorized, 0 = not authorized)
    function wards(address) external view returns (uint256);
    // authorize caller
    function rely(address usr) external;
    // deauthorize caller
    function deny(address usr) external;

    // Bid objects
    function bids(uint256) external view returns (
        uint256 bid,
        uint256 lot,
        address guy,
        uint48 tic,
        uint48 end
    );

    // DAI contract address
    function vat() external view returns (address);
    // MKR contract address
    function gem() external view returns (address);

    // num decimals (constant)
    function ONE() external pure returns (uint256);

    // minimum bid increase (config - 5% initial)
    function beg() external view returns (uint256);
    // initial lot increase (config - 50% initial)
    function pad() external view returns (uint256);
    // bid lifetime (config - 3 hours initial)
    function ttl() external view returns (uint48);
    // total auction length (config - 2 days initial)
    function tau() external view returns (uint48);

    // number of auctions
    function kicks() external view returns (uint256);
    // status of the auction (1 = active, 0 = disabled)
    function live() external view returns (uint256);
    // user who shut down flopper mechanism and paid off last bid
    function vow() external view returns (address);

    // --- Events ---
    event Kick(uint256 id, uint256 lot, uint256 bid, address indexed gal);

    // --- Admin ---
    function file(bytes32 what, uint256 data) external;

    // --- Auction ---

    // create an auction 
    // access control: authed
    // state machine: after auction expired
    // gal - recipient of the dai
    // lot - amount of mkr to mint
    // bid - amount of dai to pay
    // id - id of the auction
    function kick(address gal, uint256 lot, uint256 bid) external returns (uint256 id);

    // extend the auction and increase minimum maker amount minted
    // access control: not-authed
    // state machine: after auction expiry, before first bid
    // id - id of the auction
    function tick(uint256 id) external;

    // bid up auction and refund locked up dai to previous bidder
    // access control: not-authed
    // state machine: before auction expired
    // id - id of the auction
    // lot - amount of mkr to mint
    // bid - amount of dai to pay
    function dent(uint256 id, uint256 lot, uint256 bid) external;

    // finalize auction
    // access control: not-authed
    // state machine: after auction expired
    // id - id of the auction
    function deal(uint256 id) external;

    // --- Shutdown ---

    // shutdown flopper mechanism
    // access control: authed
    // state machine: anytime
    function cage() external;

    // get cancelled bid back
    // access control: authed
    // state machine: after shutdown
    function yank(uint256 id) external;
}