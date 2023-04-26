import 'openzeppelin-solidity/contracts/token/ERC20/ERC20.sol';
import 'openzeppelin-solidity/contracts/math/SafeMath.sol';

import './Loans.sol';
import './Medianizer.sol';
import './DSMath.sol';

pragma solidity ^0.5.10;

contract Sales is DSMath {
    FundsInterface funds;
    Loans loans;
    Medianizer med;

    uint256 public constant SWAP_EXP = 2 hours;       // Swap Expiration
    uint256 public constant SETTLEMENT_EXP = 4 hours; // Settlement Expiration

	address public deployer; // Only the Loans contract can edit data

	mapping (bytes32 => Sale)       public sales;        // Auctions
	mapping (bytes32 => Sig)        public borrowerSigs; // Borrower Signatures
	mapping (bytes32 => Sig)        public lenderSigs;   // Lender Signatures
	mapping (bytes32 => Sig)        public arbiterSigs;  // Lender Signatures
	mapping (bytes32 => SecretHash) public secretHashes; // Auction Secret Hashes
    uint256                         public saleIndex;    // Auction Index

    mapping (bytes32 => bytes32[])  public saleIndexByLoan; // Loan Auctions (find by loanIndex)

    mapping(bytes32 => bool) revealed;

    ERC20 public token;

    /**
     * @notice Container for the sale information
     * @member loanIndex The Id of the loan
     * @member discountBuy The amount in tokens that the Bitcoin collateral was bought for at discount
     * @member liquidator The address of the liquidator (party that buys the Bitcoin collateral at a discount)
     * @member borrower The address of the borrower
     * @member lender The address of the lender
     * @member arbiter The address of the arbiter
     * @member createAt The creation timestamp of the sale
     * @member pubKeyHash The Bitcoin Public Key Hash of the liquidator
     * @member set Indicates that the sale at this specific index has been opened
     * @member accepted Indicates that the discountBuy has been accepted
     * @member off Indicates that the is failed
     */
    struct Sale {
        bytes32    loanIndex;
        uint256    discountBuy;
        address    liquidator;
        address    borrower;
        address    lender;
        address    arbiter;
        uint256    createdAt;
        bytes20    pubKeyHash;
        bool       set;
        bool       accepted;
        bool       off;
    }

    /**
     * @notice Container for the Bitcoin refundable and seizable signature information
     * @member refundableSig The Bitcoin refundable signature to move collateral to swap P2WSH
     * @member seizableSig The Bitcoin seizable signature to move collateral to swap P2WSH
     */
    struct Sig {
        bytes refundableSig;
        bytes seizableSig;
    }

    /**
     * @notice Container for the Bitcoin Secret and Secret Hashes information
     */
    struct SecretHash {
        bytes32 secretHashA; // Secret Hash A
        bytes32 secretA;     // Secret A
        bytes32 secretHashB; // Secret Hash B
        bytes32 secretB;     // Secret B
        bytes32 secretHashC; // Secret Hash C
        bytes32 secretC;     // Secret C
        bytes32 secretHashD; // Secret Hash D
        bytes32 secretD;     // Secret D
    }

    function discountBuy(bytes32 sale) public view returns (uint256) {
        return sales[sale].discountBuy;
    }

    function swapExpiration(bytes32 sale) public view returns (uint256) {
        return sales[sale].createdAt + SWAP_EXP;
    }

    function settlementExpiration(bytes32 sale) public view returns (uint256) {
        return sales[sale].createdAt + SETTLEMENT_EXP;
    }

    function accepted(bytes32 sale) public view returns (bool) {
        return sales[sale].accepted;
    }

    function off(bytes32 sale) public view returns (bool) {
        return sales[sale].off;
    }

    constructor (Loans loans_, FundsInterface funds_, Medianizer med_, ERC20 token_) public {
    	deployer = address(loans_);
    	loans    = loans_;
        funds    = funds_;
        med      = med_;
        token    = token_;
        require(token.approve(address(funds), 2**256-1));
    }

    function next(bytes32 loan) public view returns (uint256) {
    	return saleIndexByLoan[loan].length;
    }

    /**
     * @dev Creates a new sale (called by the Loans contract)
     * @param loanIndex The Id of the Loan
     * @param borrower The address of the borrower
     * @param lender The address of the lender
     * @param arbiter The address of the arbiter
     * @param liquidator The address of the liquidator
     * @param secretHashA The Secret Hash of the Borrower for the current sale number
     * @param secretHashB The Secret Hash of the Lender for the current sale number
     * @param secretHashC The Secret Hash of the Arbiter for the current sale number
     * @param secretHashD the Secret Hash of the Liquidator
     * @param pubKeyHash The Bitcoin Public Key Hash of the Liquidator
     * @return sale The Id of the sale
     */
    function create(
        bytes32 loanIndex,
        address borrower,
        address lender,
        address arbiter,
        address liquidator,
        bytes32 secretHashA,
        bytes32 secretHashB,
        bytes32 secretHashC,
        bytes32 secretHashD,
        bytes20 pubKeyHash
        ) external returns(bytes32 sale) {
        require(msg.sender == address(loans));
        saleIndex = add(saleIndex, 1);
        sale = bytes32(saleIndex);
        sales[sale].loanIndex   = loanIndex;
        sales[sale].borrower    = borrower;
        sales[sale].lender      = lender;
        sales[sale].arbiter       = arbiter;
        sales[sale].liquidator  = liquidator;
        sales[sale].createdAt   = now;
        sales[sale].pubKeyHash  = pubKeyHash;
        sales[sale].discountBuy = loans.ddiv(loans.discountCollateralValue(loanIndex));
        sales[sale].set         = true;
        secretHashes[sale].secretHashA = secretHashA;
        secretHashes[sale].secretHashB = secretHashB;
        secretHashes[sale].secretHashC = secretHashC;
        secretHashes[sale].secretHashD = secretHashD;
        saleIndexByLoan[loanIndex].push(sale);
   }

    /**
     * @notice Provide Bitcoin signatures for moving collateral to collateral swap script
     * @param sale The Id of the sale
     * @param refundableSig The Bitcoin refundable collateral signature
     * @param seizableSig The Bitcoin seizable collateral signature
     *
     *         Note: More info on the collateral swap script can be seen here:
                     https://github.com/AtomicLoans/chainabstractionlayer-loans
                     */
    function provideSig(
        bytes32        sale,
        bytes calldata refundableSig,
        bytes calldata seizableSig
    ) external {
        require(sales[sale].set);
        require(now < settlementExpiration(sale));
        if (msg.sender == sales[sale].borrower) {
            borrowerSigs[sale].refundableSig = refundableSig;
            borrowerSigs[sale].seizableSig   = seizableSig;
        } else if (msg.sender == sales[sale].lender) {
            lenderSigs[sale].refundableSig = refundableSig;
            lenderSigs[sale].seizableSig   = seizableSig;
        } else if (msg.sender == sales[sale].arbiter) {
            arbiterSigs[sale].refundableSig = refundableSig;
            arbiterSigs[sale].seizableSig   = seizableSig;
        } else {
            revert();
        }
    }

    /**
     * @notice Provide secret to enable liquidator to claim collateral
     * @param secret_ The secret provided by the borrower, lender, arbiter, or liquidator
     */
    function provideSecret(bytes32 sale, bytes32 secret_) public {
        require(sales[sale].set);
        bytes32 secretHash = sha256(abi.encodePacked(secret_));
        revealed[secretHash] = true;
        if (secretHash == secretHashes[sale].secretHashA) { secretHashes[sale].secretA = secret_; }
        if (secretHash == secretHashes[sale].secretHashB) { secretHashes[sale].secretB = secret_; }
        if (secretHash == secretHashes[sale].secretHashC) { secretHashes[sale].secretC = secret_; }
        if (secretHash == secretHashes[sale].secretHashD) { secretHashes[sale].secretD = secret_; }
    }

    /**
     * @dev Indicates that two of Secret A, Secret B, Secret C have been submitted
     * @param sale The Id of the sale
     */
    function hasSecrets(bytes32 sale) public view returns (bool) {
        uint8 numCorrectSecrets = 0;
        if (revealed[secretHashes[sale].secretHashA]) { numCorrectSecrets += 1; }
        if (revealed[secretHashes[sale].secretHashB]) { numCorrectSecrets += 1; }
        if (revealed[secretHashes[sale].secretHashC]) { numCorrectSecrets += 1; }
        return (numCorrectSecrets >= 2);
    }

    /**
     * @notice Accept discount buy by liquidator and disperse funds to rightful parties
     * @param sale The Id of the sale
     */
    function accept(bytes32 sale) public {
        require(!accepted(sale));
        require(!off(sale));
        require(hasSecrets(sale));
        require(revealed[secretHashes[sale].secretHashD]);
        sales[sale].accepted = true;

        uint256 available = add(sales[sale].discountBuy, loans.repaid(sales[sale].loanIndex));

        if (sales[sale].arbiter != address(0) && available >= loans.fee(sales[sale].loanIndex)) {
            require(token.transfer(sales[sale].arbiter, loans.fee(sales[sale].loanIndex)));
            available = sub(available, loans.fee(sales[sale].loanIndex));
        }

        uint256 amount = min(available, loans.owedToLender(sales[sale].loanIndex));

        if (loans.fundIndex(sales[sale].loanIndex) == bytes32(0)) {
            require(token.transfer(sales[sale].lender, amount));
        } else {
            funds.deposit(loans.fundIndex(sales[sale].loanIndex), amount);
        }

        available = sub(available, amount);

        if (available >= loans.penalty(sales[sale].loanIndex)) {
            require(token.approve(address(med), loans.penalty(sales[sale].loanIndex)));
            med.fund(loans.penalty(sales[sale].loanIndex), token);
            available = sub(available, loans.penalty(sales[sale].loanIndex));
        } else if (available > 0) {
            require(token.approve(address(med), available));
            med.fund(available, token);
            available = 0;
        }

        if (available > 0) { require(token.transfer(sales[sale].borrower, available)); }
    }

    function provideSecretsAndAccept(bytes32 sale, bytes32[3] calldata secrets_) external {
        provideSecret(sale, secrets_[0]);
        provideSecret(sale, secrets_[1]);
        provideSecret(sale, secrets_[2]);
        accept(sale);
    }

    /**
     * @notice Refund discount buy to liquidator
     * @param sale The Id of the sale
     */
    function refund(bytes32 sale) external {
        require(!accepted(sale));
        require(!off(sale));
        require(now > settlementExpiration(sale));
        require(sales[sale].discountBuy > 0);
        sales[sale].off = true;
        require(token.transfer(sales[sale].liquidator, sales[sale].discountBuy));
        if (next(sales[sale].loanIndex) == 3) {
            require(token.transfer(sales[sale].borrower, loans.repaid(sales[sale].loanIndex)));
        }
    }
}