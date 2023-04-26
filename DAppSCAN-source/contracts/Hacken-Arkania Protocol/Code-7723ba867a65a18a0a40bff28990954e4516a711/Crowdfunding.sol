// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./TokenStaking.sol";

contract Crowdfunding {

    TokenStaking public tokenStaking;

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

    constructor(TokenStaking _tokenStaking) {
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

    mapping(uint => Whitelist[]) projectsWhitelist;
    mapping(uint => LotteryWinner[]) lotteryWinners;
    mapping (address => bool) admins;

    // ADMIN
    function setAdmin(address _admin, bool isAdmin) public onlyOwner {
        admins[_admin] = isAdmin;
    }

    function removeAdmin(address adminAddress) public onlyAdmin {
        _removeAdminFromAdmins(adminAddress);
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
                emit eventAddUserToWhitelist(projectId, users[i], block.timestamp);
            }
        }
    }

    // Bulk removal of users from the whitelist
    function removeUsersFromWhitelist(uint projectId, address[] calldata users) external onlyAdmin {
        for (uint u; u < users.length; u++) {
            for(uint i; i < projectsWhitelist[projectId].length; i++){
                if (keccak256(abi.encodePacked(projectsWhitelist[projectId][i].userAddress)) == keccak256(abi.encodePacked(users[u]))) {
                    _removeUserFromProject(projectId, i);
                }
            }
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
        uint256 currentStakeCap = 0;
        for(uint256 i; i < projectsWhitelist[projectId].length; i++){
            address userAddress = projectsWhitelist[projectId][i].userAddress;
            currentStakeCap += getUserTicketValue(userAddress);
        }
        return currentStakeCap;
    }

    function getProjectRaisedAmount(uint projectId) public view returns(uint256) {
        uint256 currentRaisedAmount = 0;
        for(uint256 i; i < lotteryWinners[projectId].length; i++){
            if (lotteryWinners[projectId][i].claimed) {
                currentRaisedAmount += lotteryWinners[projectId][i].reward;
            }
        }
        return currentRaisedAmount;
    }

    function lotteryDraw(uint projectId, address[] calldata users) external onlyAdmin {
        require(_checkProjectExistById(projectId), "Project with this ID does not exist.");
        require(!_checkOpenProject(projectId), "Project is open and should be closed.");
        // We will check if the lottery is open
        require(!projects[projectId].draw, "The lottery has been already drawn.");

        uint256 currentStakeCap = getProjectStakeCap(projectId);
        uint cap = projects[projectId].raiseGoal;

        require(cap <= currentStakeCap, "Project cap still not reached.");

        for (uint i; i < users.length; i++) {
            address user = users[i];
            if(_checkUserExistInProject(projectId, user) && !_checkUserisProjectWinner(projectId, user)){
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

    function getProjectUsers(uint projectId) external view returns (Whitelist[] memory) {
        Whitelist[] memory whitelist = new Whitelist[](projectsWhitelist[projectId].length);
        for (uint i = 0; i < projectsWhitelist[projectId].length; i++) {
            Whitelist storage user = projectsWhitelist[projectId][i];
            whitelist[i] = user;
        }
        return whitelist;
    }

    function getUserCount(uint projectId) external view returns (uint) {
        return projectsWhitelist[projectId].length;
    }

    function getLotteryWinners(uint projectId) external view returns (LotteryWinner[] memory) {
        LotteryWinner[] memory winners = new LotteryWinner[](lotteryWinners[projectId].length);
        for (uint i = 0; i < lotteryWinners[projectId].length; i++) {
            LotteryWinner storage user = lotteryWinners[projectId][i];
            winners[i] = user;
        }
        return winners;
    }

    function getLotteryWinner(uint projectId, address userAddress) public view returns (LotteryWinner memory) {
        LotteryWinner[] memory winners = lotteryWinners[projectId];
        LotteryWinner memory winner = LotteryWinner({
            projectId: projectId,
            userAddress: userAddress,
            reward: 0,
            claimed: true
        });
        for (uint i; i < winners.length; i++) {
            if(winners[i].userAddress == userAddress) {
                winner = winners[i];
                break;
            }
        }
        return winner;
    }

    function setLotteryWinnerClaimedStatus(uint projectId, address userAddress) internal {
        LotteryWinner[] memory winners = lotteryWinners[projectId];
        for (uint i; i < winners.length; i++) {
            if(winners[i].userAddress == userAddress) {
                lotteryWinners[projectId][i].claimed = true;
                break;
            }
        }
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
        emit eventAddUserToWhitelist(projectId, msg.sender, block.timestamp);
    }

    function logoutFromWhitelist(uint projectId) external {
        for(uint i; i < projectsWhitelist[projectId].length; i++){
            if (keccak256(abi.encodePacked(projectsWhitelist[projectId][i].userAddress)) == keccak256(abi.encodePacked(msg.sender))) {
                _removeUserFromProject(projectId, i);
            }
        }
    }

    // We will check if the whitelisting is open
    function isProjectOpen(uint projectId) external view returns (bool){
        return _checkOpenProject(projectId);
    }

    // We will check if the user exists in the list
    function isUserInWhitelist(uint projectId) external view returns (bool) {
        return _checkUserExistInProject(projectId, msg.sender);
    }

    function checkBuy(uint projectId, uint256 tokenToBuy) public view returns (bool) {
        // The project id is required
        require(projectId > 0, "ProjectId must be selected");
        require(_checkProjectExistById(projectId), "Project with this ID does not exist.");

        // Project info
        address contractAddress = projects[projectId].contractAddress;
        uint firstPayoutInPercent = projects[projectId].firstPayoutInPercent;

        // We will check how many tokens there are in the contract account
        uint256 availableTokens = anyoneTokenBalance(contractAddress, address(this));
        require(availableTokens > 0, "Insufficient tokens in contract");

        // We'll check to see if there are enough tokens to pay out in contract account
        uint tokensForTransfer = tokenToBuy * firstPayoutInPercent / 100;
        require(tokensForTransfer > 0, "Insufficient tokens to send");
        require(tokensForTransfer < availableTokens, "Insufficient tokens in contract to send");

        // We will get the winner and check if there is still reward available
        LotteryWinner memory winner = getLotteryWinner(projectId, msg.sender);
        require(!winner.claimed, "User already claimed the reward");

        return true;
    }

    function buy(uint projectId, uint256 tokenToBuy) payable public {
        // Payment must be greater than 0
        require(msg.value > 0, "You need to send some ether");

        // Check requirements before any transactions
        checkBuy(projectId, tokenToBuy);

        address billingAddress = projects[projectId].billingAddress;
        address contractAddress = projects[projectId].contractAddress;
        uint firstPayoutInPercent = projects[projectId].firstPayoutInPercent;
        uint tokensForTransfer = tokenToBuy * firstPayoutInPercent / 100;

        // Set the claimed attribute to true to avoid repeatedly withdrawn
        setLotteryWinnerClaimedStatus(projectId, msg.sender);

        // Create a token from a given contract address
        IERC20 token = IERC20(contractAddress);
        // I will transfer a certain number of tokens to the payer. Not all
        token.transfer(msg.sender, tokensForTransfer);

        // Transfer fee to Token owner
        payable(billingAddress).transfer(msg.value);
    }

    function claim(uint projectId, uint256 tokenToBuy) public {
        // Check requirements before any transactions
        checkBuy(projectId, tokenToBuy);

        address contractAddress = projects[projectId].contractAddress;
        uint firstPayoutInPercent = projects[projectId].firstPayoutInPercent;
        uint tokensForTransfer = tokenToBuy * firstPayoutInPercent / 100;

        // Set the claimed attribute to true to avoid repeatedly withdrawn
        setLotteryWinnerClaimedStatus(projectId, msg.sender);

        // Create a token from a given contract address
        IERC20 token = IERC20(contractAddress);
        // I will transfer a certain number of tokens to the payer. Not all
        token.transfer(msg.sender, tokensForTransfer);
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
        for(uint i; i < projectsWhitelist[projectId].length; i++){
            if (keccak256(abi.encodePacked(projectsWhitelist[projectId][i].userAddress)) == keccak256(abi.encodePacked(userAddress))) {
                return true;
            }
        }
        return false;
    }

    function _checkUserisProjectWinner(uint projectId, address userAddress) internal view returns (bool) {
        for(uint i; i < lotteryWinners[projectId].length; i++){
            if (keccak256(abi.encodePacked(lotteryWinners[projectId][i].userAddress)) == keccak256(abi.encodePacked(userAddress))) {
                return true;
            }
        }
        return false;
    }

    function _checkOpenProject(uint projectId) internal view returns (bool) {
        return projects[projectId].id > 0 && projects[projectId].endDate > block.timestamp;
    }

    function _removeUserFromProject(uint projectId, uint i) internal {
        projectsWhitelist[projectId][i] = projectsWhitelist[projectId][projectsWhitelist[projectId].length - 1];
        projectsWhitelist[projectId].pop();
    }

    function _removeAdminFromAdmins(address adminAddress) internal {
        delete admins[adminAddress];
    }

    function _removeWhitelist(uint projectId) internal {
        delete projectsWhitelist[projectId];
    }

    function _removeProject(uint projectId) internal {
        delete projects[projectId];
    }

}
