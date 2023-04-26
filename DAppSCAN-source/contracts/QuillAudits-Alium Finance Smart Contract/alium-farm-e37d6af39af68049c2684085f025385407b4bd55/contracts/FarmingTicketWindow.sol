pragma solidity =0.6.12;

import "@alium-official/alium-swap-lib/contracts/math/SafeMath.sol";
import "@alium-official/alium-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@alium-official/alium-swap-lib/contracts/token/BEP20/SafeBEP20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IAliumCollectible.sol";

contract FarmingTicketWindow is Ownable {
    using SafeBEP20 for IBEP20;

    uint256 public constant TICKET_PRICE = 1500e18; // 1500 ALM
    address public immutable alm;
    address public immutable nft;
    address public founder;

    mapping (address => bool) public hasTicket;

    event TicketBought(address);
    event EntranceAllowed(address);
    event FounderSet(address);

    constructor(address _almToken, address _nft, address _founderWallet) public {
        require(
            _almToken != address(0) &&
            _nft != address(0) &&
            _founderWallet != address(0),
            "TicketWindow: constructor sets"
        );

        alm = _almToken;
        nft = _nft;
        founder = _founderWallet;
    }

    function buyTicket() external notTicketHolder {
        address buyer = _msgSender();
        IBEP20(alm).safeTransferFrom(buyer, founder, TICKET_PRICE);
        hasTicket[buyer] = true;
        IAliumCollectible(nft).mint(buyer);
        emit TicketBought(buyer);
    }

    function passFree(address _account) external onlyOwner {
        require(!hasTicket[_account], "TicketWindow: account already has ticket");

        hasTicket[_account] = true;
        emit EntranceAllowed(_account);
    }

    function passFreeBatch(address[] memory _accounts) external onlyOwner {
        uint l = _accounts.length;
        for (uint i; i < l; i++) {
            if (!hasTicket[_accounts[i]]) {
                hasTicket[_accounts[i]] = true;
                emit EntranceAllowed(_accounts[i]);
            }
        }
    }

    function setFounder(address _founder) external {
        require(msg.sender == founder, "TicketWindow: founder wut?");
        require(_founder != address(0), "TicketWindow: zero address set");
        require(_founder != founder, "TicketWindow: the same address");

        founder = _founder;
        emit FounderSet(_founder);
    }

    modifier notTicketHolder() {
        require(
            !hasTicket[msg.sender],
            "TicketWindow: already has ticket"
        );
        _;
    }
}