// SPDX-License-Identifier: MIT
// SWC-102-Outdated Compiler Version: L3
// SWC-103-Floating Pragma: L8
pragma solidity ^0.8.2;

import "./AniaStake.sol";

contract AniaLottery {

    AniaStake public tokenStaking;

    address public owner;
    uint public tierOne = 50000;
    uint public tierOneTicketValue = 1000;
    uint public tierTwo = 20000;
    uint public tierTwoTicketValue = 500;
    uint public tierThree = 10000;
    uint public tierThreeTicketValue = 250;
    uint internal decimals = 1000000000000000000;

    event eventAddUserToWhitelist(uint indexed id, address user, uint signupDate);
    event eventAddUserToLotteryWinners(uint indexed id, address user, uint reward, uint claimed);

    struct Project {
        uint id;
        string name;
        uint raiseGoal;
        uint endDate;
        address contractAddress;
        address billingAddress;
        uint firstPayoutInPercent;
        uint256 tokenPrice;
        bool draw;
    }
    mapping (uint => Project) projects;

    struct Whitelist {
        uint projectId;
        uint signupDate;
        address userAddress;
    }

    struct LotteryWinner {
        uint projectId;
        address userAddress;
        uint reward;
        bool claimed;
    }

    constructor(AniaStake _tokenStaking) {
        tokenStaking = _tokenStaking;
        owner = msg.sender;
    }

    modifier onlyAdmin {
        require(msg.sender == owner || admins[msg.sender]);
        _;
    }

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    mapping(uint => uint) projectUserCount;
    mapping(uint => Whitelist[]) projectsWhitelist;
    mapping(uint => mapping(address => uint256)) projectUserIndex;
    mapping(uint => uint) projectStakeCap;
    mapping(uint => uint) lotteryWinnerCount;
    mapping(uint => LotteryWinner[]) lotteryWinners;
    mapping(uint => mapping(address => uint256)) projectWinnerIndex;
    mapping(uint => uint) projectRaisedAmount;
    mapping (address => bool) admins;

    mapping (address => bool) stableCoins;

    // ADMIN
    function setAdmin(address _admin, bool isAdmin) public onlyOwner {
        admins[_admin] = isAdmin;
    }

    function removeAdmin(address adminAddress) public onlyAdmin {
        _removeAdminFromAdmins(adminAddress);
    }

    function setStableCoin(address _address, bool isActive) public onlyOwner {
        stableCoins[_address] = isActive;
    }

    function createProject(uint projectId, string calldata projectName, uint raiseGoal, uint endDate, address contractAddress, address billingAddress, uint firstPayoutInPercent, uint256 tokenPrice) external onlyAdmin {
        require(!_checkProjectExistById(projectId), "Project with this ID exist.");

        Project memory newProject = Project(projectId, projectName, raiseGoal, endDate, contractAddress, billingAddress, firstPayoutInPercent, tokenPrice, false);

        projects[projectId] = newProject;
    }

    function updateProject(uint projectId, string calldata projectName, uint raiseGoal, uint endDate, address contractAddress, address billingAddress, uint firstPayoutInPercent, uint256 tokenPrice) external onlyAdmin {

        // Each non-existent record returns 0
        require(projects[projectId].id == projectId, "Project with this ID not exist.");

        projects[projectId].name = projectName;
        projects[projectId].raiseGoal = raiseGoal;
        projects[projectId].endDate = endDate;
        projects[projectId].contractAddress = contractAddress;
        projects[projectId].billingAddress = billingAddress;
        projects[projectId].firstPayoutInPercent= firstPayoutInPercent;
        projects[projectId].tokenPrice = tokenPrice;
    }

    function removeProject(uint projectId) external onlyAdmin {
        _removeWhitelist(projectId);
        _removeProject(projectId);
    }

    // If there are any resources, the owner can withdraw them
    // SWC-105-Unprotected Ether Withdrawal: L117 - L119
    function withdraw() public payable onlyOwner {
        payable (msg.sender).transfer(address(this).balance);
    }

    function withdrawTokens(uint projectId, address recipient) public onlyAdmin {
        address contractAddress = projects[projectId].contractAddress;
        // Create a token from a given contract address
        IERC20 token = IERC20(contractAddress);
        token.transfer(recipient, token.balanceOf(address(this)));
    }

    // Add users to the whitelist in bulk
    function addUsersToWhitelist(uint projectId, address[] calldata users, bool checkEndDate) external onlyAdmin {

        if(checkEndDate){
            require(_checkOpenProject(projectId), "Project is close.");
        }
        // We will check if the whitelisting is open
        require(!projects[projectId].draw, "The lottery has been launched and project is completed close.");
        for (uint i; i < users.length; i++) {
            if(!_checkUserExistInProject(projectId, users[i])){
                projectsWhitelist[projectId].push(
                    Whitelist({
                        projectId: projectId,
                        userAddress: users[i],
                        signupDate: block.timestamp
                    })
                );
                projectStakeCap[projectId] += getUserTicketValue(users[i]);
                uint256 index = projectsWhitelist[projectId].length - 1;
                projectUserIndex[projectId][users[i]] = index;
                projectUserCount[projectId]++;
                emit eventAddUserToWhitelist(projectId, users[i], block.timestamp);
            }
        }
    }

    // Bulk removal of users from the whitelist
    function removeUsersFromWhitelist(uint projectId, address[] calldata users) external onlyAdmin {
        for (uint i; i < users.length; i++) {
            _removeUserFromProject(projectId, users[i]);
        }
    }

    function getUserTicketValue(address _address) public view returns (uint256) {
        uint256 userStake = tokenStaking.hasStakeWithRewards(_address);
        if(userStake >= tierOne * decimals){
            return tierOneTicketValue;
        } else if (userStake >= tierTwo * decimals){
            return tierTwoTicketValue;
        } else if (userStake >= tierThree * decimals){
            return tierThreeTicketValue;
        }
        return 0;
    }

    function getProjectStakeCap(uint projectId) public view returns(uint256) {
        return projectStakeCap[projectId];
    }

    function getProjectRaisedAmount(uint projectId) public view returns(uint256) {
        return projectRaisedAmount[projectId];
    }

    function lotteryDraw(uint projectId, address[] calldata users) external onlyAdmin {
        require(_checkProjectExistById(projectId), "Project with this ID does not exist.");
        require(!_checkOpenProject(projectId), "Project is open and should be closed.");
        // We will check if the lottery is open
        require(!projects[projectId].draw, "The lottery has been already drawn.");

        for (uint i; i < users.length; i++) {
            address user = users[i];
            if(_checkUserExistInProject(projectId, user) && !_checkUserIsProjectWinner(projectId, user)){
                uint reward = getUserTicketValue(user);
                if (reward > 0) {
                    lotteryWinners[projectId].push(
                        LotteryWinner({
                            projectId: projectId,
                            userAddress: user,
                            reward: reward,
                            claimed: false
                        })
                    );
                    uint256 index = lotteryWinners[projectId].length - 1;
                    projectWinnerIndex[projectId][user] = index;
                    lotteryWinnerCount[projectId]++;
                    emit eventAddUserToLotteryWinners(projectId, user, reward, 0);
                }
            }
        }

        // Set the project lottery draw status to true to avoid multiple lottery rounds
        projects[projectId].draw = true;
    }

    function getProject(uint projectId) external view returns (Project memory) {
        return projects[projectId];
    }

    function getUserCount(uint projectId) external view returns (uint) {
        return projectUserCount[projectId];
    }

    function getProjectUser(uint projectId, address userAddress) public view returns (Whitelist memory) {
        uint256 index = projectUserIndex[projectId][userAddress];
        require(projectsWhitelist[projectId][index].userAddress == userAddress, "User not found");
        return projectsWhitelist[projectId][index];
    }

    function getLotteryWinner(uint projectId, address userAddress) public view returns (LotteryWinner memory) {
        uint256 index = projectWinnerIndex[projectId][userAddress];
        require(lotteryWinners[projectId][index].userAddress == userAddress, "Winner not found");
        return lotteryWinners[projectId][index];
    }

    function getLotteryWinnerCount(uint projectId) external view returns (uint) {
        return lotteryWinnerCount[projectId];
    }

    function setLotteryWinnerClaimedStatus(uint projectId, address userAddress) internal {
        uint256 index = projectWinnerIndex[projectId][userAddress];
        require(lotteryWinners[projectId][index].userAddress == userAddress, "User not found");
        lotteryWinners[projectId][index].claimed = true;
    }

    // Helper functions
    function changeTierOne(uint _value) external onlyAdmin {
        require(_value > 0, "Tier value has to be more than 0");
        require(_value > tierTwo, "Tier value has to be more than Tier Two");
        require(_value > tierThree, "Tier value has to be more than Tier Three");
        tierOne = _value;
    }
    function changeTierTwo(uint _value) external onlyAdmin {
        require(_value > 0, "Tier value has to be more than 0");
        require(_value < tierOne, "Tier value has to be less than Tier One");
        require(_value > tierThree, "Tier value has to be more than Tier Three");
        tierTwo = _value;
    }
    function changeTierThree(uint _value) external onlyAdmin {
        require(_value > 0, "Tier value has to be more than 0");
        require(_value < tierOne, "Tier value has to be less than Tier One");
        require(_value < tierTwo, "Tier value has to be less than Tier Two");
        tierThree = _value;
    }
    function changeTierOneTicketValue(uint _value) external onlyAdmin {
        require(_value > 0, "Tier Ticket value has to be more than 0");
        require(_value > tierTwoTicketValue, "Tier Ticket value has to be more than Tier Two");
        require(_value > tierThreeTicketValue, "Tier Ticket value has to be more than Tier Three");
        tierOneTicketValue = _value;
    }
    function changeTierTwoTicketValue(uint _value) external onlyAdmin {
        require(_value > 0, "Tier Ticket value has to be more than 0");
        require(_value < tierOneTicketValue, "Tier Ticket value has to be less than Tier One");
        require(_value > tierThreeTicketValue, "Tier Ticket value has to be more than Tier Three");
        tierTwoTicketValue = _value;
    }
    function changeTierThreeTicketValue(uint _value) external onlyAdmin {
        require(_value > 0, "Tier Ticket value has to be more than 0");
        require(_value < tierOneTicketValue, "Tier Ticket value has to be less than Tier One");
        require(_value < tierTwoTicketValue, "Tier Ticket value has to be less than Tier Two");
        tierThreeTicketValue = _value;
    }

    // USER
    function signUpToWhitelist(uint projectId) external {
        // We will check if the whitelisting is open
        require(_checkOpenProject(projectId), "Project is close.");
        // We will check if the user exists in the list
        require(!_checkUserExistInProject(projectId, msg.sender), "User is already in whitelist.");
        projectsWhitelist[projectId].push(
            Whitelist({
                projectId: projectId,
                userAddress: msg.sender,
                signupDate: block.timestamp
            })
        );
        projectStakeCap[projectId] += getUserTicketValue(msg.sender);
        uint256 index = projectsWhitelist[projectId].length - 1;
        projectUserIndex[projectId][msg.sender] = index;
        projectUserCount[projectId]++;
        emit eventAddUserToWhitelist(projectId, msg.sender, block.timestamp);
    }

    function logoutFromWhitelist(uint projectId) external {
        _removeUserFromProject(projectId, msg.sender);
    }

    // We will check if the whitelisting is open
    function isProjectOpen(uint projectId) external view returns (bool){
        return _checkOpenProject(projectId);
    }

    // We will check if the user exists in the list
    function isUserInWhitelist(uint projectId) external view returns (bool) {
        return _checkUserExistInProject(projectId, msg.sender);
    }

    function checkBuy(uint projectId, uint256 tokensToBuy) public view returns (bool) {
        // The project id is required
        require(projectId > 0, "ProjectId must be selected");
        require(_checkProjectExistById(projectId), "Project with this ID does not exist.");

        // Project info
        address contractAddress = projects[projectId].contractAddress;

        // We will check how many tokens there are in the contract account
        uint256 availableTokens = anyoneTokenBalance(contractAddress, address(this));
        require(availableTokens > 0, "Insufficient tokens in contract");

        // We'll check to see if there are enough tokens to pay out in contract account
        require(tokensToBuy > 0, "Insufficient tokens to send");
        require(tokensToBuy < availableTokens, "Insufficient tokens in contract to send");

        // We will get the winner and check if there is still reward available
        LotteryWinner memory winner = getLotteryWinner(projectId, msg.sender);
        require(!winner.claimed, "User already claimed the reward");

        return true;
    }

    function buy(uint projectId, uint pay, address tokenForPayContractAddress) external {

        require(stableCoins[tokenForPayContractAddress], "This Token is not available for payment");

        // Payment must be greater than 0
        require(pay > 0, "You need to send some ether");
        require(getUserTicketValue(msg.sender) == pay, "You need to pay the exact tier value before claiming the reward");

        uint256 tokensToBuy = decimals * (pay * decimals) / projects[projectId].tokenPrice * projects[projectId].firstPayoutInPercent / 100;

        // Check requirements before any transactions
        checkBuy(projectId, tokensToBuy);

        address billingAddress = projects[projectId].billingAddress;
        address contractAddress = projects[projectId].contractAddress;
        require(billingAddress != contractAddress, "Billing Address must be different as Contract Address");

        // Create a token from a given contract address
        IERC20 token = IERC20(contractAddress);
        // I will transfer a certain number of tokens to the payer. Not all
        token.transfer(msg.sender, tokensToBuy);

        // Transfer stable Coin to Token owner
        IERC20 stableCoin = IERC20(tokenForPayContractAddress);
        stableCoin.transferFrom(msg.sender, billingAddress, pay * decimals);

        // Set the claimed attribute to true to avoid repeatedly withdrawn
        setLotteryWinnerClaimedStatus(projectId, msg.sender);
        projectRaisedAmount[projectId] += pay;
    }

    // Check the balance for a specific token for a specific address
    function anyoneTokenBalance(address tokenContractAddress, address userAddress) public view returns(uint) {
        IERC20 token = IERC20(tokenContractAddress);
        return token.balanceOf(userAddress);
    }

    // Internal functions
    function _checkProjectExistById(uint projectId) internal view returns (bool) {
        if(projects[projectId].id > 0){
            return true;
        }
        return false;
    }

    function _checkUserExistInProject(uint projectId, address userAddress) internal view returns (bool) {
        if (projectsWhitelist[projectId].length == 0) {
            return false;
        }

        uint256 index = projectUserIndex[projectId][userAddress];
        if (projectsWhitelist[projectId][index].userAddress == userAddress) {
            return true;
        }
        return false;
    }

    function _checkUserIsProjectWinner(uint projectId, address userAddress) internal view returns (bool) {
        if (lotteryWinners[projectId].length == 0) {
            return false;
        }

        uint256 index = projectWinnerIndex[projectId][userAddress];
        if (lotteryWinners[projectId][index].userAddress == userAddress) {
            return true;
        }
        return false;
    }

    function _checkOpenProject(uint projectId) internal view returns (bool) {
        return projects[projectId].id > 0 && projects[projectId].endDate > block.timestamp;
    }

    function _removeUserFromProject(uint256 projectId, address userAddress) internal {
        uint256 index = projectUserIndex[projectId][userAddress];
        if (projectsWhitelist[projectId][index].userAddress == userAddress) {
            delete projectUserIndex[projectId][userAddress];
            projectStakeCap[projectId] -= getUserTicketValue(projectsWhitelist[projectId][index].userAddress);
            delete projectsWhitelist[projectId][index];
            projectUserCount[projectId]--;
        }
    }

    function _removeAdminFromAdmins(address adminAddress) internal {
        delete admins[adminAddress];
    }

    function _removeWhitelist(uint projectId) internal {
        projectStakeCap[projectId] = 0;
        projectRaisedAmount[projectId] = 0;
        delete projectsWhitelist[projectId];
    }

    function _removeProject(uint projectId) internal {
        projectUserCount[projectId] = 0;
        lotteryWinnerCount[projectId] = 0;
        delete projects[projectId];
    }

}
