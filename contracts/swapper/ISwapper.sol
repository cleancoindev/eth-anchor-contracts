// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;

interface ISwapper {
    function swapToken(
        address _from,
        address _to,
        uint256 _amount,
        address _beneficiary
    ) external;
}