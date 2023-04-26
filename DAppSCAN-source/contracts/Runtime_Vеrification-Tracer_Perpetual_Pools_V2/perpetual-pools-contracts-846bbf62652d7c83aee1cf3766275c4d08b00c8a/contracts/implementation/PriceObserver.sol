//SPDX-License-Identifier: CC-BY-NC-ND-4.0
pragma solidity 0.8.7;

import "../interfaces/IPriceObserver.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PriceObserver is Ownable, IPriceObserver {
    uint256 public constant MAX_NUM_ELEMS = 24;
    uint256 public numElems = 0;
    int256[MAX_NUM_ELEMS] public observations;
    address writer = address(0);

    function capacity() public pure override returns (uint256) {
        return MAX_NUM_ELEMS;
    }

    function length() public view override returns (uint256) {
        return numElems;
    }

    function get(uint256 i) public view override returns (int256) {
        require(i < length(), "PO: Out of bounds");
        return observations[i];
    }

    function getAll() public view override returns (int256[24] memory) {
        return observations;
    }

    function add(int256 x) public override onlyWriter returns (bool) {
        if (full()) {
            leftRotateWithPad(x);
            return true;
        } else {
            observations[length()] = x;
            numElems += 1;
            return false;
        }
    }

    function setWriter(address _writer) public onlyOwner {
        require(_writer != address(0), "PO: Null address not allowed");
        writer = _writer;
    }

    function getWriter() public view returns (address) {
        return writer;
    }

    function full() private view returns (bool) {
        return length() == capacity();
    }

    function clear() public onlyOwner {
        numElems = 0;
        delete observations;
    }

    /**
     * @notice Rotates observations array to the **left** by one element and sets the last element of `xs` to `x`
     * @param x Element to "rotate into" observations array
     *
     */
    function leftRotateWithPad(int256 x) private {
        uint256 n = length();

        /* linear scan over the [1, n] subsequence */
        for (uint256 i = 1; i < n; i++) {
            observations[i - 1] = observations[i];
        }

        /* rotate `x` into `observations` from the right (remember, we're **left**
         * rotating -- with padding!) */
        observations[n - 1] = x;
    }

    modifier onlyWriter() {
        require(msg.sender == writer, "PO: Permission denied");
        _;
    }
}
