/*
 * Copyright (c) The Force Protocol Development Team
*/
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;


import "./IRouter.sol";
import "./BondData.sol";

/**
 * @title ERC20 interface
 * @dev see https://eips.ethereum.org/EIPS/eip-20
 */
interface IERC20Detailed {
    function symbol() external view returns (string memory);
}

interface INameGen {
    function gen(string calldata symbol, uint id) external view returns (string memory);
}

interface IVerify {
    function verify(address[2] calldata, uint256[8] calldata) external view returns (bool);
}

contract BondFactory {
    using SafeERC20 for IERC20;

    address public router;
    address public verify;
    address public vote;
    address public core;
    address public nameGen;
    address public ACL;

    constructor(
        address _ACL,
        address _router,
        address _verify,
        address _vote,
        address _core,
	    address _nameGen
    ) public {
        ACL = _ACL;
        router = _router;
        verify = _verify;
        vote = _vote;
        core = _core;
        nameGen = _nameGen;
    }

    function setACL(address _ACL) external {
        require(msg.sender == ACL, "require ACL");
        ACL = _ACL;
    }

    //提交发债信息，new BondData
    //tokens[0]: _collateralToken
    //tokens[1]: _crowdToken
    //info[0]: _totalBondIssuance
    //info[1]: _couponRate, //一期的利率
    //info[2]: _maturity, //秒数
    //info[3]: _issueFee
    //info[4]: _minIssueRatio
    //info[5]: _financePurposeHash,//融资用途hash
    //info[6]: _paymentSourceHash,//还款来源hash
    //info[7]: _issueTimestamp,//发债时间
    //_redeemPutback[0]: _supportRedeem,
    //_redeemPutback[1]: _supportPutback
    function issue(
        address[2] calldata tokens,
        uint256 _minCollateralAmount,
        uint256[8] calldata info,
        bool[2] calldata _redeemPutback
    ) external returns (uint256) {
        require(IVerify(verify).verify(tokens, info), "verify error");

        uint256 nr = IRouter(router).bondNr();
        string memory bondName = INameGen(nameGen).gen(IERC20Detailed(tokens[0]).symbol(), nr);
        BondData b = new BondData(
            ACL,
            nr,
            bondName,
            msg.sender,
            tokens[0],
            tokens[1],
            info,
            _redeemPutback
        );
        IRouter(router).setDefaultContract(nr, address(b));
        IRouter(router).setBondNr(nr + 1);

        IACL(ACL).enableany(address(this), address(b));
        IACL(ACL).enableboth(core, address(b));
        IACL(ACL).enableboth(vote, address(b));

        b.setLogics(core, vote);
        
        //合约划转用户的币到用户的bondData合约中
        IERC20(tokens[0]).safeTransferFrom(msg.sender, address(this), _minCollateralAmount);
        IERC20(tokens[0]).safeApprove(address(b), _minCollateralAmount);
        b.initialDeposit(msg.sender, _minCollateralAmount);

        return nr;
    }
}
