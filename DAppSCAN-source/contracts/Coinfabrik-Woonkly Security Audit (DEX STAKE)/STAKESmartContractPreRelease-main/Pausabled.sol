// SPDX-License-Identifier: MIT
pragma solidity ^0.6.6;

import "https://github.com/Woonkly/MartinHSolUtils/Owners.sol";

/**
MIT License

Copyright (c) 2021 Woonkly OU

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED BY WOONKLY OU "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

contract Pausabled is Owners {
    //Section Type declarations

    //Section State variables
    bool internal _paused;

    //Section Modifier
    modifier Active() {
        require(!isPaused(), "paused");
        _;
    }

    function isPaused() public view returns (bool) {
        return _paused;
    }

    //Section Events
    event Paused(bool paused);

    function _setPause(bool paused) internal virtual returns (bool) {
        _paused = paused;
        emit Paused(_paused);
        return true;
    }

    //Section functions
    function setPause(bool paused)
        public
        virtual
        onlyIsInOwners
        returns (bool)
    {
        return _setPause(paused);
    }
}
