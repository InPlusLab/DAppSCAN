pragma solidity ^0.4.18;

import "./IProductStorage.sol";
import "./IFeePolicy.sol";
import "../common/Manageable.sol";
import "../common/SafeMathLib.sol";
import "../token/IERC20Token.sol";

/**@dev Calculates fee details. Takes into account BCS tokens that grant fee discount */
contract FeePolicy is Manageable {

    using SafeMathLib for uint256;
    

    //
    // Storage data

    uint16 constant MAXPERMILLE = 1000;

    IProductStorage public productStorage;
    uint16 public defaultFee;               //default fee for genereal products (permille)
    uint16 public escrowFee;                //additional fee for escrow usage (permille)
    //uint256 public minEscrowFeePermille;    //minimum escrow fee permille in weis, can't be discounted further
    uint16 public fiatPriceFee;             //additional fee for fiat price usage (permille)
    address public feeWallet;
    
    IERC20Token public token;               // token to check minimum token balance
    uint256 public minTokenForDiscount;     // min token amount to get fee discount
    uint256 public termDuration;            // term duration in seconds
    uint256 public maxDiscountPerToken;     // max total fee discount/token per term in weis (Y from the docs)
    uint16 public discount;                 // discount permille [0-1000] (X from the docs)
    mapping(address=>mapping(uint256=>uint256)) public totalFeeDiscount; // total fee for combination of vendor+term

    uint256 denominator;                    //maxDiscountPerToken*tokens/denominator = maxTotalDiscount per term


    //
    // Modifiers

    modifier validPermille(uint16 value) {
        require(value <= MAXPERMILLE);
        _;
    }



    //
    // Methods

    function FeePolicy(
        IProductStorage _productStorage,
        uint16 _defaultFeePermille, 
        uint16 _escrowFeePermille,        
        uint16 _fiatPriceFeePermille,
        address _feeWallet,        
        IERC20Token _token,
        uint256 _minTokenForDiscount,
        uint256 _termDuration,
        uint256 _maxDiscountPerToken,
        uint16 _discountPermille
    ) 
        public 
    {        
        require(_termDuration > 0);
        
        productStorage = _productStorage;
        termDuration = _termDuration;

        setParams(
            _defaultFeePermille,
            _escrowFeePermille,
            _fiatPriceFeePermille,
            _feeWallet,
            _token,
            _minTokenForDiscount,        
            _maxDiscountPerToken,
            _discountPermille
        );
    }

    /**@dev Returns total fee amount depending on payment */
    function getFeeDetails(address owner, uint256 productId, uint256 payment) 
        public 
        constant 
        returns(uint256 feeAmount, uint256 feeDiscount) 
    {
        uint16 fee = productStorage.getVendorFee(owner);
        if(fee == 0) {
            fee = defaultFee;
        }

        if(productStorage.isEscrowUsed(productId)) {
            fee = fee + escrowFee;
        }

        if(productStorage.isFiatPriceUsed(productId)) {
            fee = fee + fiatPriceFee;
        }

        if(fee >= MAXPERMILLE) {
            fee = MAXPERMILLE;
        }

        feeAmount = payment.safeMult(uint256(fee)) / MAXPERMILLE;
        feeDiscount = 0;
        //check if we should apply discount for fee
        if(token.balanceOf(owner) >= minTokenForDiscount) {
            feeDiscount = feeAmount.safeMult(uint256(discount)) / MAXPERMILLE;

            uint256 remainingDiscount = getRemainingDiscount(owner);
            if(feeDiscount > remainingDiscount) {
                feeDiscount = remainingDiscount;
            }
            feeAmount = feeAmount.safeSub(feeDiscount);
        }        
    }

    /**@dev Returns max fee discount that can be accumulated during every term */
    function getMaxTotalDiscount(address owner) public constant returns (uint256) {
        return maxDiscountPerToken.safeMult(token.balanceOf(owner)) / denominator;
    }


    /**@dev Returns remaining discount for the current term */
    function getRemainingDiscount(address owner) public constant returns(uint256) {
        uint256 term = now / termDuration;  //current term #
        uint256 maxTotalDiscount = getMaxTotalDiscount(owner);

        if(totalFeeDiscount[owner][term] < maxTotalDiscount) {
            return maxTotalDiscount - totalFeeDiscount[owner][term];            
        } else {
            return 0;
        }
    }

    /**@dev Returns extended information about remaining discount: discount + timestamp when current term expires */
    function getRemainingDiscountInfo(address owner) public constant returns(uint256, uint256) {
        return (
            getRemainingDiscount(owner), 
            (now / termDuration + 1) * termDuration
        );
    }

    /**@dev Calculates and returns fee amount. Stores calculated discount for the current term  */
    function calculateFeeAmount(address owner, uint256 productId, uint256 payment) public managerOnly returns(uint256) {
        var (feeAmount, feeDiscount) = getFeeDetails(owner, productId, payment);
        
        if(feeDiscount > 0) {
            uint256 term = now / termDuration;
            totalFeeDiscount[owner][term] = totalFeeDiscount[owner][term].safeAdd(feeDiscount);
        }
        
        return feeAmount;
    }

    /**@dev Sends fee amount equal to msg.value to a single fee wallet  */
    function sendFee() public payable {
        feeWallet.transfer(msg.value);
    }

    /**@dev Sets new parameters values */
    function setParams(
        uint16 _defaultFeePermille, 
        uint16 _escrowFeePermille,
        uint16 _fiatPriceFeePermille,
        address _feeWallet,
        IERC20Token _token,
        uint256 _minTokenForDiscount,        
        uint256 _maxDiscountPerToken,
        uint16 _discountPermille
    ) 
        public 
        ownerOnly
        validPermille(_defaultFeePermille)
        validPermille(_escrowFeePermille)
        validPermille(_fiatPriceFeePermille)
        validPermille(_discountPermille)

    {
        require(_defaultFeePermille + _escrowFeePermille + _fiatPriceFeePermille <= 1000);

        defaultFee = _defaultFeePermille;
        escrowFee = _escrowFeePermille;
        fiatPriceFee = _fiatPriceFeePermille;
        feeWallet = _feeWallet;
        token = _token;
        minTokenForDiscount = _minTokenForDiscount;
        maxDiscountPerToken = _maxDiscountPerToken;
        discount = _discountPermille;

        denominator = uint256(10) ** token.decimals();
    }
}