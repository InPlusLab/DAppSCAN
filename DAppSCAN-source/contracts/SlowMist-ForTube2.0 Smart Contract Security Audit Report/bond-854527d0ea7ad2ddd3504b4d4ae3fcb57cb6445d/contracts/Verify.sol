pragma solidity ^0.6.0;


interface IConfig {
    function depositTokenCandidates(address token) external view returns (bool);

    function issueTokenCandidates(address token) external view returns (bool);

    function issueFeeCandidates(uint256 issueFee) external view returns (bool);

    function interestRateCandidates(uint256 interestRate)
        external
        view
        returns (bool);

    function maturityCandidates(uint256 maturity) external view returns (bool);

    function minIssueRatioCandidates(uint256 minIssueRatio)
        external
        view
        returns (bool);

    function maxIssueAmount(address depositToken, address issueToken) external view returns (uint256);
    function minIssueAmount(address depositToken, address issueToken) external view returns (uint256);
}

contract Verify {
    address public config;

    constructor(address _config) public {
        config = _config;
    }

    //tokens[0]: _collateralToken
    //tokens[1]: _crowdToken
    //arguments[0]: _totalBondIssuance
    //arguments[1]: _couponRate,  //一期的利率
    //arguments[2]: _maturity,    //秒数
    //arguments[3]: _issueFee     //
    //arguments[4]: _minIssueRatio
    //arguments[5]: _financePurposeHash,//融资用途hash
    //arguments[6]: _paymentSourceHash, //还款来源hash
    //arguments[7]: _issueTimestamp,    //发债时间

    function verify(address[2] calldata tokens, uint256[8] calldata arguments)
        external
        view
        returns (bool)
    {
        address depositToken = tokens[0];
        address issueToken = tokens[1];

        uint256 totalIssueAmount = arguments[0];
        uint256 interestRate = arguments[1];
        uint256 maturity = arguments[2];
        uint256 issueFee = arguments[3];
        uint256 minIssueRatio = arguments[4];

        IConfig _config = IConfig(config);

        return
            _config.depositTokenCandidates(depositToken) &&
            _config.issueTokenCandidates(issueToken) &&
            totalIssueAmount <= _config.maxIssueAmount(depositToken, issueToken) &&
            totalIssueAmount >= _config.minIssueAmount(depositToken, issueToken) &&
            _config.interestRateCandidates(interestRate) &&
            _config.maturityCandidates(maturity) &&
            _config.issueFeeCandidates(issueFee) &&
            _config.minIssueRatioCandidates(minIssueRatio);
    }
}
