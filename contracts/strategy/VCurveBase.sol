// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../interfaces/curve/ICurve.sol";
import "../interfaces/uniswap/IUniswapV2Router02.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "hardhat/console.sol";

abstract contract VCurveBase {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    address public constant aDAI = 0x028171bCA77440897B824Ca71D1c56caC55b68A3;
    address public constant aUSDC = 0xBcca60bB61934080951369a648Fb03DF4F96263C;
    address public constant aUSDT = 0x3Ed3B47Dd13EC9a98b44e6204A523E766B225811;
    address public constant weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address public constant crv = 0xD533a949740bb3306d119CC777fa900bA034cd52; //reward token of gauge
    address public constant a3crv = 0xFd2a8fA60Abd58Efe3EeE34dd494cD491dC14900; //lp token to the gauge pool

    uint256 public constant MAX_UINT_VALUE = uint256(-1);

    function convertFrom18(address _token, uint256 _amount) internal pure returns (uint256) {
        if (_token == DAI) return _amount;
        else if (_token == USDC) return _amount.div(10**12);
        else if (_token == USDT) return _amount.div(10**12);
        return _amount;
    }

    function convertTo18(address _token, uint256 _amount) internal pure returns (uint256) {
        if (_token == DAI) return _amount;
        else if (_token == USDC) return _amount.mul(10**12);
        else if (_token == USDT) return _amount.mul(10**12);
        return _amount;
    }

    function getTokenIndex(address token) internal pure returns (int128) {
        if (token == DAI) return 0;
        else if (token == USDC) return 1;
        else if (token == USDT) return 2;
        return 0;
    }
}
