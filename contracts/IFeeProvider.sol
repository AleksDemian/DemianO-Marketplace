// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

interface IFeeProvider {
    function platformFeeInCoin() external view returns(uint256);
    function platformFeeInToken() external view returns(uint256);
}