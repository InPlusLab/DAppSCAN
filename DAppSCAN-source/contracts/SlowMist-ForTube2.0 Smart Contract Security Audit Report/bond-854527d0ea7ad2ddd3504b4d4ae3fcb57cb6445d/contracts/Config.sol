pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;


interface IACL {
    function accessible(address sender, address to, bytes4 sig)
        external
        view
        returns (bool);
}


contract Config {
    address public ACL;

    constructor(address _ACL) public {
        ACL = _ACL;
    }

    modifier auth {
        require(
            IACL(ACL).accessible(msg.sender, address(this), msg.sig),
            "access unauthorized"
        );
        _;
    }

    function setACL(address _ACL) external {
        require(msg.sender == ACL, "require ACL");
        ACL = _ACL;
    }

    uint256 public voteDuration;
    uint256 public depositDuration;
    uint256 public investDuration;
    uint256 public gracePeriod; //宽限期

    uint256 public ratingFeeRatio; //划分手续费中的投票收益占比

    struct DepositTokenArgument {
        uint256 discount; //折扣    0.85 => 0.85 * 1e18
        uint256 liquidateLine; //清算线  70% => 0.7 * 1e18
        uint256 depositMultiple; //质押倍数
    }

    struct IssueTokenArgument {
        uint256 partialLiquidateAmount;
    }

    struct IssueAmount {
        uint256 maxIssueAmount; //单笔债券最大发行数量
        uint256 minIssueAmount; //单笔债券最小发行数量
    }

    //deposit token => issuetoken => amount;
    mapping(address => mapping(address => IssueAmount)) public issueAmounts;
    mapping(address => DepositTokenArgument) public depositTokenArguments;
    mapping(address => IssueTokenArgument) public issueTokenArguments;

    function setRatingFeeRatio(uint256 ratio) external auth {
        ratingFeeRatio = ratio;
    }

    function setVoteDuration(uint256 sec) external auth {
        voteDuration = sec;
    }

    function setDepositDuration(uint256 sec) external auth {
        depositDuration = sec;
    }

    function setInvestDuration(uint256 sec) external auth {
        investDuration = sec;
    }

    function setGrasePeriod(uint256 period) external auth {
        gracePeriod = period;
    }

    function setDiscount(address token, uint256 discount) external auth {
        depositTokenArguments[token].discount = discount;
    }

    function discount(address token) external view returns (uint256) {
        return depositTokenArguments[token].discount;
    }

    function setLiquidateLine(address token, uint256 line) external auth {
        depositTokenArguments[token].liquidateLine = line;
    }

    function liquidateLine(address token) external view returns (uint256) {
        return depositTokenArguments[token].liquidateLine;
    }

    function setDepositMultiple(address token, uint256 depositMultiple)
        external
        auth
    {
        depositTokenArguments[token].depositMultiple = depositMultiple;
    }

    function depositMultiple(address token) external view returns (uint256) {
        return depositTokenArguments[token].depositMultiple;
    }

    function setMaxIssueAmount(
        address depositToken,
        address issueToken,
        uint256 maxIssueAmount
    ) external auth {
        issueAmounts[depositToken][issueToken].maxIssueAmount = maxIssueAmount;
    }

    function maxIssueAmount(address depositToken, address issueToken)
        external
        view
        returns (uint256)
    {
        return issueAmounts[depositToken][issueToken].maxIssueAmount;
    }

    function setMinIssueAmount(
        address depositToken,
        address issueToken,
        uint256 minIssueAmount
    ) external auth {
        issueAmounts[depositToken][issueToken].minIssueAmount = minIssueAmount;
    }

    function minIssueAmount(address depositToken, address issueToken)
        external
        view
        returns (uint256)
    {
        return issueAmounts[depositToken][issueToken].minIssueAmount;
    }

    function setPartialLiquidateAmount(
        address token,
        uint256 _partialLiquidateAmount
    ) external auth {
        issueTokenArguments[token]
            .partialLiquidateAmount = _partialLiquidateAmount;
    }

    function partialLiquidateAmount(address token)
        external
        view
        returns (uint256)
    {
        return issueTokenArguments[token].partialLiquidateAmount;
    }

    uint256 public professionalRatingWeightRatio; // professional-Rating Weight Ratio;
    uint256 public communityRatingWeightRatio; // community-Rating Weight Ratio;

    function setProfessionalRatingWeightRatio(
        uint256 _professionalRatingWeightRatio
    ) external auth {
        professionalRatingWeightRatio = _professionalRatingWeightRatio;
    }

    function setCommunityRatingWeightRatio(uint256 _communityRatingWeightRatio)
        external
        auth
    {
        communityRatingWeightRatio = _communityRatingWeightRatio;
    }

    /** verify */

    //支持发债的代币列表
    mapping(address => bool) public depositTokenCandidates;
    //支持融资的代币列表
    mapping(address => bool) public issueTokenCandidates;
    //发行费用
    mapping(uint256 => bool) public issueFeeCandidates;
    //一期的利率
    mapping(uint256 => bool) public interestRateCandidates;
    //债券期限
    mapping(uint256 => bool) public maturityCandidates;
    //最低发行比率
    mapping(uint256 => bool) public minIssueRatioCandidates;
    //可评级的地址选项
    mapping(address => bool) public ratingCandidates;

    function setDepositTokenCandidates(address[] calldata tokens, bool enable)
        external
        auth
    {
        for (uint256 i = 0; i < tokens.length; ++i) {
            depositTokenCandidates[tokens[i]] = enable;
        }
    }

    function setIssueTokenCandidates(address[] calldata tokens, bool enable)
        external
        auth
    {
        for (uint256 i = 0; i < tokens.length; ++i) {
            issueTokenCandidates[tokens[i]] = enable;
        }
    }

    function setIssueFeeCandidates(uint256[] calldata issueFees, bool enable)
        external
        auth
    {
        for (uint256 i = 0; i < issueFees.length; ++i) {
            issueFeeCandidates[issueFees[i]] = enable;
        }
    }

    function setInterestRateCandidates(
        uint256[] calldata interestRates,
        bool enable
    ) external auth {
        for (uint256 i = 0; i < interestRates.length; ++i) {
            interestRateCandidates[interestRates[i]] = enable;
        }
    }

    function setMaturityCandidates(uint256[] calldata maturities, bool enable)
        external
        auth
    {
        for (uint256 i = 0; i < maturities.length; ++i) {
            maturityCandidates[maturities[i]] = enable;
        }
    }

    function setMinIssueRatioCandidates(
        uint256[] calldata minIssueRatios,
        bool enable
    ) external auth {
        for (uint256 i = 0; i < minIssueRatios.length; ++i) {
            minIssueRatioCandidates[minIssueRatios[i]] = enable;
        }
    }

    function setRatingCandidates(address[] calldata proposals, bool enable)
        external
        auth
    {
        for (uint256 i = 0; i < proposals.length; ++i) {
            ratingCandidates[proposals[i]] = enable;
        }
    }

    address public gov;

    function setGov(address _gov) external auth {
        gov = _gov;
    }

    uint256 public communityRatingLine;

    function setCommunityRatingLine(uint256 _communityRatingLine)
        external
        auth
    {
        communityRatingLine = _communityRatingLine;
    }
}
