pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "./SafeERC20.sol";
import "./IRouter.sol";
import "./StageDefine.sol";
import "./IBondData.sol";


interface IPRA {
    function raters(address who) external view returns (bool);
}


interface IConfig {
    function ratingCandidates(address proposal) external view returns (bool);

    function depositDuration() external view returns (uint256);

    function professionalRatingWeightRatio() external view returns (uint256);

    function communityRatingWeightRatio() external view returns (uint256);

    function investDuration() external view returns (uint256);

    function communityRatingLine() external view returns (uint256);
}


interface IACL {
    function accessible(address sender, address to, bytes4 sig)
        external
        view
        returns (bool);
}


interface IRating {
    function risk() external view returns (uint256);
    function fine() external view returns (bool);
}


contract Vote {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    event MonitorEvent(
        address indexed who,
        address indexed bond,
        bytes32 indexed funcName,
        bytes
    );

    function MonitorEventCallback(address who, address bond, bytes32 funcName, bytes calldata payload) external {
        emit MonitorEvent(who, bond, funcName, payload);
    }

    address public router;
    address public config;
    address public ACL;
    address public PRA;

    modifier auth {
        require(
            IACL(ACL).accessible(msg.sender, address(this), msg.sig),
            "Vote: access unauthorized"
        );
        _;
    }

    constructor(address _ACL, address _router, address _config, address _PRA)
        public
    {
        router = _router;
        config = _config;
        ACL = _ACL;
        PRA = _PRA;
    }

    function setACL(
        address _ACL) external {
        require(msg.sender == ACL, "require ACL");
        ACL = _ACL;
    }

    //专业评级时调用
    function prcast(uint256 id, address proposal, uint256 reason) external {
        IBondData data = IBondData(IRouter(router).defaultDataContract(id));
        require(data.voteExpired() > now, "vote is expired");
        require(
            IPRA(PRA).raters(msg.sender),
            "sender is not a professional rater"
        );
        IBondData.prwhat memory pr = data.pr();
        require(pr.proposal == address(0), "already professional rating");
        IBondData.what memory _what = data.votes(msg.sender);
        require(_what.proposal == address(0), "already community rating");
        require(data.issuer() != msg.sender, "issuer can't vote for self bond");
        require(
            IConfig(config).ratingCandidates(proposal),
            "proposal is not permissive"
        );
        data.setPr(msg.sender, proposal, reason);
        emit MonitorEvent(
            msg.sender,
            address(data),
            "prcast",
            abi.encodePacked(proposal)
        );
    }

    //仅能被 data.vote 回调, 社区投票时调用
    function cast(uint256 id, address who, address proposal, uint256 amount)
        external
        auth
    {
        IBondData data = IBondData(IRouter(router).defaultDataContract(id));
        require(data.voteExpired() > now, "vote is expired");
        require(!IPRA(PRA).raters(who), "sender is a professional rater");
        require(data.issuer() != who, "issuer can't vote for self bond");
        require(
            IConfig(config).ratingCandidates(proposal),
            "proposal is not permissive"
        );

        IBondData.what memory what = data.votes(who);

        address p = what.proposal;
        uint256 w = what.weight;

        //多次投票但是本次投票的提案与前次投票的提案不同
        if (p != address(0) && p != proposal) {

            data.setBondParamMapping("weights", p, data.weights(p).sub(w));
            data.setBondParamMapping("weights", proposal, data.weights(proposal).add(w));
        }

        data.setVotes(who, proposal, w.add(amount));

        data.setBondParamMapping("weights", proposal, data.weights(proposal).add(amount));
        data.setBondParam("totalWeights", data.totalWeights().add(amount));

        //同票数情况下后投出来的为胜
        if (data.weights(proposal) >= data.weights(data.top())) {
            // data.setTop(proposal);
            data.setBondParamAddress("top", proposal);
        }
    }

    //仅能被 data.take 回调
    function take(uint256 id, address who) external auth returns (uint256) {
        IBondData data = IBondData(IRouter(router).defaultDataContract(id));
        require(now > data.voteExpired(), "vote is expired");
        require(data.top() != address(0), "vote is not winner");
        uint256 amount = data.voteLedger(who);

        return amount;
    }

    function rating(uint256 id) external {
        IBondData data = IBondData(IRouter(router).defaultDataContract(id));
        require(now > data.voteExpired(), "vote unexpired");

        uint256 _bondStage = data.bondStage();
        require(
            _bondStage == uint256(BondStage.RiskRating),
            "already rating finished"
        );

        uint256 totalWeights = data.totalWeights();
        IBondData.prwhat memory pr = data.pr();

        if (
            totalWeights >= IConfig(config).communityRatingLine() &&
            pr.proposal != address(0)
        ) {
            address top = data.top();
            uint256 p = IConfig(config).professionalRatingWeightRatio(); //40%
            uint256 c = IConfig(config).communityRatingWeightRatio(); //60%
            uint256 pr_weights = totalWeights.mul(p).div(c);

            if (top != pr.proposal) {
                uint256 pr_proposal_weights = data.weights(pr.proposal).add(
                    pr_weights
                );

                if (data.weights(top) < pr_proposal_weights) {
                    //data.setTop(pr.proposal);
                    data.setBondParamAddress("top", pr.proposal);
                }

                //社区评级结果与专业评级的投票选项不同但权重相等时, 以风险低的为准
                if (data.weights(top) == pr_proposal_weights) {
                    data.setBondParamAddress("top", 
                        IRating(top).risk() < IRating(pr.proposal).risk()
                            ? top
                            : pr.proposal
                    );
                }
            }
            if(IRating(data.top()).fine()) {
                data.setBondParam("bondStage", uint256(BondStage.CrowdFunding));
                data.setBondParam("investExpired", now + IConfig(config).investDuration());
                data.setBondParam("bondExpired", now + IConfig(config).investDuration() + data.maturity());
            } else {
                data.setBondParam("bondStage", uint256(BondStage.RiskRatingFail));
                data.setBondParam("issuerStage", uint256(IssuerStage.UnWithdrawPawn));
            }
        } else {
            data.setBondParam("bondStage", uint256(BondStage.RiskRatingFail));
            data.setBondParam("issuerStage", uint256(IssuerStage.UnWithdrawPawn));
        }

        emit MonitorEvent(
            msg.sender,
            address(data),
            "rating",
            abi.encodePacked(data.top(), data.weights(data.top()))
        );
    }

    //取回后页面获得手续费保留原值不变
    function profitOf(uint256 id, address who) public view returns (uint256) {
        IBondData data = IBondData(IRouter(router).defaultDataContract(id));
        uint256 _bondStage = data.bondStage();
        if (
            _bondStage == uint256(BondStage.RepaySuccess) ||
            _bondStage == uint256(BondStage.DebtClosed)
        ) {
            IBondData.what memory what = data.votes(who);
            IBondData.prwhat memory pr = data.pr();

            uint256 p = IConfig(config).professionalRatingWeightRatio();
            uint256 c = IConfig(config).communityRatingWeightRatio();

            uint256 _fee = data.fee();
            uint256 _profit = 0;

            if (pr.who != who) {
                if(what.proposal == address(0)) {
                    return 0;
                }
                //以社区评级人身份投过票
                //fee * c (0.6 * 1e18) * weights/totalweights;
                _profit = _fee.mul(c).mul(what.weight).div(
                    data.totalWeights()
                );
            } else {
                //who对本债券以专业评级人投过票
                //fee * p (0.4 * 1e18);
                _profit = _fee.mul(p);
            }

            uint256 liability = data.liability();
            //profit = profit * (1 - liability/originLiability);
            uint256 originLiability = data.originLiability();
            _profit = _profit
                .mul(originLiability.sub(liability))
                .div(originLiability)
                .div(1e18);

            return _profit;
        }

        return 0;
    }

    //取回评级收益,被bondData调用
    function profit(uint256 id, address who) external auth returns (uint256) {
        IBondData data = IBondData(IRouter(router).defaultDataContract(id));
        uint256 _bondStage = data.bondStage();
        require(
            _bondStage == uint256(BondStage.RepaySuccess) ||
                _bondStage == uint256(BondStage.DebtClosed),
            "bond is unrepay or unliquidate"
        );
        require(data.profits(who) == 0, "voting profit withdrawed");
        IBondData.prwhat memory pr = data.pr();
        IBondData.what memory what = data.votes(who);
        require(what.proposal != address(0) || pr.who == who, "user is not rating vote");
        uint256 _profit = profitOf(id, who);
        data.setBondParamMapping("profits", who, _profit);
        data.setBondParam("totalProfits", data.totalProfits().add(_profit));

        return _profit;
    }
}
