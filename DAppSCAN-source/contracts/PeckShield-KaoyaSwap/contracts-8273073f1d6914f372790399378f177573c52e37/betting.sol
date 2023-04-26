pragma solidity 0.8.7;

interface IPriceOracle{
    function latestAnswer() external view returns (int256);
}

struct MatchInfo {
    uint256 startTime;
    uint256 endTime;
    uint256 startPrice;
    uint256 endPrice;
    uint256 betEndTime;
    uint256 upBalance;
    uint256 downBalance;
}
struct UserInfo{
    uint256 matchId;
    bool upDown;
    uint256 balance;
    bool done;
}

contract betting{
    address public owner;
    address public oracle;
    MatchInfo[] public matchInfo;
    
    mapping (address => UserInfo) userInfo;
    constructor() public {
      owner = msg.sender;
    }
    modifier onlyOwner() {
        require(owner==msg.sender, 'UniswapV2Router: EXPIRED');
        _;
    }
    function setOracle(address _oracle) public onlyOwner{
        oracle = _oracle;
    }
    function startMatch() public onlyOwner{
        uint256 currentPrice = uint(IPriceOracle(oracle).latestAnswer());
        matchInfo.push(MatchInfo({
            startTime:block.timestamp,
            endTime: block.timestamp + 86400,
            startPrice : currentPrice,
            endPrice : 0,
            betEndTime : block.timestamp + 3600,
            upBalance:0,
            downBalance:0
        }));
    }
    function setEndPrice() public onlyOwner{
        uint matchLength = matchInfo.length;
        require(matchInfo[matchLength-1].endTime>block.timestamp-1 && matchInfo[matchLength-1].endTime<block.timestamp+1, "error");
        
        uint256 currentPrice = uint(IPriceOracle(oracle).latestAnswer());
        matchInfo[matchLength-1].endPrice = currentPrice;
    }
    function doBetting(bool _upDown) external payable{
        
        uint matchLength = matchInfo.length;
        require(matchInfo[matchLength-1].betEndTime>block.timestamp-1, "error");
        
        UserInfo storage user = userInfo[msg.sender];
        if(user.matchId<matchInfo.length-1&&user.done==false&&user.balance>0){
            claim(user.matchId);
        }
        if(user.matchId!=matchInfo.length-1){
            if(_upDown) {
                matchInfo[matchLength-1].upBalance +=msg.value;
            }
            else{
                matchInfo[matchLength-1].downBalance +=msg.value;
            }
        }
        user.balance +=msg.value;
        user.matchId = matchInfo.length-1;
        user.upDown = _upDown;
        user.done = false;
    }
    function claim(uint256 matchId) public{
        require(matchInfo[matchId].endTime<block.timestamp-1, "error");
        UserInfo storage user = userInfo[msg.sender];
        require(user.done==false,"error");
        MatchInfo storage _match = matchInfo[matchId];

        uint256 userBalance;
        if(_match.startPrice<=_match.endPrice)
            userBalance = user.balance*975*(_match.upBalance + _match.downBalance)/(_match.upBalance*1000);
        else
            userBalance = user.balance*975*(_match.upBalance + _match.downBalance)/(_match.downBalance*1000);
        user.done = true;
        payable(msg.sender).transfer(userBalance);
    }
}
