pragma solidity >=0.6.0;


contract Rating {
    string public name;
    uint256 public risk;
    bool public fine;

    constructor(string memory _name, uint256 _risk, bool _fine) public {
        name = _name;
        risk = _risk;
        fine = _fine;
    }
}

