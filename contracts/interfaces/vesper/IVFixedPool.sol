// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IVFixedPool {
    function totalSupply() external view returns (uint256);

    function getExceedRewards() external returns (uint256);

    function getLatestPrice(address token) external view returns (uint256);

    function totalBalanceUSDOfPool() external view returns (uint256);

    function totalBalanceOfPool() external view returns (uint256);

    function approveToken() external;

    function deposit(address, uint256) external;

    function rebalance() external;

    function resetApproval() external;

    function getUserInterestEarned(address) external view returns (uint256);

    function getPoolInterestEarned() external view returns (uint256);

    function withdraw(uint256) external;

    function setTimeLock(uint256) external;

    function getMinimumToken() external view returns (address, int128);
}
