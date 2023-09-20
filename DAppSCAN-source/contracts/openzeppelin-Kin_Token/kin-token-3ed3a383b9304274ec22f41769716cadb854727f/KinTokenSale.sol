pragma solidity ^0.4.15;

import './SafeMath.sol';
import './Ownable.sol';
import './TokenHolder.sol';
import './KinToken.sol';
import './VestingTrustee.sol';

/// @title Kin token sale contract.
contract KinTokenSale is Ownable, TokenHolder {
    using SafeMath for uint256;

    // External parties:

    // KIN token contract.
    KinToken public kin;

    // Vesting contract for pre-sale participants.
    VestingTrustee public trustee;

    // Received funds are forwarded to this address.
    address public fundingRecipient;

    // Kin token decimals.
    // Using same decimal value as ETH (makes ETH-KIN conversion much easier).
    // This is the same as in Kin token contract.
    uint256 public constant TOKEN_DECIMALS = 10 ** 18;

    // Maximum number of tokens in circulation: 10 trillion.
    uint256 public constant MAX_TOKENS = 10 ** 13 * TOKEN_DECIMALS;

    // Maximum tokens offered in the sale.
    uint256 public constant MAX_TOKENS_SOLD = 512192121951 * TOKEN_DECIMALS;

    // Wei to 1 USD ratio.
    //
    // TODO update to the real ETH price before sale launch.
    uint256 public constant WEI_PER_USD = uint256(1 ether) / 360;

    // KIN to 1 USD ratio,
    // such MAX_TOKENS_SOLD * KIN_PER_USD is the $75M cap.
    uint256 public constant KIN_PER_USD = 6829 * TOKEN_DECIMALS;

    // KIN to 1 wei ratio.
    uint256 public constant KIN_PER_WEI = KIN_PER_USD / WEI_PER_USD;

    // Sale start, end blocks (time ranges)
    uint256 public constant SALE_DURATION = 14 days;
    uint256 public startTime;
    uint256 public endTime;

    // Amount of tokens sold until now in the sale.
    uint256 public tokensSold = 0;

    // Participation caps, according to KYC tiers.
    uint256 public constant TIER_1_CAP = 100000 * WEI_PER_USD;
    uint256 public constant TIER_2_CAP = uint256(-1); // Maximum uint256 value

    // Accumulated amount each participant have contributed so far.
    mapping (address => uint256) public participationHistory;

    // Maximum amount that each particular is allowed to contribute (in WEI).
    mapping (address => uint256) public participationCaps;

    // Maximum amount ANYBODY is currently allowed to contribute.
    uint256 public hardParticipationCap = 5000 * WEI_PER_USD;

    // Vesting information for special addresses:
    struct TokenGrant {
        uint256 value;
        uint256 startOffset;
        uint256 cliffOffset;
        uint256 endOffset;
        uint256 installmentLength;
        uint8 percentVested;
    }

    address[] public tokenGrantees;
    mapping (address => TokenGrant) public tokenGrants;
    uint256 public lastGrantedIndex = 0;
    uint256 public constant GRANT_BATCH_SIZE = 10;

    // Post-TDE multisig addresses.
    //
    // TODO: add real addresses here.
    address public constant KIN_FOUNDATION_ADDRESS = 0xa8F769B88d6D74FB2Bd3912F6793F75625228baF;
    address public constant KIK_ADDRESS = 0x7a029DC995f87B5cA060975b9A8A1b4bdB33cDC5;

    event TokensIssued(address indexed _to, uint256 _tokens);

    /// @dev Reverts if called when not during sale.
    modifier onlyDuringSale() {
        if (tokensSold >= MAX_TOKENS_SOLD || now < startTime || now >= endTime) {
            revert();
        }

        _;
    }

    /// @dev Reverts if called before sale ends.
    modifier onlyAfterSale() {
        if (!(tokensSold >= MAX_TOKENS_SOLD || now >= endTime)) {
            revert();
        }

        _;
    }

    /// @dev Constructor that initializes the sale conditions.
    /// @param _fundingRecipient address The address of the funding recipient.
    /// @param _startTime uint256 The start time of the token sale.
    function KinTokenSale(address _fundingRecipient, uint256 _startTime) {
        require(_fundingRecipient != address(0));
        require(_startTime > now);

        // Deploy new KinToken contract.
        kin = new KinToken();

        // Deploy new VestingTrustee contract.
        trustee = new VestingTrustee(kin);

        fundingRecipient = _fundingRecipient;
        startTime = _startTime;
        endTime = startTime + SALE_DURATION;

        // Initialize special vesting grants.
        initTokenGrants();
    }

    /// @dev Initialize token grants.
    ///
    /// TODO: add real values here.
    function initTokenGrants() private onlyOwner {
        // Issue the remaining 60% to Kin Foundation's multisig wallet. In a few days, after the token sale is
        // finalized, these tokens will be loaded into the KinVestingTrustee smart contract, according to the white
        // paper. Please note, that this is implied by setting a 0% vesting percent.
        tokenGrantees.push(KIN_FOUNDATION_ADDRESS);
        tokenGrants[KIN_FOUNDATION_ADDRESS] = TokenGrant(60 * 100000000000 * TOKEN_DECIMALS, 0, 0, 3 years, 1 days, 0);

        // Kik, 30%
        tokenGrantees.push(KIK_ADDRESS);
        tokenGrants[KIK_ADDRESS] = TokenGrant(30 * 100000000000 * TOKEN_DECIMALS, 0, 0, 120 weeks, 12 weeks, 100);
    }
//SWC-128-DoS With Block Gas Limit:L148-161、165-179
    /// @dev Adds a Kin token vesting grant.
    /// @param _grantee address The address of the token grantee. Can be granted only once.
    /// @param _value uint256 The value of the grant.
    function addTokenGrant(address _grantee, uint256 _value) external onlyOwner {
        require(_grantee != address(0));
        require(_value > 0);

        // Verify the grant doesn't already exist.
        require(tokenGrants[_grantee].value == 0);
        for (uint i = 0; i < tokenGrantees.length; i++) {
            require(tokenGrantees[i] != _grantee);
        }

        // Add grant and add to grantee list.
        tokenGrantees.push(_grantee);
        tokenGrants[_grantee] = TokenGrant(_value, 0, 1 years, 1 years, 1 days, 50);
    }

    /// @dev Deletes a Kin token grant.
    /// @param _grantee address The address of the token grantee.
    function deleteTokenGrant(address _grantee) external onlyOwner {
        require(_grantee != address(0));

        // Delete the grant from the keys array.
        for (uint i = 0; i < tokenGrantees.length; i++) {
            if (tokenGrantees[i] == _grantee) {
                delete tokenGrantees[i];

                break;
            }
        }

        // Delete the grant from the mapping.
        delete tokenGrants[_grantee];
    }

    /// @dev Add a list of participants to a capped participation tier.
    /// @param _participants address[] The list of participant addresses.
    /// @param _cap uint256 The cap amount (in ETH).
    function setParticipationCap(address[] _participants, uint256 _cap) private onlyOwner {
        for (uint i = 0; i < _participants.length; i++) {
            participationCaps[_participants[i]] = _cap;
        }
    }

    /// @dev Add a list of participants to cap tier #1.
    /// @param _participants address[] The list of participant addresses.
    function setTier1Participants(address[] _participants) external onlyOwner {
        setParticipationCap(_participants, TIER_1_CAP);
    }

    /// @dev Add a list of participants to tier #2.
    /// @param _participants address[] The list of participant addresses.
    function setTier2Participants(address[] _participants) external onlyOwner {
        setParticipationCap(_participants, TIER_2_CAP);
    }

    /// @dev Set hard participation cap for all participants.
    /// @param _cap uint256 The hard cap amount.
    function setHardParticipationCap(uint256 _cap) external onlyOwner {
        require(_cap > 0);

        hardParticipationCap = _cap;
    }

    /// @dev Fallback function that will delegate the request to create().
    function () external payable onlyDuringSale {
        create(msg.sender);
    }

    /// @dev Create and sell tokens to the caller.
    /// @param _recipient address The address of the recipient receiving the tokens.
    function create(address _recipient) public payable onlyDuringSale {
        require(_recipient != address(0));

        // Enforce participation cap (in Wei received).
        uint256 weiAlreadyParticipated = participationHistory[msg.sender];
        uint256 participationCap = SafeMath.min256(participationCaps[msg.sender], hardParticipationCap);
        uint256 cappedWeiReceived = SafeMath.min256(msg.value, participationCap.sub(weiAlreadyParticipated));
        require(cappedWeiReceived > 0);

        // Accept funds and transfer to funding recipient.
        uint256 weiLeftInSale = MAX_TOKENS_SOLD.sub(tokensSold).div(KIN_PER_WEI);
        uint256 weiToParticipate = SafeMath.min256(cappedWeiReceived, weiLeftInSale);
        participationHistory[msg.sender] = weiAlreadyParticipated.add(weiToParticipate);
        fundingRecipient.transfer(weiToParticipate);

        // Issue tokens and transfer to recipient.
        uint256 tokensLeftInSale = MAX_TOKENS_SOLD.sub(tokensSold);
        uint256 tokensToIssue = weiToParticipate.mul(KIN_PER_WEI);
        if (tokensLeftInSale.sub(tokensToIssue) < KIN_PER_WEI) {
            // If purchase would cause less than KIN_PER_WEI tokens left then nobody could ever buy them.
            // So, gift them to the last buyer.
            tokensToIssue = tokensLeftInSale;
        }
        tokensSold = tokensSold.add(tokensToIssue);
        issueTokens(_recipient, tokensToIssue);

        // Partial refund if full participation not possible
        // e.g. due to cap being reached.
        uint256 refund = msg.value.sub(weiToParticipate);
        if (refund > 0) {
            msg.sender.transfer(refund);
        }
    }

    /// @dev Finalizes the token sale event, by stopping token minting.
    function finalize() external onlyAfterSale onlyOwner {
        if (!kin.isMinting()) {
            revert();
        }

        require(lastGrantedIndex == tokenGrantees.length);

        // Finish minting.
        kin.endMinting();
    }

    /// @dev Grants pre-configured token grants in batches. When the method is called, it'll resume from the last grant,
    /// from its previous run, and will finish either after granting GRANT_BATCH_SIZE grants or finishing the whole list
    /// of grants.
    function grantTokens() external onlyAfterSale onlyOwner {
        uint endIndex = SafeMath.min256(tokenGrantees.length, lastGrantedIndex + GRANT_BATCH_SIZE);
        for (uint i = lastGrantedIndex; i < endIndex; i++) {
            address grantee = tokenGrantees[i];

            // Calculate how many tokens have been granted, vested, and issued such that: granted = vested + issued.
            TokenGrant memory tokenGrant = tokenGrants[grantee];
            uint256 tokensGranted = tokenGrant.value.mul(tokensSold).div(MAX_TOKENS_SOLD);
            uint256 tokensVested = tokensGranted.mul(tokenGrant.percentVested).div(100);
            uint256 tokensIssued = tokensGranted.sub(tokensVested);

            // Transfer issued tokens that have yet to be transferred to grantee.
            if (tokensIssued > 0) {
                issueTokens(grantee, tokensIssued);
            }

            // Transfer vested tokens that have yet to be transferred to vesting trustee, and initialize grant.
            if (tokensVested > 0) {
                issueTokens(trustee, tokensVested);
                trustee.grant(grantee, tokensVested, now.add(tokenGrant.startOffset), now.add(tokenGrant.cliffOffset),
                    now.add(tokenGrant.endOffset), tokenGrant.installmentLength, true);
            }

            lastGrantedIndex++;
        }
    }

    /// @dev Issues tokens for the recipient.
    /// @param _recipient address The address of the recipient.
    /// @param _tokens uint256 The amount of tokens to issue.
    function issueTokens(address _recipient, uint256 _tokens) private {
        // Request Kin token contract to mint the requested tokens for the buyer.
        kin.mint(_recipient, _tokens);

        TokensIssued(_recipient, _tokens);
    }

    /// @dev Requests to transfer control of the Kin token contract to a new owner.
    /// @param _newOwnerCandidate address The address to transfer ownership to.
    ///
    /// NOTE:
    ///   1. The new owner will need to call Kin token contract's acceptOwnership directly in order to accept the ownership.
    ///   2. Calling this method during the token sale will prevent the token sale to continue, since only the owner of
    ///      the Kin token contract can issue new tokens.
    function requestKinTokenOwnershipTransfer(address _newOwnerCandidate) external onlyOwner {
        kin.requestOwnershipTransfer(_newOwnerCandidate);
    }

    /// @dev Accepts new ownership on behalf of the Kin token contract.
    // This can be used by the sale contract itself to claim back ownership of the Kin token contract.
    function acceptKinTokenOwnership() external onlyOwner {
        kin.acceptOwnership();
    }

    /// @dev Requests to transfer control of the VestingTrustee contract to a new owner.
    /// @param _newOwnerCandidate address The address to transfer ownership to.
    ///
    /// NOTE:
    ///   1. The new owner will need to call VestingTrustee's acceptOwnership directly in order to accept the ownership.
    ///   2. Calling this method during the token sale will prevent the token sale from finalizaing, since only the owner
    ///      of the VestingTrustee contract can issue new token grants.
    function requestVestingTrusteeOwnershipTransfer(address _newOwnerCandidate) external onlyOwner {
        trustee.requestOwnershipTransfer(_newOwnerCandidate);
    }

    /// @dev Accepts new ownership on behalf of the VestingTrustee contract.
    /// This can be used by the token sale contract itself to claim back ownership of the VestingTrustee contract.
    function acceptVestingTrusteeOwnership() external onlyOwner {
        trustee.acceptOwnership();
    }
}
