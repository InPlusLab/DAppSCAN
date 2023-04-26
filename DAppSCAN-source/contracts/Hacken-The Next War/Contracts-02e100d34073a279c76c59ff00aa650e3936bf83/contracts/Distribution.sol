//SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Distribution is Ownable {

    IERC20 public tngToken;
    uint256 public constant DENOM = 100000; // For percentage precision upto 0.00x%

    // Token vesting 
    uint256[] public claimableTimestamp;
    mapping(uint256 => uint256) public claimablePercent;

    // Store the information of all users
    mapping(address => Account) public accounts;

    // For tracking
    uint256 public totalPendingVestingToken;    // Counter to track total required tokens
    uint256 public totalParticipants;           // Total presales participants

    event Register(address[] account, uint256[] tokenAllocation);
    event Deregister(address[] account);
    event Claim(address user, uint256 amount);
    event SetClaimable(uint256[] timestamp, uint256[] percent);

    struct Account {
        uint256 tokenAllocation;            // user's total token allocation 
        uint256 pendingTokenAllocation;     // user's pending token allocation
        uint256 claimIndex;                 // user's claimed at which index. 0 means never claim
        uint256 claimedTimestamp;           // user's last claimed timestamp. 0 means never claim
    }

	constructor(address _tngToken, uint256[] memory _claimableTimestamp, uint256[] memory _claimablePercent) {
        tngToken = IERC20(_tngToken);
        setClaimable(_claimableTimestamp, _claimablePercent);

        emit SetClaimable(_claimableTimestamp, _claimablePercent);
    }

    // Register token allocation info 
    // account : IDO address
    // tokenAllocation : IDO contribution amount in wei 
    function register(address[] memory account, uint256[] memory tokenAllocation) external onlyOwner {
        require(account.length > 0, "Account array input is empty");
        require(tokenAllocation.length > 0, "tokenAllocation array input is empty");
        require(tokenAllocation.length == account.length, "tokenAllocation length does not matched with account length");
        
        // Iterate through the inputs
        for(uint256 index = 0; index < account.length; index++) {
            // Save into account info
            Account storage userAccount = accounts[account[index]];

            // For tracking
            // Only add to the var if is a new entry
            // To update, deregister and re-register
            if(userAccount.tokenAllocation == 0) {
                totalParticipants++;

                userAccount.tokenAllocation = tokenAllocation[index];
                userAccount.pendingTokenAllocation = tokenAllocation[index];

                // For tracking purposes
                totalPendingVestingToken += tokenAllocation[index];
            }
        }

        emit Register(account, tokenAllocation);
    }

    function deRegister(address[] memory account) external onlyOwner {
        require(account.length > 0, "Account array input is empty");
        
        // Iterate through the inputs
        for(uint256 index = 0; index < account.length; index++) {
            // Save into account info
            Account storage userAccount = accounts[account[index]];

            if(userAccount.tokenAllocation > 0) {
                totalParticipants--;

                // For tracking purposes
                totalPendingVestingToken -= userAccount.pendingTokenAllocation;

                userAccount.tokenAllocation = 0;
                userAccount.pendingTokenAllocation = 0;
                userAccount.claimIndex = 0;
                userAccount.claimedTimestamp = 0;
            }
        }

        emit Deregister(account);
    }

    function claim() external {
        Account storage userAccount = accounts[_msgSender()];
        uint256 tokenAllocation = userAccount.tokenAllocation;
        require(tokenAllocation > 0, "Nothing to claim");

        uint256 claimIndex = userAccount.claimIndex;
        require(claimIndex < claimableTimestamp.length, "All tokens claimed");

        //Calculate user vesting distribution amount
        uint256 tokenQuantity = 0;
        for(uint256 index = claimIndex; index < claimableTimestamp.length; index++) {

            uint256 _claimTimestamp = claimableTimestamp[index];   
            if(block.timestamp >= _claimTimestamp) {
                claimIndex++;
                tokenQuantity = tokenQuantity + (tokenAllocation * claimablePercent[_claimTimestamp] / DENOM);
            } else {
                break;
            }
        }
        require(tokenQuantity > 0, "Nothing to claim now, please wait for next vesting");

        //Validate whether contract token balance is sufficient
        uint256 contractTokenBalance = tngToken.balanceOf(address(this));
        require(contractTokenBalance >= tokenQuantity, "Contract token quantity is not sufficient");

        //Update user details
        userAccount.claimedTimestamp = block.timestamp;
        userAccount.claimIndex = claimIndex;
        userAccount.pendingTokenAllocation = userAccount.pendingTokenAllocation - tokenQuantity;

        //For tracking
        totalPendingVestingToken -= tokenQuantity;

        //Release token
        bool status = tngToken.transfer(_msgSender(), tokenQuantity);
        require(status, "Failed to claim");

        emit Claim(_msgSender(), tokenQuantity);
    }

    // Calculate claimable tokens at current timestamp
    function getClaimableAmount(address account) external view returns(uint256) {
        Account storage userAccount = accounts[account];
        uint256 tokenAllocation = userAccount.tokenAllocation;
        uint256 claimIndex = userAccount.claimIndex;

        if(tokenAllocation == 0) return 0;
        if(claimableTimestamp.length == 0) return 0;
        if(block.timestamp < claimableTimestamp[0]) return 0;
        if(claimIndex >= claimableTimestamp.length) return 0;

        uint256 tokenQuantity = 0;
        for(uint256 index = claimIndex; index < claimableTimestamp.length; index++){

            uint256 _claimTimestamp = claimableTimestamp[index];
            if(block.timestamp >= _claimTimestamp){
                tokenQuantity = tokenQuantity + (tokenAllocation * claimablePercent[_claimTimestamp] / DENOM);
            } else {
                break;
            }
        }

        return tokenQuantity;
    }

    // Update claim percentage. Timestamp must match with _claimableTime
    function setClaimable(uint256[] memory timestamp, uint256[] memory percent) public onlyOwner {
        require(timestamp.length > 0, "Empty timestamp input");
        require(timestamp.length == percent.length, "Array size not matched");

        // set claim percentage
        for(uint256 index = 0; index < timestamp.length; index++){
            claimablePercent[timestamp[index]] = percent[index];
        }

        // set claim timestamp
        claimableTimestamp = timestamp;
    }

    function getClaimableTimestamp() external view returns (uint256[] memory){
        return claimableTimestamp;
    }

    function getClaimablePercent() external view returns (uint256[] memory){
        uint256[] memory _claimablePercent = new uint256[](claimableTimestamp.length);

        for(uint256 index = 0; index < claimableTimestamp.length; index++) {

            uint256 _claimTimestamp = claimableTimestamp[index];   
            _claimablePercent[index] = claimablePercent[_claimTimestamp];
        }

        return _claimablePercent;
    }

    function rescueToken(address _token, address _to, uint256 _amount) external onlyOwner {
        uint256 _contractBalance = IERC20(_token).balanceOf(address(this));
        require(_contractBalance >= _amount, "Insufficient tokens");
        IERC20(_token).transfer(_to, _amount);
    }

}
