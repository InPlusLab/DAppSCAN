// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.0;

import "./BytesLib.sol";

// requirement: validate addresses like cosmosvaloper1susdz7trk9edeqf3qprkpunzqn4lyhvlduzncj
/* 
cosmos1dgtl8dqky0cucr9rlllw9cer9ysrkjnjagz5zp
cosmospub1addwnpepq272xswjqka4wm6x8nvuwshdquh0q8xrxlafz7lj32snvtg2jswl6x5ywwu
cosmosvaloper1susdz7trk9edeqf3qprkpunzqn4lyhvlduzncj
cosmosvaloperpub1addwnpepq272xswjqka4wm6x8nvuwshdquh0q8xrxlafz7lj32snvtg2jswl60hprp0
bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4
*/

library Bech32 {
	using BytesLib for bytes;

	bytes constant CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l";

	/**
	 * @dev validates if address is valid
	 * @param blockchainAddress_: account address
	 * @param hrpBytes_: hrp in bytes
	 * @param controlDigitBytes_: control Digit in Bytes
	 * @param dataBytesSize_: data size in Bytes
	 */
	function isBech32AddressValid(
		string memory blockchainAddress_,
		bytes memory hrpBytes_,
		bytes memory controlDigitBytes_,
		uint256 dataBytesSize_
	) internal pure returns (bool) {
		// return bech32ValidateStr(blockchainAddress);
		bytes memory _addressBytesLocal = bytes(blockchainAddress_);
		// split hrp and compare with the bytes hrp stored
		bytes memory _hrpBytesLocal = _addressBytesLocal.slice(
			0,
			hrpBytes_.length
		);
		if (!_hrpBytesLocal.equal(hrpBytes_)) return false;

		// split controlDigitBytes_ and compare with the bytes controlDigitBytes_ stored
		bytes memory _controlDigestBytes = _addressBytesLocal.slice(
			_hrpBytesLocal.length,
			1
		);
		if (!_controlDigestBytes.equal(controlDigitBytes_)) return false;

		// split addressData and compare the length with dataBytesSize_
		bytes memory _dataBytes = _addressBytesLocal.slice(
			_hrpBytesLocal.length + 1,
			(_addressBytesLocal.length - _hrpBytesLocal.length - 1)
		);
		if (_dataBytes.length != dataBytesSize_) return false;

		// validate checksum
		bytes memory _dataSliceBytes = _addressBytesLocal.slice(
			_hrpBytesLocal.length + 1,
			(_addressBytesLocal.length - 6 - _hrpBytesLocal.length - 1)
		);
		// decode data slice using the CHARSET
		uint256[] memory _dataSlice = decode(_dataSliceBytes);
		if (_dataSlice.length == 0) return false;
		// convert hrp Bytes to uint[]
		uint256[] memory _hrp = toUintFromBytes(_hrpBytesLocal);
		// calculate checksummed data
		bytes memory checksummedDataBytes = encode(_hrp, _dataSlice);
		bool isValid = _dataBytes.equal(checksummedDataBytes);
		// isValid = _dataSliceBytes.equal(checksummedDataBytes);

		return isValid;
	}

	/**
	 * @dev decodes the account address and returns decoded bytes array
	 * @param addressDigestBytes_: account address in bytes
	 */
	function decode(bytes memory addressDigestBytes_)
		internal
		pure
		returns (uint256[] memory decodedBytes)
	{
		decodedBytes = new uint256[](addressDigestBytes_.length);
		uint256[] memory nullBytes;
		uint256 charsetIndex;

		for (
			uint256 addressDigestBytesIndex = 0;
			addressDigestBytesIndex < addressDigestBytes_.length;
			addressDigestBytesIndex++
		) {
			for (
				charsetIndex = 0;
				charsetIndex < CHARSET.length;
				charsetIndex++
			) {
				if (
					addressDigestBytes_[addressDigestBytesIndex] ==
					CHARSET[charsetIndex]
				) break;
			}
			if (charsetIndex == CHARSET.length) return nullBytes;
			decodedBytes[addressDigestBytesIndex] = charsetIndex;
		}
		return decodedBytes;
	}

	/**
	 * @dev converts bytes to uint and returns data digest array
	 * @param dataDigestBytes_: data digest in bytes
	 */
	function toUintFromBytes(bytes memory dataDigestBytes_)
		internal
		pure
		returns (uint256[] memory dataDigest)
	{
		dataDigest = new uint256[](dataDigestBytes_.length);
		for (
			uint256 dataDigestIndex = 0;
			dataDigestIndex < dataDigestBytes_.length;
			dataDigestIndex++
		) {
			dataDigest[dataDigestIndex] = uint256(
				uint8(dataDigestBytes_[dataDigestIndex])
			);
		}
		return dataDigest;
	}

	/**
	 * @dev checks the polymod and return int value
	 * @param values: values in array
	 */
	function polymod(uint256[] memory values) internal pure returns (uint256) {
		uint32[5] memory GENERATOR = [
			0x3b6a57b2,
			0x26508e6d,
			0x1ea119fa,
			0x3d4233dd,
			0x2a1462b3
		];
		uint256 chk = 1;
		for (uint256 p = 0; p < values.length; p++) {
			uint256 top = chk >> 25;
			chk = ((chk & 0x1ffffff) << 5) ^ values[p];
			for (uint256 i = 0; i < 5; i++) {
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
	function hrpExpand(uint256[] memory hrp)
		internal
		pure
		returns (uint256[] memory)
	{
		uint256[] memory ret = new uint256[](hrp.length + hrp.length + 1);
		for (uint256 p = 0; p < hrp.length; p++) {
			ret[p] = hrp[p] >> 5;
		}
		ret[hrp.length] = 0;
		for (uint256 p = 0; p < hrp.length; p++) {
			ret[p + hrp.length + 1] = hrp[p] & 31;
		}
		return ret;
	}

	/**
	 * @dev  combines two strings together
	 * @param left: left int value in array
	 * @param right: right int value in array
	 */
	function concat(uint256[] memory left, uint256[] memory right)
		internal
		pure
		returns (uint256[] memory)
	{
		uint256[] memory ret = new uint256[](left.length + right.length);

		uint256 i = 0;
		for (; i < left.length; i++) {
			ret[i] = left[i];
		}

		uint256 j = 0;
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
	function extend(
		uint256[] memory array,
		uint256 val,
		uint256 num
	) internal pure returns (uint256[] memory) {
		uint256[] memory ret = new uint256[](array.length + num);

		uint256 i = 0;
		for (; i < array.length; i++) {
			ret[i] = array[i];
		}

		uint256 j = 0;
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
	function createChecksum(uint256[] memory hrp, uint256[] memory data)
		internal
		pure
		returns (uint256[] memory)
	{
		uint256[] memory values = extend(concat(hrpExpand(hrp), data), 0, 6);
		uint256 mod = polymod(values) ^ 1;
		uint256[] memory ret = new uint256[](6);
		for (uint256 p = 0; p < 6; p++) {
			ret[p] = (mod >> (5 * (5 - p))) & 31;
		}
		return ret;
	}

	/**
	 * @dev  encode to the bech32 alphabet list
	 * @param hrp: hrp int value in array
	 * @param data: data int value in array
	 */
	function encode(uint256[] memory hrp, uint256[] memory data)
		internal
		pure
		returns (bytes memory)
	{
		uint256[] memory combined = concat(data, createChecksum(hrp, data));
		// uint[] memory combined = data;

		// TODO: prepend hrp

		// convert uint[] to bytes
		bytes memory ret = new bytes(combined.length);
		for (uint256 p = 0; p < combined.length; p++) {
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
	function convert(
		uint256[] memory data,
		uint256 inBits,
		uint256 outBits
	) internal pure returns (uint256[] memory) {
		uint256 value = 0;
		uint256 bits = 0;
		uint256 maxV = (1 << outBits) - 1;

		uint256[] memory ret = new uint256[](32);
		uint256 j = 0;
		for (uint256 i = 0; i < data.length; ++i) {
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
