// SPDX-License-Identifier: UNLICENSED
pragma solidity >= 0.7.0;


import "./BytesLib.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";


// requirement: validate addresses like cosmosvaloper1susdz7trk9edeqf3qprkpunzqn4lyhvlduzncj
/* 
cosmos1dgtl8dqky0cucr9rlllw9cer9ysrkjnjagz5zp
cosmospub1addwnpepq272xswjqka4wm6x8nvuwshdquh0q8xrxlafz7lj32snvtg2jswl6x5ywwu
cosmosvaloper1susdz7trk9edeqf3qprkpunzqn4lyhvlduzncj
cosmosvaloperpub1addwnpepq272xswjqka4wm6x8nvuwshdquh0q8xrxlafz7lj32snvtg2jswl60hprp0
bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4

1. split the address to hrp and data
2. check the hrp ? 
2. data part length should be greater than or equal to 6
3. convert data part from bech32 encoding to  

steps:
1. get address as bytes
2. split hrp and compare with the bytes hrp stored
3. split controlDigit and compare with the bytes controlDigit stored
4. splity addressData and compate the length with dataSize
5. 
*/

contract Bech32Validation is Initializable {
    using BytesLib for bytes;

    bytes constant CHARSET = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
    bytes hrpBytes;
    bytes controlDigitBytes;
    uint dataSize;

    /*
  * @dev Constructor for initializing the Bech32Validation contract.
  * sets hrpBytes, controlDigitBytes and dataSize value
  */
    function initialize() public virtual initializer {
        hrpBytes = "cosmos";
        controlDigitBytes = "1"; 
        dataSize = 38;
    }

    /**
     * @dev Return bool value based on address validation
     * @param blockchainAddress: account address
     */
    function isBech32AddressValid(string memory blockchainAddress) public view returns(bool) {
        return bech32ValidateStr(blockchainAddress);
    }

    /**
     * @dev splits the address with the hrp and validates the address
     * @param addressDigestStr_: account address
     */
    function bech32ValidateStr(string memory addressDigestStr_) public view returns(bool) {
        bool isValid;

        // split hrp and compare with the bytes hrp stored
        isValid = hrpValidateStr(addressDigestStr_);
        if(!isValid) return isValid;

        // split controlDigit_ and compare with the bytes controlDigit_ stored
        isValid = controlDigitValidateStr(addressDigestStr_);
        if(!isValid) return isValid;

        // split addressData and compare the length with dataSize_
        isValid = dataSizeValidateStr(addressDigestStr_);
        if(!isValid) return isValid;

        // validate checksum
        isValid = checksumValidateStr(addressDigestStr_);
        if(!isValid) return isValid;
       
        return isValid;
    }

    /**
     * @dev split hrp and compare with the bytes hrp stored
     * @param addressDigestBytes_: account address in bytes
     * @param hrpBytes_: hrp in bytes
     * @param controlDigitBytes_: set digit bytes (initially set to 1)
     * @param dataSize_: data size (initially set to 38)
     */
    function bech32Validate(bytes memory addressDigestBytes_, bytes memory hrpBytes_, bytes memory controlDigitBytes_, uint dataSize_) public pure returns(bool) {
        bool isValid;

        // split hrp and compare with the bytes hrp stored
        isValid = hrpValidate(addressDigestBytes_, hrpBytes_);
        if(!isValid) return isValid;

        // split controlDigit_ and compare with the bytes controlDigit_ stored
        isValid = controlDigitValidate(addressDigestBytes_, hrpBytes_, controlDigitBytes_);
        if(!isValid) return isValid;

        // split addressData and compare the length with dataSize_
        isValid = dataSizeValidate(addressDigestBytes_, hrpBytes_, dataSize_);
        if(!isValid) return isValid;

        // validate checksum
        isValid = checksumValidate(addressDigestBytes_, hrpBytes_);
        if(!isValid) return isValid;
       
        return isValid;
    }

    /**
     * @dev converted address to bytes and validates its length and validates hrp
     * @param addressDigestStr_: account address
     */
    function hrpValidateStr(string memory addressDigestStr_) public view returns(bool) {
        bytes memory addressDigestBytes_ = bytes(addressDigestStr_);
        if(addressDigestBytes_.length != 45) return false;
        return hrpValidate(addressDigestBytes_, hrpBytes);
    }

    /**
     * @dev slices the account address in bytes and compares it with hrpBytes
     * @param addressDigestBytes_: account address n bytes
     * @param hrpBytes_: hrp converted to bytes
     */
    function hrpValidate(bytes memory addressDigestBytes_, bytes memory hrpBytes_) public pure returns(bool) {
        bytes memory hrpDigestBytes = addressDigestBytes_.slice(0, hrpBytes_.length);
        if(!hrpDigestBytes.equal(hrpBytes_)) return false;
        return true;
    }

    /**
     * @dev Returns account address converted to bytes and validates control digits
     * @param addressDigestStr_: account address
     */
    function controlDigitValidateStr(string memory addressDigestStr_) public view returns(bool) {
        bytes memory addressDigestBytes_ = bytes(addressDigestStr_);
        return controlDigitValidate(addressDigestBytes_, hrpBytes, controlDigitBytes);
    }

    /**
     * @dev slices the account address in bytes and compares it with control digest bytes
     * @param addressDigestBytes_: account address converted to bytes
     * @param hrpBytes_: hrp in bytes
     * @param controlDigit_: control digit in bytes
     */
    function controlDigitValidate(bytes memory addressDigestBytes_, bytes memory hrpBytes_, bytes memory controlDigit_) public pure returns(bool) {
        bytes memory _controlDigestBytes = addressDigestBytes_.slice(hrpBytes_.length, 1);
        if(!_controlDigestBytes.equal(controlDigit_)) return false;
        return true;
    }

    /**
     * @dev validates the dara size
     * @param addressDigestStr_: account address
     */
    function dataSizeValidateStr(string memory addressDigestStr_) public view returns(bool) {
        bytes memory addressDigestBytes_ = bytes(addressDigestStr_);
        return dataSizeValidate(addressDigestBytes_, hrpBytes, dataSize);
    }

    /**
     * @dev validates the dara size
     * @param addressDigestBytes_: account address in bytes
     * @param hrpBytes_: hrp in bytes
     * @param dataSize_: data size in bytes
     */
    function dataSizeValidate(bytes memory addressDigestBytes_, bytes memory hrpBytes_, uint dataSize_) public pure returns(bool) {
        bytes memory _dataDigestBytes = addressDigestBytes_.slice(hrpBytes_.length+1, (addressDigestBytes_.length-hrpBytes_.length-1));
        if(_dataDigestBytes.length != dataSize_) return false;
        return true;
    }

    /**
     * @dev validates the checksun
     * @param addressDigestStr_: account address
     */
    function checksumValidateStr(string memory addressDigestStr_) public view returns(bool) {
        bytes memory addressDigestBytes_ = bytes(addressDigestStr_);
        return checksumValidate(addressDigestBytes_, hrpBytes);
    }

    /**
     * @dev calculates checksummed data and return bool
     * @param addressDigestBytes_: account address in bytes
     * @param hrpBytes_: hrp in bytes
     */
    function checksumValidate(bytes memory addressDigestBytes_, bytes memory hrpBytes_) public pure returns(bool) {
        bool isValid;
        bytes memory checksummedDataBytes;

        // convert addressDigestBytes to addressDigest
        // uint[] addressDigest = decode(_dataDigestBytes);
        bytes memory dataBytes = addressDigestBytes_.slice(hrpBytes_.length + 1, addressDigestBytes_.length - hrpBytes_.length - 1);
        bytes memory dataSliceBytes = addressDigestBytes_.slice(hrpBytes_.length + 1, (addressDigestBytes_.length - 6 - hrpBytes_.length - 1));

        // convert data slice bytes to uint[]
        // uint[] memory dataSlice = toUintFromBytes(dataSliceBytes);
        uint[] memory dataSlice = decode(dataSliceBytes);
        if(dataSlice.length == 0) return false;

        // convert hrp Bytes to uint[]
        uint[] memory hrp = toUintFromBytes(hrpBytes_);

        // calculate checksummed data
        checksummedDataBytes = encode(hrp, dataSlice);
        isValid = dataBytes.equal(checksummedDataBytes);
        // isValid = dataSliceBytes.equal(checksummedDataBytes);

        return isValid;
    }

    /**
     * @dev decodes the account address and returns decoded bytes
     * @param addressDigestStr_: account address
     */
    function decodeStr(string memory addressDigestStr_) public pure returns(uint[] memory decodedBytes) {
        bytes memory _addressDigestBytes = bytes(addressDigestStr_);
        decodedBytes = decode(_addressDigestBytes);
        return decodedBytes;
    }

    /**
     * @dev decodes the account address and returns decoded bytes array
     * @param addressDigestBytes_: account address in bytes
     */
    function decode(bytes memory addressDigestBytes_) public pure returns(uint[] memory decodedBytes) {
        decodedBytes = new uint[](addressDigestBytes_.length);
        uint[] memory nullBytes;
        uint charsetIndex;

        for (uint addressDigestBytesIndex = 0; addressDigestBytesIndex < addressDigestBytes_.length; addressDigestBytesIndex++) {
            for (charsetIndex = 0; charsetIndex < CHARSET.length; charsetIndex++) {
                if(addressDigestBytes_[addressDigestBytesIndex] == CHARSET[charsetIndex])
                break;
            }
            if(charsetIndex == CHARSET.length) return nullBytes;
            decodedBytes[addressDigestBytesIndex] = charsetIndex;
        }
        return decodedBytes;
    }

    /**
     * @dev converts string to uint and returns data digest array
     * @param dataDigestStr_: data digest
     */
    function toUintFromStr(string memory dataDigestStr_) public pure returns(uint[] memory dataDigest) {
        bytes memory _dataDigestBytes = bytes(dataDigestStr_);
        return toUintFromBytes(_dataDigestBytes);
    }

    /**
     * @dev converts bytes to uint and returns data digest array
     * @param dataDigestBytes_: data digest in bytes
     */
    function toUintFromBytes(bytes memory dataDigestBytes_) public pure returns(uint[] memory dataDigest) {
        dataDigest = new uint[](dataDigestBytes_.length);
        for (uint dataDigestIndex = 0; dataDigestIndex < dataDigestBytes_.length; dataDigestIndex++) {
            dataDigest[dataDigestIndex] = uint256(uint8(dataDigestBytes_[dataDigestIndex]));
        }
        return dataDigest;
    }

    /**
     * @dev converts bytes2 to uint and returns data digest array
     * @param dataDigestBytes_: data digest in bytes
     */
    function toUintFromBytes2(bytes memory dataDigestBytes_) public pure returns(uint[] memory dataDigest) {
        dataDigest = new uint[](dataDigestBytes_.length);
        for (uint dataDigestIndex = 0; dataDigestIndex < dataDigestBytes_.length; dataDigestIndex++) {
            dataDigest[dataDigestIndex] = uint256(bytes32(dataDigestBytes_[dataDigestIndex]));
        }
        return dataDigest;
    }

    /**
     * @dev checks the polymod and return int value
     * @param values: values in array
     */
    function polymod(uint[] memory values) internal pure returns(uint) {
        uint32[5] memory GENERATOR = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];
        uint chk = 1;
        for (uint p = 0; p < values.length; p++) {
            uint top = chk >> 25;
            chk = (chk & 0x1ffffff) << 5 ^ values[p];
            for (uint i = 0; i < 5; i++) {
                if ((top >> i) & 1 == 1) {
                    chk ^= GENERATOR[i];
                }
            }
        }
        return chk;
    }

    /**
     * @dev expands the hrp and return int[] value
     * @param hrp: hrp in array
     */
    function hrpExpand(uint[] memory hrp) internal pure returns (uint[] memory) {
        uint[] memory ret = new uint[](hrp.length+hrp.length+1);
        for (uint p = 0; p < hrp.length; p++) {
            ret[p] = hrp[p] >> 5;
        }
        ret[hrp.length] = 0;
        for (uint p = 0; p < hrp.length; p++) {
            ret[p+hrp.length+1] = hrp[p] & 31;
        }
        return ret;
    }

    /**
     * @dev  combines two strings together
     * @param left: left int value in array
     * @param right: right int value in array
     */
    function concat(uint[] memory left, uint[] memory right) internal pure returns(uint[] memory) {
        uint[] memory ret = new uint[](left.length + right.length);

        uint i = 0;
        for (; i < left.length; i++) {
            ret[i] = left[i];
        }

        uint j = 0;
        while (j < right.length) {
            ret[i++] = right[j++];
        }

        return ret;
    }

    /**
     * @dev  add trailing padding to the data
     * @param array: array int value in array
     * @param val: value
     * @param num: num
     */
    function extend(uint[] memory array, uint val, uint num) internal pure returns(uint[] memory) {
        uint[] memory ret = new uint[](array.length + num);

        uint i = 0;
        for (; i < array.length; i++) {
            ret[i] = array[i];
        }

        uint j = 0;
        while (j < num) {
            ret[i++] = val;
            j++;
        }

        return ret;
    }

    /**
    * @dev  create checksum
    * @param hrp: hrp int value in array
    * @param data: data int value in array
    */
    function createChecksum(uint[] memory hrp, uint[] memory data) internal pure returns (uint[] memory) {
        uint[] memory values = extend(concat(hrpExpand(hrp), data), 0, 6);
        uint mod = polymod(values) ^ 1;
        uint[] memory ret = new uint[](6);
        for (uint p = 0; p < 6; p++) {
            ret[p] = (mod >> 5 * (5 - p)) & 31;
        }
        return ret;
    }

    /**
    * @dev  encode to the bech32 alphabet list
    * @param hrp: hrp int value in array
    * @param data: data int value in array
    */
    function encode(uint[] memory hrp, uint[] memory data) internal pure returns (bytes memory) {
        uint[] memory combined = concat(data, createChecksum(hrp, data));
        // uint[] memory combined = data;

        // TODO: prepend hrp

        // convert uint[] to bytes
        bytes memory ret = new bytes(combined.length);
        for (uint p = 0; p < combined.length; p++) {
            ret[p] = CHARSET[combined[p]];
        }

        return ret;
    }

    /**
    * @dev  converts the data
    * @param data: data int value in array
    * @param inBits: inBits
    * @param outBits: outBits
    */
    function convert(uint[] memory data, uint inBits, uint outBits) internal pure returns (uint[] memory) {
        uint value = 0;
        uint bits = 0;
        uint maxV = (1 << outBits) - 1;

        uint[] memory ret = new uint[](32);
        uint j = 0;
        for (uint i = 0; i < data.length; ++i) {
            value = (value << inBits) | data[i];
            bits += inBits;

            while (bits >= outBits) {
                bits -= outBits;
                ret[j] = (value >> bits) & maxV;
                j += 1;
            }
        }
        return ret;
    }
}