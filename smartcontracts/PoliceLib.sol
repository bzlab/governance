pragma solidity >=0.5.0 <0.7.0;

library PoliceLib {
    enum DecisionType{ YES, NO, ABSTAIN}
    enum ActorType{ FOUNDER, INITIAL_DEVELOPER, DEVELOPER, MINER, USER, EXCHANGE_OWNER, EXCHANGE_USER, OTHER}
    enum ProposalStatus{ ACTIVE, REJECTED, WITHDRAWN, ACCEPTED}
    
   /**
    * toEthSignedMessageHash
    * @dev prefix a bytes32 value with "\x19Ethereum Signed Message:"
    * and hash the result
    */
  function toEthSignedMessageHash(bytes32 hash)
    internal
    pure
    returns (bytes32)
  {
    return keccak256(
      abi.encodePacked("\x19Ethereum Signed Message:\n32", hash)
    );
  }
  
  
  /**
   * @dev Recover signer address from a message by using their signature
   * @param hash bytes32 message, the hash is the signed message. What is recovered is the signer address.
   * @param signature bytes signature, the signature is generated using web3.eth.sign()
   */
    function verify(address p, bytes32 hash, bytes memory signature)
        public
        pure
        returns (bool)
      {
        bytes32 r;
        bytes32 s;
        uint8 v;
    
        // Check the signature length
        if (signature.length != 65) {
            return false;
        }
    
        // Divide the signature in r, s and v variables with inline assembly.
        assembly {
            //r := mload(add(signature, 0x20))   //load 32 bytes starting from 
            //s := mload(add(signature, 0x40))
            //v := byte(0, mload(add(signature, 0x60)))
            r := mload(add(signature, 0x21))   //load 32 bytes starting from 
            s := mload(add(signature, 0x41))
            v := byte(0, mload(add(signature, 0x20)))
        }
    
        // Version of signature should be 27 or 28, but 0 and 1 are also possible versions
        if (v < 27) {
          v += 27;
        }
    
        // If the version is correct return the signer address
        if (v != 27 && v != 28) {
            return false;
        } else {
          // solium-disable-next-line arg-overflow
          //address adr = ecrecover(hash, v, r, s);
          return (ecrecover(hash, v, r, s) == p);
        }
    }

    
    //Disclaimer. This following functions are retrieved from https://github.com/GNSPS/solidity-bytes-utils/blob/master/contracts/BytesLib.sol
    function slice(bytes memory _bytes, uint256 _start, uint256 _length) internal pure returns (bytes memory)
    {
        require(_length + 31 >= _length, "slice_overflow");
        require(_start + _length >= _start, "slice_overflow");
        require(_bytes.length >= _start + _length, "slice_outOfBounds");

        bytes memory tempBytes;

        assembly {
            switch iszero(_length)
            case 0 {
                // Get a location of some free memory and store it in tempBytes as
                // Solidity does for memory variables.
                tempBytes := mload(0x40)

                // The first word of the slice result is potentially a partial
                // word read from the original array. To read it, we calculate
                // the length of that partial word and start copying that many
                // bytes into the array. The first word we copy will start with
                // data we don't care about, but the last `lengthmod` bytes will
                // land at the beginning of the contents of the new array. When
                // we're done copying, we overwrite the full first word with
                // the actual length of the slice.
                let lengthmod := and(_length, 31)

                // The multiplication in the next line is necessary
                // because when slicing multiples of 32 bytes (lengthmod == 0)
                // the following copy loop was copying the origin's length
                // and then ending prematurely not copying everything it should.
                let mc := add(add(tempBytes, lengthmod), mul(0x20, iszero(lengthmod)))
                let end := add(mc, _length)

                for {
                    // The multiplication in the next line has the same exact purpose
                    // as the one above.
                    let cc := add(add(add(_bytes, lengthmod), mul(0x20, iszero(lengthmod))), _start)
                } lt(mc, end) {
                    mc := add(mc, 0x20)
                    cc := add(cc, 0x20)
                } {
                    mstore(mc, mload(cc))
                }

                mstore(tempBytes, _length)

                //update free-memory pointer
                //allocating the array padded to 32 bytes like the compiler does now
                mstore(0x40, and(add(mc, 31), not(31)))
            }
            //if we want a zero-length slice let's just return a zero-length array
            default {
                tempBytes := mload(0x40)

                mstore(0x40, add(tempBytes, 0x20))
            }
        }

        return tempBytes;
    }
    
    function toBytes32(bytes memory _bytes, uint256 _start) internal pure returns (bytes32) {
        require(_start + 32 >= _start, "toBytes32_overflow");
        require(_bytes.length >= _start + 32, "toBytes32_outOfBounds");
        bytes32 tempBytes32;

        assembly {
            tempBytes32 := mload(add(add(_bytes, 0x20), _start))
        }

        return tempBytes32;
    }
    
    function toUint32(bytes memory _bytes, uint256 _start) internal pure returns (uint32) {
        require(_start + 4 >= _start, "toUint32_overflow");
        require(_bytes.length >= _start + 4, "toUint32_outOfBounds");
        uint32 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x4), _start))
        }

        return tempUint;
    }
    
    function toUint8(bytes memory _bytes, uint256 _start) internal pure returns (uint8) {
        require(_start + 1 >= _start, "toUint8_overflow");
        require(_bytes.length >= _start + 1 , "toUint8_outOfBounds");
        uint8 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x1), _start))
        }

        return tempUint;
    }
    
    function concatenateArrays(address[] memory Accounts, address[] memory Accounts2) public pure returns(address[] memory) {
        address[] memory returnArr = new address[](Accounts.length + Accounts2.length);
    
        uint i=0;
        for (; i < Accounts.length; i++) {
            returnArr[i] = Accounts[i];
        }
    
        uint j=0;
        while (j < Accounts.length) {
            returnArr[i++] = Accounts2[j++];
        }
    
        return returnArr;
    } 

    function compareStr(string memory str1, string memory str2) public pure returns(bool) {
        if(bytes(str1).length != bytes(str2).length) {
            return false;
        } else {
            return keccak256(bytes(str1)) == keccak256(bytes(str2));
        }
    }
}
