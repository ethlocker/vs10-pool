// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IVFixedStrategy {
    function withdraw(address token, uint256 amount) external returns (uint256);

    function rebalance() external;

    function getCurrentSupplyUSD() external returns (uint256);
}
