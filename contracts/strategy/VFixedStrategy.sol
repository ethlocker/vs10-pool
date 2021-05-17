// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../Pausable.sol";
import "./VCurveBase.sol";
import "../interfaces/vesper/IController.sol";
import "../interfaces/vesper/IVFixedPool.sol";
import "../interfaces/address-list/IAddressListExt.sol";
import "../interfaces/address-list/IAddressListFactory.sol";
import "hardhat/console.sol";

contract VFixedStrategy is VCurveBase, Pausable {
    uint256 public lastRebalanceBlock;
    IController public immutable controller;
    address public immutable vvsp;
    IAddressListExt public immutable keepers;

    address public pool;

    string public constant NAME = "Strategy-FixedPool";
    string public constant VERSION = "2.0.2";

    uint256 public min = 9000; //min deposit percent to meet daily withdrawals, means rebalance will deposit only 90% of the balance of this conctract
    uint256 public max = 10000;

    address public univ2Router2 = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    ICurvea3Gauge public gauge = ICurvea3Gauge(0xd662908ADA2Ea1916B3318327A97eB18aD588b5d); //a3crv farming contract

    ICurvea3Pool public a3pool = ICurvea3Pool(0xDeBF20617708857ebe4F679508E7b7863a8A8EeE); //a3 pool

    ICurveMintr public mintr = ICurveMintr(0xd061D61a4d941c39E5453435B6345Dc261C2fcE0); //reward mint contract

    // for apy calculation
    struct LastState {
        uint256 apy;
        uint256 period;
        uint256 lastTimestamp;
        uint256 initialSupply;
        uint256 currentSupply;
    }

    constructor(
        address _controller,
        address _pool,
        address _vvsp
    ) public {
        vvsp = _vvsp;
        controller = IController(_controller);
        pool = _pool;

        IAddressListFactory factory = IAddressListFactory(0xD57b41649f822C51a73C44Ba0B3da4A880aF0029);
        IAddressListExt _keepers = IAddressListExt(factory.createList());
        _keepers.grantRole(keccak256("LIST_ADMIN"), _controller);
        keepers = _keepers;
    }

    modifier onlyKeeper() {
        require(keepers.contains(_msgSender()), "caller-is-not-keeper");
        _;
    }

    modifier onlyController() {
        require(_msgSender() == address(controller), "Caller is not the controller");
        _;
    }

    function pause() external onlyController {
        _pause();
    }

    function unpause() external onlyController {
        _unpause();
    }

    function withdrawFromPool(uint256[3] memory amounts) internal {
        IERC20(DAI).safeTransferFrom(pool, address(this), amounts[0]);
        IERC20(USDC).safeTransferFrom(pool, address(this), amounts[1]);
        IERC20(USDT).safeTransferFrom(pool, address(this), amounts[2]);
    }

    function _addLiquidity(uint256[3] memory amounts) internal {
        IERC20(DAI).safeApprove(address(a3pool), 0);
        IERC20(DAI).safeApprove(address(a3pool), amounts[0]);

        IERC20(USDC).safeApprove(address(a3pool), 0);
        IERC20(USDC).safeApprove(address(a3pool), amounts[1]);

        IERC20(USDT).safeApprove(address(a3pool), 0);
        IERC20(USDT).safeApprove(address(a3pool), amounts[2]);
        a3pool.add_liquidity(amounts, 0, true); //use underlying true
    }

    function rebalance() external whenNotPaused {
        //only pool can call
        require(block.number - lastRebalanceBlock >= controller.rebalanceFriction(address(vvsp)), "Can not rebalance");

        lastRebalanceBlock = block.number;

        ICurveMintr(mintr).mint(address(gauge));
        uint256 _crv = IERC20(crv).balanceOf(address(this));
        console.log("   [rebalance] _crv => ", _crv);
        if (_crv > 0) {
            (address to, ) = IVFixedPool(pool).getMinimumToken();
            _swapUniswap(crv, to, _crv);
            uint256 _balance = IERC20(to).balanceOf(address(this));
            console.log("   [rebalance] _balance => ", _balance);
            IERC20(to).safeTransfer(pool, _balance);
        }

        uint256[3] memory liquidity;
        liquidity[0] = IERC20(DAI).balanceOf(pool).mul(min).div(max);
        liquidity[1] = IERC20(USDC).balanceOf(pool).mul(min).div(max);
        liquidity[2] = IERC20(USDT).balanceOf(pool).mul(min).div(max);

        withdrawFromPool(liquidity);
        console.log("   [rebalance] liquidity => %s, %s, %s", liquidity[0], liquidity[1], liquidity[2]);

        liquidity[0] = IERC20(DAI).balanceOf(address(this));
        liquidity[1] = IERC20(USDC).balanceOf(address(this));
        liquidity[2] = IERC20(USDT).balanceOf(address(this));

        _addLiquidity(liquidity);

        uint256 _a3crv = IERC20(a3crv).balanceOf(address(this));
        console.log("   [rebalance] a3crv token balance => ", _a3crv);

        if (_a3crv > 0) {
            IERC20(a3crv).safeApprove(address(gauge), 0);
            IERC20(a3crv).safeApprove(address(gauge), _a3crv);
            gauge.deposit(_a3crv);
        }

        // withdraw vvsp
        uint256 initialSupply = IVFixedPool(pool).totalSupply();
        console.log("   [rebalance] pool totalsupply => ", initialSupply);
        uint256 currentSupply = getCurrentSupplyUSD();
        console.log("   [rebalance] currentSupplyUSD => ", currentSupply);
        if (currentSupply >= initialSupply) {
            uint256 rewards = currentSupply.sub(initialSupply);
            console.log("   [rebalance] rewards => ", rewards);
            uint256 exceedRewards = IVFixedPool(pool).getExceedRewards();
            console.log("   [rebalance] exceedRewards => ", exceedRewards);
            if (rewards >= exceedRewards) {
                _withdraw(vvsp, rewards.sub(exceedRewards), true);
            }
        }
    }

    function _getLatestPrice(address _token) internal view returns (uint256) {
        return IVFixedPool(pool).getLatestPrice(_token);
    }

    function withdraw(address token, uint256 amount) external returns (uint256) {
        //from pool only
        return _withdraw(pool, token, amount);
    }

    function _withdraw(
        address recipient,
        uint256 amount,
        bool isUSD
    ) internal returns (uint256) {
        console.log("   [strategy Withdraw] amount => ", amount);
        (address token, int128 index) = getMaximumToken();
        console.log("   [strategy Withdraw] token => ", token);
        uint256 outputAmount;
        if (isUSD) outputAmount = convertFrom18(token, amount.mul(10**8).div(_getLatestPrice(token)));
        else outputAmount = amount;
        console.log("   [strategy Withdraw] outputAmount => ", outputAmount);
        uint256[3] memory _amounts;
        _amounts[0] = 0;
        _amounts[1] = 0;
        _amounts[2] = 0;
        _amounts[uint256(index)] = outputAmount;

        uint256 lpAmount = a3pool.calc_token_amount(_amounts, false);
        console.log("   [strategy Withdraw] lpAmount => ", lpAmount);
        uint256 lpForWithdraw = lpAmount.mul(110).div(100); //because of calculation accuracy
        if (totalStakedOfPool() >= lpForWithdraw) gauge.withdraw(lpForWithdraw);
        else gauge.withdraw(totalStakedOfPool());

        uint256 _a3crv = IERC20(a3crv).balanceOf(address(this));
        console.log("   [strategy Withdraw] a3crv token balance after gauge withdraw=> ", _a3crv);

        a3pool.remove_liquidity_one_coin(lpForWithdraw, index, 0, true);
        console.log("   [strategy Withdraw] gauge remaining amount => ", totalStakedOfPool());

        uint256 _tokenBalanceAfter = IERC20(token).balanceOf(address(this));
        console.log("   [strategy Withdraw] _tokenBalanceAfter => ", _tokenBalanceAfter);
        uint256 afterUSDAmount = _tokenBalanceAfter.mul(_getLatestPrice(token)).div(10**8);
        console.log("   [strategy Withdraw] afterUSDAmount => ", afterUSDAmount);
        uint256 _dustBalance = IERC20(a3crv).balanceOf(address(this));
        if (_dustBalance > 0) {
            IERC20(a3crv).safeApprove(address(gauge), 0);
            IERC20(a3crv).safeApprove(address(gauge), _dustBalance);
            gauge.deposit(_dustBalance);
        }

        require(_tokenBalanceAfter >= outputAmount, "[a3pool Withdraw] - insufficient token amount");

        IERC20(token).safeTransfer(recipient, outputAmount);

        _tokenBalanceAfter = IERC20(token).balanceOf(address(this));
        if (_tokenBalanceAfter > 0) {
            console.log("   [strategy Withdraw] dust after withdraw => ", _tokenBalanceAfter);
            IERC20(token).safeTransfer(pool, _tokenBalanceAfter);
        }
        return outputAmount;
    }

    function _withdraw(
        address recipient,
        address token,
        uint256 amount
    ) internal returns (uint256) {
        console.log("   [strategy Withdraw] amount => ", amount);
        console.log("   [strategy Withdraw] token => ", token);
        int128 index = getTokenIndex(token);
        console.log("   [strategy Withdraw] index => ", uint256(index));
        uint256[3] memory _amounts;
        _amounts[0] = 0;
        _amounts[1] = 0;
        _amounts[2] = 0;
        _amounts[uint256(index)] = amount;

        uint256 lpAmount = a3pool.calc_token_amount(_amounts, false);
        console.log("   [strategy Withdraw] lpAmount => ", lpAmount);

        uint256 lpForWithdraw = lpAmount.mul(110).div(100); //because of calculation accuracy
        console.log("   [strategy Withdraw] totalStaked to gauge => ", totalStakedOfPool());
        console.log("   [strategy Withdraw] lpForWithdraw => ", lpForWithdraw);
        if (totalStakedOfPool() >= lpForWithdraw) gauge.withdraw(lpForWithdraw);
        else gauge.withdraw(totalStakedOfPool());
        gauge.withdraw(lpForWithdraw);

        uint256 _a3crv = IERC20(a3crv).balanceOf(address(this));
        console.log("   [strategy Withdraw] a3crv token balance after gauge withdraw=> ", _a3crv);

        a3pool.remove_liquidity_one_coin(lpForWithdraw, index, 0, true);
        console.log("   [strategy Withdraw] gauge remaining amount => ", totalStakedOfPool());

        uint256 _tokenBalanceAfter = IERC20(token).balanceOf(address(this));
        console.log("   [strategy Withdraw] _tokenBalanceAfter => ", _tokenBalanceAfter);
        uint256 afterUSDAmount = _tokenBalanceAfter.mul(_getLatestPrice(token)).div(10**8);
        console.log("   [strategy Withdraw] afterUSDAmount => ", afterUSDAmount);
        uint256 _dustBalance = IERC20(a3crv).balanceOf(address(this));
        if (_dustBalance > 0) {
            console.log("   [strategy Withdraw] a3crv dust => ", _dustBalance);
            IERC20(a3crv).safeApprove(address(gauge), 0);
            IERC20(a3crv).safeApprove(address(gauge), _dustBalance);
            gauge.deposit(_dustBalance);
        }
        require(_tokenBalanceAfter >= amount, "[a3pool Withdraw] - insufficient token amount");
        IERC20(token).safeTransfer(recipient, amount);
        //dust transfer
        _tokenBalanceAfter = IERC20(token).balanceOf(address(this));
        if (_tokenBalanceAfter > 0) {
            console.log("   [strategy Withdraw] dust after withdraw => ", _tokenBalanceAfter);
            IERC20(token).safeTransfer(pool, _tokenBalanceAfter);
        }
        return amount;
    }

    function getMaximumToken() public view returns (address, int128) {
        uint256[] memory balances = new uint256[](3);
        balances[0] = a3pool.balances(0); // DAI
        balances[1] = a3pool.balances(1).mul(10**12); // USDC
        balances[2] = a3pool.balances(2).mul(10**12); // USDT

        if (balances[0] > balances[1] && balances[0] > balances[2]) {
            return (DAI, 0);
        }

        if (balances[1] > balances[0] && balances[1] > balances[2]) {
            return (USDC, 1);
        }

        if (balances[2] > balances[0] && balances[2] > balances[1]) {
            return (USDT, 2);
        }

        return (DAI, 0);
    }

    function getStrategyBalance() public view returns (uint256) {
        uint256 _lpSupply = IERC20(a3crv).totalSupply();
        console.log("   [strategy getStrategyBalance] a3crv Supply => ", _lpSupply);
        uint256 _balance = totalStakedOfPool();
        console.log("   [strategy getStrategyBalance] a3crv balance => ", _balance);
        uint256 _daiBalanceUSD = a3pool.balances(0).mul(_getLatestPrice(DAI)).mul(_balance).div(_lpSupply).div(10**8);
        console.log("   [strategy getStrategyBalance] _daiBalanceUSD => ", _daiBalanceUSD);
        uint256 _usdcBalanceUSD =
            a3pool.balances(1).mul(10**12).mul(_getLatestPrice(USDC)).mul(_balance).div(_lpSupply).div(10**8);
        console.log("   [strategy getStrategyBalance] _usdcBalanceUSD => ", _usdcBalanceUSD);
        uint256 _usdtBalanceUSD =
            a3pool.balances(2).mul(10**12).mul(_getLatestPrice(USDT)).mul(_balance).div(_lpSupply).div(10**8);
        console.log("   [strategy getStrategyBalance] _usdtBalanceUSD => ", _usdtBalanceUSD);
        return _daiBalanceUSD.add(_usdcBalanceUSD).add(_usdtBalanceUSD);
    }

    function getStrategyRewards() public returns (uint256) {
        uint256 amount = getRewardClaimable();
        return amount.mul(uint256(IVFixedPool(pool).getLatestPrice(crv))).div(10**8);
    }

    function getCurrentSupplyUSD() public returns (uint256) {
        return getStrategyRewards().add(IVFixedPool(pool).totalBalanceUSDOfPool().add(getStrategyBalance()));
    }

    function _swapUniswap(
        address _from,
        address _to,
        uint256 _amount
    ) internal {
        require(_to != address(0));

        address[] memory path;

        if (_from == weth || _to == weth) {
            path = new address[](2);
            path[0] = _from;
            path[1] = _to;
        } else {
            path = new address[](3);
            path[0] = _from;
            path[1] = weth;
            path[2] = _to;
        }

        IERC20(path[0]).safeApprove(univ2Router2, 0);
        IERC20(path[0]).safeApprove(univ2Router2, _amount);

        IUniswapV2Router02(univ2Router2).swapExactTokensForTokens(_amount, 0, path, address(this), now.add(60));
    }

    function totalStakedOfPool() public view returns (uint256) {
        return gauge.balanceOf(address(this));
    }

    function getRewardClaimable() public returns (uint256) {
        return gauge.claimable_tokens(address(this));
    }
}
