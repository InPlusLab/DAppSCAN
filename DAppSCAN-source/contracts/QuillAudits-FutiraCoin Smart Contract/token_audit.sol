// File: contracts/VESTATToken.sol
pragma solidity ^0.8.0;
contract XXXToken is ERC20 {
   mapping(address => bool) public signers;
   uint pendingTransactionID = 1;//SWC-108-State Variable Default Visibility:L5
   uint public TransactionsCount = 0;
   uint[] public PendingTransactionList;
   uint public currentTotalSupply;
   address public owner;
   address public VestingWallet; 
   mapping(uint => VestingTransaction) public VestingTransactions;
   struct VestingTransaction
   {
       address to;
       uint amount;
       string status;
       uint ExecuteDate;
       uint DueDate;
   }
//SWC-135-Code With No Effects:L21,83
   event TransferedFromCurrentSupply(uint from, address indexed to, uint256 value); 
   event SoldToken(address from, address to, uint256 amount);  
   modifier onlyOwner {
       require(msg.sender == owner, "You are not the owner of this smart contract. Contact info@futiracoin.com for help.");
       _;    }
   modifier onlyVestingWallet {
       require(msg.sender == VestingWallet, "You are not the VestingWallet of this smart contract. Contact info@futiracoin.com for help.");
       _;    }
   modifier onlySigner {
       require(signers[msg.sender] == true, "You are not the signer of this smart contract. Contact info@futiracoin.com for help.");
       _;    }
   constructor() ERC20("XXXToken", "XXX") {
       VestingWallet = address(this) ;
       _mint(msg.sender, 10000000000 * 10 ** 6);
       owner = msg.sender;
       signers[0x75Df3A4B10a18774c716221270037F55C32F41f4] = true;
       signers[0xFEBF8C088d8B823cAADC93ec40F99E162b50B6FF] = true;
       currentTotalSupply = totalSupply();
   }
    // To get a detail about a pending transaction
   function getVestingTransaction(uint _id) public view returns(address, uint, string memory, uint) {
       return (VestingTransactions[_id].to, VestingTransactions[_id].amount, VestingTransactions[_id].status, VestingTransactions[_id].DueDate);
   }  
    // To get number of last pending transaction and count of not signed
   function getcurrentPendingTransactions() public view returns( uint, uint, uint){
       uint count = 0;
       uint FirstTRX = 0;
       uint LastTRX = 0;
       for(uint i = 0; i<TransactionsCount; i++){
       if( keccak256(abi.encodePacked((VestingTransactions[i].status))) == keccak256(abi.encodePacked(("pending")))){  
       count++;
       LastTRX=i;
       if(FirstTRX ==0){
           FirstTRX=i; }
       }   
       }
       return (FirstTRX,count,LastTRX);
   }
   // To get number of last pending transaction and count of not signed
   function getWalletVests(address account) public view virtual  returns (uint, uint)
   {
       uint numberofTRX = 0;
       uint Total_amount = 0;
      for(uint i = 0; i < TransactionsCount; i++)
       {
               if( VestingTransactions[i].to == account && keccak256(abi.encodePacked((VestingTransactions[i].status))) != keccak256(abi.encodePacked(("successful"))))
               {
                  Total_amount=Total_amount+VestingTransactions[i].amount;
                  numberofTRX=numberofTRX+1;
               }  }
       return (Total_amount , numberofTRX);
   }
   // To check whether an ID is in the PendingTransactionList
   function checkVestingTransactionList(uint _id) internal view returns(bool)
   {


           if(keccak256(abi.encodePacked((VestingTransactions[_id].status))) == keccak256(abi.encodePacked(("pending"))))
           {  return true; }
       return false;
   }
   // To change the status into failed and delete all the pending transaction that has exceed the time allowed
   function deleteExceededTimeVestingTransaction() internal returns(bool)
   {
       for(uint i = 0; i < PendingTransactionList.length; i++)
       {
       
           if( block.timestamp > VestingTransactions[i].DueDate)
           {
               VestingTransactions[i].status = "Duted";
               PendingTransactionList[i]=0;
           }
           else if(block.timestamp > VestingTransactions[i].ExecuteDate + 3600 && keccak256(abi.encodePacked((VestingTransactions[i].status))) == keccak256(abi.encodePacked(("pending")))){
               VestingTransactions[i].status = "failed";
               PendingTransactionList[i]=0;
           }  }
       return true;  
   }
   function approvePendingVestingTransactions() onlySigner public returns(bool)
   {
       uint i;
       for( i = 0; i < TransactionsCount; i++)
       {  
               if(keccak256(abi.encodePacked((VestingTransactions[i].status))) == keccak256(abi.encodePacked(("pending"))))
               {
                   approvePendingVestingTransaction(i);
               }
          
       }
       if(i > 0){
           return true;
       }
       else{
           return false;
      }    }
     function approvePendingVestingTransaction(uint256 _id) onlySigner public returns(bool)
   {
     
       bool check = checkVestingTransactionList(_id);
           if(check || _id==0)
           {
               if(block.timestamp < VestingTransactions[_id].ExecuteDate + 3600 && keccak256(abi.encodePacked((VestingTransactions[_id].status))) == keccak256(abi.encodePacked(("pending"))))
               {
                   if(VestingTransactions[_id].DueDate < block.timestamp ){
                       VestingTransactions[_id].status ="successful";
                       _transfer(owner, VestingTransactions[_id].to, VestingTransactions[_id].amount);
                       PendingTransactionList[_id]=0;
                   }
                   else {
                   VestingTransactions[_id].status ="approved";
                    _transfer(owner, VestingWallet, VestingTransactions[_id].amount);
                      PendingTransactionList[_id]=0;
                   }
                   return true;
               }
               else if (block.timestamp > VestingTransactions[_id].ExecuteDate + 3600 && keccak256(abi.encodePacked((VestingTransactions[_id].status))) == keccak256(abi.encodePacked(("pending")))){
                   VestingTransactions[_id].status ="failed";
                   PendingTransactionList[_id]=0;
                    return false;
               }   }
           return false; }
   // This function will create a pending transaction for signer to sign
   function createVestingTransaction(address _to, uint _amount, uint Due_Date) public onlyOwner returns(uint)
   {
       uint id =  TransactionsCount;
       VestingTransactions[id] = VestingTransaction(_to, _amount, "pending",block.timestamp, Due_Date);
       PendingTransactionList.push(id+1);
       pendingTransactionID = pendingTransactionID + 1;
       TransactionsCount = TransactionsCount +1;
       return id;
   }


   function Claim() public returns (bool)
   {
       bool status = false;
       for(uint i = 0; i<TransactionsCount; i++)
       {
       if(VestingTransactions[i].DueDate <= block.timestamp && VestingTransactions[i].to == _msgSender() )
       {
           status = true;
       if(keccak256(abi.encodePacked((VestingTransactions[i].status))) == keccak256(abi.encodePacked(("approved"))))
       {
           address _to = VestingTransactions[i].to;
           uint _amount = VestingTransactions[i].amount;
           _transfer(VestingWallet, msg.sender, _amount);  
           VestingTransactions[i].status = "successful";
           emit SoldToken(VestingWallet, _to, _amount);
       }  }  }
       if (!status){
           revert("You currently don't have duted transactions . Contact info@futiracoin.com for help.");
       }
       return status;
   }
   function setTotalSupply(string memory operation, uint _amount) onlyOwner public returns(uint)
   {
       if(keccak256(abi.encodePacked((operation))) == keccak256(abi.encodePacked(("add"))))
       {
           _mint(msg.sender, _amount);
           currentTotalSupply += _amount;
       }
       else if(keccak256(abi.encodePacked((operation))) == keccak256(abi.encodePacked(("delete"))))
       {
           require(currentTotalSupply >= _amount, "The amount is greater than the total supply. Contact info@futiracoin.com for help.");
           _burn(msg.sender, _amount);
           currentTotalSupply -= _amount;
       }
       else
       {
           revert("This operation is not acceptable. Contact info@futiracoin.com for help.");
       } 
       return totalSupply();
   }
    function transfer(address recipient, uint amount) override public returns (bool) {
        if(msg.sender==owner){
            createVestingTransaction( recipient, amount, block.timestamp);
           return true;
        }   
        _transfer(_msgSender(), recipient, amount);
       return true;
   }   }