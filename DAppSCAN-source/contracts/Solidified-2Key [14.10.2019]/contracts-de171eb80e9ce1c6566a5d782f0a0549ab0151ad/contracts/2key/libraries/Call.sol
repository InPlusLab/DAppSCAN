pragma solidity ^0.4.24;

library Call {
    function params0(address c, bytes _method) public view returns (uint answer) {
        // https://medium.com/@blockchain101/calling-the-function-of-another-contract-in-solidity-f9edfa921f4c
        //    dc = c;
        bytes4 sig = bytes4(keccak256(_method));
        assembly {
        // move pointer to free memory spot
            let ptr := mload(0x40)
        // put function sig at memory spot
            mstore(ptr,sig)

            let result := call(  // use WARNING because this should be staticcall BUT geth crash!
            15000, // gas limit
            c, // sload(dc_slot),  // to addr. append var to _slot to access storage variable
            0, // not transfer any ether (comment if using staticcall)
            ptr, // Inputs are stored at location ptr
            0x04, // Inputs are 0 bytes long
            ptr,  //Store output over input
            0x20) //Outputs are 1 bytes long

            if eq(result, 0) {
                revert(0, 0)
            }

            answer := mload(ptr) // Assign output to answer var
            mstore(0x40,add(ptr,0x24)) // Set storage pointer to new space
        }
    }

    function params1(address c, bytes _method, uint _val) public view returns (uint answer) {
        // https://medium.com/@blockchain101/calling-the-function-of-another-contract-in-solidity-f9edfa921f4c
        //    dc = c;
        bytes4 sig = bytes4(keccak256(_method));
        assembly {
        // move pointer to free memory spot
            let ptr := mload(0x40)
        // put function sig at memory spot
            mstore(ptr,sig)
        // append argument after function sig
            mstore(add(ptr,0x04), _val)

            let result := call(  // use WARNING because this should be staticcall BUT geth crash!
            15000, // gas limit
            c, // sload(dc_slot),  // to addr. append var to _slot to access storage variable
            0, // not transfer any ether (comment if using staticcall)
            ptr, // Inputs are stored at location ptr
            0x24, // Inputs are 0 bytes long
            ptr,  //Store output over input
            0x20) //Outputs are 1 bytes long

            if eq(result, 0) {
                revert(0, 0)
            }

            answer := mload(ptr) // Assign output to answer var
            mstore(0x40,add(ptr,0x24)) // Set storage pointer to new space
        }
    }

    function params2(address c, bytes _method, uint _val1, uint _val2) public view returns (uint answer) {
        // https://medium.com/@blockchain101/calling-the-function-of-another-contract-in-solidity-f9edfa921f4c
        //    dc = c;
        bytes4 sig = bytes4(keccak256(_method));
        assembly {
        // move pointer to free memory spot
            let ptr := mload(0x40)
        // put function sig at memory spot
            mstore(ptr,sig)
        // append argument after function sig
            mstore(add(ptr,0x04), _val1)
            mstore(add(ptr,0x24), _val2)

            let result := call(  // use WARNING because this should be staticcall BUT geth crash!
            15000, // gas limit
            c, // sload(dc_slot),  // to addr. append var to _slot to access storage variable
            0, // not transfer any ether (comment if using staticcall)
            ptr, // Inputs are stored at location ptr
            0x44, // Inputs are 4 bytes for signature and 2 uint256
            ptr,  //Store output over input
            0x20) //Outputs are 1 uint long

        // TODO cause revert
        //            if eq(result, 0) {
        //                revert(0, 0)
        //            }

            answer := mload(ptr) // Assign output to answer var
            mstore(0x40,add(ptr,0x20)) // Set storage pointer to new space
        }
    }

    function loadAddress(bytes sig, uint idx) public pure returns (address) {
        address influencer;
        idx += 20;
        assembly
        {
            influencer := mload(add(sig, idx))
        }
        return influencer;
    }

    function loadUint8(bytes sig, uint idx) public pure returns (uint8) {
        uint8 weight;
        idx += 1;
        assembly
        {
            weight := mload(add(sig, idx))
        }
        return weight;
    }


    function recoverHash(bytes32 hash, bytes sig, uint idx) public pure returns (address) {
        // same as recoverHash in utils/sign.js
        // The signature format is a compact form of:
        //   {bytes32 r}{bytes32 s}{uint8 v}
        // Compact means, uint8 is not padded to 32 bytes.
        require (sig.length >= 65+idx, 'bad signature length');
        idx += 32;
        bytes32 r;
        assembly
        {
            r := mload(add(sig, idx))
        }

        idx += 32;
        bytes32 s;
        assembly
        {
            s := mload(add(sig, idx))
        }

        idx += 1;
        uint8 v;
        assembly
        {
            v := mload(add(sig, idx))
        }
        if (v >= 32) { // handle case when signature was made with ethereum web3.eth.sign or getSign which is for signing ethereum transactions
            v -= 32;
            bytes memory prefix = "\x19Ethereum Signed Message:\n32"; // 32 is the number of bytes in the following hash
            hash = keccak256(abi.encodePacked(prefix, hash));
        }
        if (v <= 1) v += 27;
        require(v==27 || v==28,'bad sig v');
        return ecrecover(hash, v, r, s);

    }

    function recoverSigMemory(bytes sig) private pure returns (address[], address[], uint8[], uint[], uint) {
        uint8 version = loadUint8(sig, 0);
        uint msg_len = (version == 1) ? 1+65+20 : 1+20+20;
        uint n_influencers = (sig.length-21) / (65+msg_len);
        uint8[] memory weights = new uint8[](n_influencers);
        address[] memory keys = new address[](n_influencers);
        if ((sig.length-21) % (65+msg_len) > 0) {
            n_influencers++;
        }
        address[] memory influencers = new address[](n_influencers);
        uint[] memory offsets = new uint[](n_influencers);

        return (influencers, keys, weights, offsets, msg_len);
    }

    function recoverSigParts(bytes sig, address last_address) private pure returns (address[], address[], uint8[], uint[]) {
        // sig structure:
        // 1 byte version 0 or 1
        // 20 bytes are the address of the contractor or the influencer who created sig.
        //  this is the "anchor" of the link
        //  It must have a public key aleady stored for it in public_link_key
        // Begining of a loop on steps in the link:
        // * 65 bytes are step-signature using the secret from previous step
        // * message of the step that is going to be hashed and used to compute the above step-signature.
        //   message length depend on version 41 (version 0) or 86 (version 1):
        //   * 1 byte cut (percentage) each influencer takes from the bounty. the cut is stored in influencer2cut or weight for voting
        //   * 20 bytes address of influencer (version 0) or 65 bytes of signature of cut using the influencer address to sign
        //   * 20 bytes public key of the last secret
        // In the last step the message can be optional. If it is missing the message used is the address of the sender
        uint idx = 0;
        uint msg_len;
        uint8[] memory weights;
        address[] memory keys;
        address[] memory influencers;
        uint[] memory offsets;
        (influencers, keys, weights, offsets, msg_len) = recoverSigMemory(sig);
        idx += 1;  // skip version

        idx += 20; // skip old_address which should be read by the caller in order to get old_key
        uint count_influencers = 0;

        while (idx + 65 <= sig.length) {
            offsets[count_influencers] = idx;
            idx += 65;  // idx was increased by 65 for the signature at the begining which we will process later

            if (idx + msg_len <= sig.length) {  // its  a < and not a <= because we dont want this to be the final iteration for the converter
                weights[count_influencers] = loadUint8(sig, idx);
                require(weights[count_influencers] > 0,'weight not defined (1..255)');  // 255 are used to indicate default (equal part) behaviour
                idx++;


                if (msg_len == 41)  // 1+20+20 version 0
                {
                    influencers[count_influencers] = loadAddress(sig, idx);
                    idx += 20;
                    keys[count_influencers] = loadAddress(sig, idx);
                    idx += 20;
                } else if (msg_len == 86)  // 1+65+20 version 1
                {
                    keys[count_influencers] = loadAddress(sig, idx+65);
                    influencers[count_influencers] = recoverHash(
                        keccak256(
                            abi.encodePacked(
                                keccak256(abi.encodePacked("bytes binding to weight","bytes binding to public")),
                                keccak256(abi.encodePacked(weights[count_influencers],keys[count_influencers]))
                            )
                        ),sig,idx);
                    idx += 65;
                    idx += 20;
                }

            } else {
                // handle short signatures generated with free_take
                influencers[count_influencers] = last_address;
            }
            count_influencers++;
        }
        require(idx == sig.length,'illegal message size');

        return (influencers, keys, weights, offsets);
    }

    function recoverSig(bytes sig, address old_key, address last_address) public pure returns (address[], address[], uint8[]) {
        // validate sig AND
        // recover the information from the signature: influencers, public_link_keys, weights/cuts
        // influencers may have one more address than the keys and weights arrays
        //
        require(old_key != address(0),'no public link key');

        address[] memory influencers;
        address[] memory keys;
        uint8[] memory weights;
        uint[] memory offsets;
        (influencers, keys, weights, offsets) = recoverSigParts(sig, last_address);

        // check if we received a valid signature
        for(uint i = 0; i < influencers.length; i++) {
            if (i < weights.length) {
                require (recoverHash(keccak256(abi.encodePacked(weights[i], keys[i], influencers[i])),sig,offsets[i]) == old_key, 'illegal signature');
                old_key = keys[i];
            } else {
                // signed message for the last step is the address of the converter
                require (recoverHash(keccak256(abi.encodePacked(influencers[i])),sig,offsets[i]) == old_key, 'illegal last signature');
            }
        }

        return (influencers, keys, weights);
    }
}
