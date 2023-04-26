pragma solidity 0.5.14;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";

// This is for per user
library AccountTokenLib {
    using SafeMath for uint256;
    struct TokenInfo {
        // Deposit info
        uint256 depositPrincipal;   // total deposit principal of ther user
        uint256 depositInterest;    // total deposit interest of the user
        uint256 lastDepositBlock;   // the block number of user's last deposit
        // Borrow info
        uint256 borrowPrincipal;    // total borrow principal of ther user
        uint256 borrowInterest;     // total borrow interest of ther user
        uint256 lastBorrowBlock;    // the block number of user's last borrow
    }

    uint256 constant BASE = 10**18;

    // returns the principal
    function getDepositPrincipal(TokenInfo storage self) public view returns(uint256) {
        return self.depositPrincipal;
    }

    function getBorrowPrincipal(TokenInfo storage self) public view returns(uint256) {
        return self.borrowPrincipal;
    }

    function getDepositBalance(TokenInfo storage self, uint accruedRate) public view returns(uint256) {
        return self.depositPrincipal.add(calculateDepositInterest(self, accruedRate));
    }

    function getBorrowBalance(TokenInfo storage self, uint accruedRate) public view returns(uint256) {
        return self.borrowPrincipal.add(calculateBorrowInterest(self, accruedRate));
    }

    function getLastDepositBlock(TokenInfo storage self) public view returns(uint256) {
        return self.lastDepositBlock;
    }

    function getLastBorrowBlock(TokenInfo storage self) public view returns(uint256) {
        return self.lastBorrowBlock;
    }

    function getDepositInterest(TokenInfo storage self) public view returns(uint256) {
        return self.depositInterest;
    }

    function getBorrowInterest(TokenInfo storage self) public view returns(uint256) {
        return self.borrowInterest;
    }

    function borrow(TokenInfo storage self, uint256 amount, uint256 accruedRate, uint256 _block) public {
        newBorrowCheckpoint(self, accruedRate, _block);
        self.borrowPrincipal = self.borrowPrincipal.add(amount);
    }

    /**
     * Update token info for withdraw. The interest will be withdrawn with higher priority.
     */
    function withdraw(TokenInfo storage self, uint256 amount, uint256 accruedRate, uint256 _block) public {
        newDepositCheckpoint(self, accruedRate, _block);
        if (self.depositInterest >= amount) {
            self.depositInterest = self.depositInterest.sub(amount);
        } else if (self.depositPrincipal.add(self.depositInterest) >= amount) {
            self.depositPrincipal = self.depositPrincipal.sub(amount.sub(self.depositInterest));
            self.depositInterest = 0;
        } else {
            self.depositPrincipal = 0;
            self.depositInterest = 0;
        }
    }

    /**
     * Update token info for deposit
     */
    function deposit(TokenInfo storage self, uint256 amount, uint accruedRate, uint256 _block) public {
        newDepositCheckpoint(self, accruedRate, _block);
        self.depositPrincipal = self.depositPrincipal.add(amount);
    }

    function repay(TokenInfo storage self, uint256 amount, uint accruedRate, uint256 _block) public {
        // updated rate (new index rate), applying the rate from startBlock(checkpoint) to currBlock
        newBorrowCheckpoint(self, accruedRate, _block);
        // user owes money, then he tries to repays
        if (self.borrowInterest > amount) {
            self.borrowInterest = self.borrowInterest.sub(amount);
        } else if (self.borrowPrincipal.add(self.borrowInterest) > amount) {
            self.borrowPrincipal = self.borrowPrincipal.sub(amount.sub(self.borrowInterest));
            self.borrowInterest = 0;
        } else {
            self.borrowPrincipal = 0;
            self.borrowInterest = 0;
        }
    }

    function newDepositCheckpoint(TokenInfo storage self, uint accruedRate, uint256 _block) public {
        self.depositInterest = calculateDepositInterest(self, accruedRate);
        self.lastDepositBlock = _block;
    }

    function newBorrowCheckpoint(TokenInfo storage self, uint accruedRate, uint256 _block) public {
        self.borrowInterest = calculateBorrowInterest(self, accruedRate);
        self.lastBorrowBlock = _block;
    }

    // Calculating interest according to the new rate
    // calculated starting from last deposit checkpoint
    function calculateDepositInterest(TokenInfo storage self, uint accruedRate) public view returns(uint256) {
        return self.depositPrincipal.add(self.depositInterest).mul(accruedRate).sub(self.depositPrincipal.mul(BASE)).div(BASE);
    }

    function calculateBorrowInterest(TokenInfo storage self, uint accruedRate) public view returns(uint256) {
        uint256 _balance = self.borrowPrincipal;
        if(accruedRate == 0 || _balance == 0 || BASE >= accruedRate) {
            return self.borrowInterest;
        } else {
            return _balance.add(self.borrowInterest).mul(accruedRate).sub(_balance.mul(BASE)).div(BASE);
        }
    }
}
