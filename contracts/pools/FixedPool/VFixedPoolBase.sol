// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "hardhat/console.sol";

import "../../Pausable.sol";
import "../../strategy/VTokenBase.sol";
import "../../interfaces/vesper/IVFixedStrategy.sol";
import "../../interfaces/vesper/IController.sol";
import "../../interfaces/chainlink/AggregatorV3Interface.sol";

abstract contract VFixedPoolBase is VTokenBase, Context, Pausable, ReentrancyGuard, ERC20 {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    mapping(address => AggregatorV3Interface) internal priceFeed;
    uint16 public immutable APY; // 10000 = 100%
    uint16 public immutable EXCEED_APY; // 10000 = 100%
    IController public immutable controller;
    uint256 public year_time = 60 * 60 * 24 * 365;

    uint256 public timelockDuration = 7 days; //initially 7 days, but changeable

    struct UserInfo {
        uint256 interestEarned;
        uint256 lastTimestamp;
        uint256 timelock;
    }
    mapping(address => UserInfo) public userInfo;

    struct PoolInfo {
        uint256 balanceTotal;
        uint256 interestTotal;
        uint256 lastTimestamp;
    }
    PoolInfo public poolInfo;

    constructor(
        address _controller,
        uint16 _apy,
        string memory _name,
        string memory _symbol
    ) public ERC20(_name, _symbol) {
        require(_controller != address(0), "Controller address is zero");
        require(_apy > 0 && _apy < 10000, "APY is invalid");

        controller = IController(_controller);
        APY = _apy;
        EXCEED_APY = 5000;

        priceFeed[DAI] = AggregatorV3Interface(0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9); // dai/usd price oracle
        priceFeed[USDC] = AggregatorV3Interface(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6); // usdc/usd price oracle
        priceFeed[USDT] = AggregatorV3Interface(0x3E7d1eAB13ad0104d2750B8863b489D65364e32D); // usdt/usd price oracle
        priceFeed[crv] = AggregatorV3Interface(0xCd627aA160A6fA45Eb793D19Ef54f5062F20f33f); // crv/usd price oracle
    }

    function getLatestPrice(address token) public view returns (uint256) {
        (, int256 price, , , ) = priceFeed[token].latestRoundData();
        return uint256(price);
    }

    function setTimeLock(uint256 _duration) external onlyController {
        require(_duration > 0, "Duration is invaild");
        timelockDuration = _duration;
    }

    function _getRatio(uint256 _duration) internal view returns (uint256) {
        return _duration.mul(10**12).div(year_time);
    }

    function _updateInterest(address _user) internal {
        UserInfo storage user = userInfo[_user];
        address strategy = controller.strategy(address(this));
        uint256 _duration;
        uint256 _interest;
        if (_user != strategy) {
            _duration = block.timestamp.sub(user.lastTimestamp);
            console.log("   [updateInterest] _duration => ", _duration);
            console.log("   [updateInterest] balanceOfUser => ", balanceOf(_user));
            _interest = balanceOf(_user).mul(APY).mul(_getRatio(_duration)).div(10**12).div(10**4);
            console.log("   [updateInterest] user interest for period => ", _interest);
            user.interestEarned = user.interestEarned.add(_interest);
            user.lastTimestamp = block.timestamp;
        }
        _duration = block.timestamp.sub(poolInfo.lastTimestamp);
        console.log("   [updateInterest] pool _duration => ", _duration);
        console.log("   [updateInterest] poolInfo.balanceTotal => ", poolInfo.balanceTotal);
        _interest = poolInfo.balanceTotal.mul(APY).mul(_getRatio(_duration)).div(10**16);
        console.log("   [updateInterest] pool interest for period => ", _interest);
        poolInfo.interestTotal = poolInfo.interestTotal.add(_interest);
        console.log("   [updateInterest] poolInfo.interestTotal => ", poolInfo.interestTotal);
        poolInfo.lastTimestamp = block.timestamp;
    }

    function getExceedRewards() external onlyStrategy returns (uint256) {
        // only strategy
        _updateInterest(_msgSender());
        return poolInfo.interestTotal.mul(EXCEED_APY).div(APY);
    }

    function getUserInterestEarned(address user) external view returns (uint256) {
        return userInfo[user].interestEarned;
    }

    function getPoolInterestEarned() external view returns (uint256) {
        return poolInfo.interestTotal;
    }

    /**
     * @notice Deposit DAI/USDC/USDT tokens
     * @param token Deposit token.
     * @param amount ERC20 token amount.
     */
    function deposit(address token, uint256 amount) public whenNotPaused nonReentrant {
        require(token == DAI || token == USDC || token == USDT, "[Deposit] Deposit token is not allowed");
        require(!address(_msgSender()).isContract(), "[Deposit] Contract is not allowed");
        require(timelockDuration != 0, "timelock duration is not set");
        // save user amount in usd

        UserInfo storage user = userInfo[_msgSender()];
        if (user.timelock == 0) user.timelock = now + timelockDuration;

        _updateInterest(_msgSender());

        IERC20(token).safeTransferFrom(_msgSender(), address(this), amount);

        uint256 _usdAmount = convertTo18(token, amount).mul(getLatestPrice(token)).div(10**8);

        poolInfo.balanceTotal = poolInfo.balanceTotal.add(_usdAmount);
        _mint(_msgSender(), _usdAmount);
    }

    function withdraw(uint256 usdAmount) public whenNotPaused nonReentrant {
        require(!address(_msgSender()).isContract(), "[Withdraw] Contract is not allowed");
        UserInfo storage user = userInfo[_msgSender()];
        require(user.timelock > 0 && user.timelock < now, "[Withdraw] withdraw is not allowed in the lock period");

        _updateInterest(_msgSender());
        IVFixedStrategy strategy = IVFixedStrategy(controller.strategy(address(this)));

        uint256 initialSupply = totalSupply();
        // check insufficient apy
        uint256 currentSupply = strategy.getCurrentSupplyUSD();
        uint256 rewards = currentSupply.sub(initialSupply);
        console.log("   [Pool withdraw] rewards => ", rewards);
        require(rewards >= poolInfo.interestTotal, "insufficient APY");
        //end check

        uint256 userSupply = balanceOf(_msgSender());
        console.log("   [Pool withdraw] user.interestEarned => ", user.interestEarned);
        console.log("   [Pool withdraw] userSupply => ", userSupply);
        uint256 _withdrawAmount = usdAmount.mul(userSupply.add(user.interestEarned)).div(userSupply);
        console.log("   [Pool withdraw] _withdrawAmount => ", _withdrawAmount);

        (address _token, ) = getMaximumToken();
        console.log("   [Pool withdraw] maximum token => ", _token);
        uint256 _balance = IERC20(_token).balanceOf(address(this));
        console.log("   [Pool withdraw] balanceOfPool => ", _balance);
        uint256 _actualToken = convertFrom18(_token, _getTokenAmountFromUsd(_token, _withdrawAmount));
        console.log("   [Pool withdraw] _actualTokenAmount => ", _actualToken);

        _burn(_msgSender(), usdAmount);

        console.log("   [Pool withdraw] poolInfo.balanceTotal before => ", poolInfo.balanceTotal);
        poolInfo.balanceTotal = poolInfo.balanceTotal.sub(usdAmount);
        console.log("   [Pool withdraw] poolInfo.balanceTotal after => ", poolInfo.balanceTotal);

        if (_balance < _actualToken) {
            uint256 _restAmount = _actualToken.sub(_balance);
            console.log("   [Pool withdraw] _restAmount => ", _restAmount);
            uint256 withdrawnAmount = strategy.withdraw(_token, _restAmount);
            console.log("   [Pool withdraw] withdrawnAmount => ", withdrawnAmount);
            require(_restAmount == withdrawnAmount, "strategy failed");
        }
        IERC20(_token).safeTransfer(_msgSender(), _actualToken);
    }

    function getMaximumToken() public view returns (address, int128) {
        uint256[] memory balances = new uint256[](3);
        balances[0] = IERC20(DAI).balanceOf(address(this)); // DAI
        balances[1] = IERC20(USDC).balanceOf(address(this)).mul(10**12); // USDC
        balances[2] = IERC20(USDT).balanceOf(address(this)).mul(10**12); // USDT

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

    function getMinimumToken() public view returns (address, int128) {
        uint256[] memory balances = new uint256[](3);
        balances[0] = IERC20(DAI).balanceOf(address(this)); // DAI
        balances[1] = IERC20(USDC).balanceOf(address(this)).mul(10**12); // USDC
        balances[2] = IERC20(USDT).balanceOf(address(this)).mul(10**12); // USDT

        if (balances[0] < balances[1] && balances[0] < balances[2]) {
            return (DAI, 0);
        }

        if (balances[1] < balances[0] && balances[1] < balances[2]) {
            return (USDC, 1);
        }

        if (balances[2] < balances[0] && balances[2] < balances[1]) {
            return (USDT, 2);
        }

        return (DAI, 0);
    }

    function _getTokenAmountFromUsd(address _token, uint256 _usdAmount) internal view returns (uint256) {
        return _usdAmount.mul(10**8).div(getLatestPrice(_token));
    }

    function totalBalanceOfPool() public view returns (uint256) {
        return
            IERC20(DAI).balanceOf(address(this)).add(IERC20(USDC).balanceOf(address(this)).mul(10**12)).add(
                IERC20(USDT).balanceOf(address(this)).mul(10**12)
            );
    }

    function totalBalanceUSDOfPool() public view returns (uint256) {
        uint256 _daiBalance = IERC20(DAI).balanceOf(address(this)).mul(getLatestPrice(DAI)).div(10**8);
        uint256 _usdcBalance = IERC20(USDC).balanceOf(address(this)).mul(10**12).mul(getLatestPrice(USDC)).div(10**8);
        uint256 _usdtBalance = IERC20(USDT).balanceOf(address(this)).mul(10**12).mul(getLatestPrice(USDT)).div(10**8);
        return _daiBalance.add(_usdcBalance).add(_usdtBalance);
    }

    function rebalance() external {
        IVFixedStrategy strategy = IVFixedStrategy(controller.strategy(address(this)));
        strategy.rebalance();
    }

    /// @dev Approve strategy to spend collateral token and strategy token of pool.
    function approveToken() external virtual onlyController {
        address strategy = controller.strategy(address(this));
        IERC20(DAI).safeApprove(strategy, MAX_UINT_VALUE);
        IERC20(USDC).safeApprove(strategy, MAX_UINT_VALUE);
        IERC20(USDT).safeApprove(strategy, MAX_UINT_VALUE);
    }

    /// @dev Reset token approval of strategy. Called when updating strategy.
    function resetApproval() external virtual onlyController {
        address strategy = controller.strategy(address(this));
        IERC20(DAI).safeApprove(strategy, 0);
        IERC20(USDC).safeApprove(strategy, 0);
        IERC20(USDT).safeApprove(strategy, 0);
    }

    modifier onlyStrategy() {
        require(_msgSender() == controller.strategy(address(this)), "caller is not the strategy");
        _;
    }

    modifier onlyController() {
        require(address(controller) == _msgSender(), "Caller is not the controller");
        _;
    }

    function pause() external onlyController {
        _pause();
    }

    function unpause() external onlyController {
        _unpause();
    }

    function shutdown() external onlyController {
        _shutdown();
    }

    function open() external onlyController {
        _open();
    }
}
