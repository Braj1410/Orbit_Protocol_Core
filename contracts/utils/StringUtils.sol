// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

library StringUtils {
    /**
     * @dev Returns the length of a given string
     *
     * @param s The string to measure the length of
     * @return The length of the input string
     */
    function strlen(string memory s) internal pure returns (uint) {
        uint len;
        uint i = 0;
        uint bytelength = bytes(s).length;
        for(len = 0; i < bytelength; len++) {
            bytes1 b = bytes(s)[i];
            if(b < 0x80) {
                i += 1;
            } else if (b < 0xE0) {
                i += 2;
            } else if (b < 0xF0) {
                i += 3;
            } else if (b < 0xF8) {
                i += 4;
            } else if (b < 0xFC) {
                i += 5;
            } else {
                i += 6;
            }
        }
        return len;
    }

    function toLower(string memory s) internal pure returns (string memory) {
        bytes memory bstr = bytes(s);
        bytes memory blower = new bytes(bstr.length);
        for (uint i = 0; i < bstr.length; i++) {
            if ((uint8(bstr[i]) >= 65) && (uint8(bstr[i]) <= 90)) {
                blower[i] = bytes1(uint8(bstr[i]) + 32);
            } else {
                blower[i] = bstr[i];
            }
        }
        return string(blower);
    }

    function toUpper(string memory s) internal pure returns (string memory) {
        bytes memory bstr = bytes(s);
        bytes memory bupper = new bytes(bstr.length);
        for (uint i = 0; i < bstr.length; i++) {
            if ((uint8(bstr[i]) >= 97) && (uint8(bstr[i]) <= 122)) {
                bupper[i] = bytes1(uint8(bstr[i]) - 32);
            } else {
                bupper[i] = bstr[i];
            }
        }
        return string(bupper);
    }
}
