// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract Bitmap {
    bool[8] implementationWithBool;
    uint8 implementationWithBitmap;

    function setDataWithBoolArray(bool[8] memory data) external {
        implementationWithBool = data;
    }

    function setDataWithBitmap(uint8 data) external {
        implementationWithBitmap = data;
    }

    function readWithBoolArray(uint8 index) external returns (bool) {
        return implementationWithBool[index];
    }

    function readWithBitmap(uint indexFromRight) external returns (bool) {
        uint256 bitAtIndex = implementationWithBitmap & (1 << indexFromRight);
        return bitAtIndex > 0;
    }

    function readWithBitmapFromLeft(
        uint indexFromLeft
    ) external returns (bool) {
        uint256 bitAtIndex = implementationWithBitmap &
            (1 << (8 - 1 - indexFromLeft));
        return bitAtIndex > 0;
    }
}
