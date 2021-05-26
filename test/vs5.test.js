const hre = require("hardhat");
var chaiAsPromised = require("chai-as-promised");

const {assert} = require("chai").use(chaiAsPromised);
const {time} = require("@openzeppelin/test-helpers");
const {web3} = require("@openzeppelin/test-helpers/src/setup");
const {expect} = require("hardhat");

const Controller = hre.artifacts.require("Controller");
const VS5Pool = hre.artifacts.require("VS5Pool");
const ERC20 = hre.artifacts.require("ERC20");

const VFixedStrategy = hre.artifacts.require("VFixedStrategy");

const unlockAccount = async (address) => {
  await hre.network.provider.send("hardhat_impersonateAccount", [address]);
  return address;
};

const toWei = (amount, decimal = 18) => {
  return hre.ethers.utils.parseUnits(hre.ethers.BigNumber.from(amount).toString(), decimal);
};

const fromWei = (amount, decimal = 18) => {
  return hre.ethers.utils.formatUnits(amount, decimal);
};

describe("VS10 Fixed pool test", () => {
  let vs5Pool, controller, strategy;

  let vvsp = "0xbA4cFE5741b357FA371b506e5db0774aBFeCf8Fc";
  let whale, DAI, USDC, USDT;

  before("Deploy contracts", async () => {
    [alice, bob, john] = await web3.eth.getAccounts();
    controller = await Controller.new();
    vs5Pool = await VS5Pool.new(controller.address);
    strategy = await VFixedStrategy.new(controller.address, vs5Pool.address, vvsp);

    await web3.eth.sendTransaction({
      from: alice,
      to: "0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503",
      value: toWei(10),
    });

    whale = await unlockAccount("0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503");
    DAI = await ERC20.at("0x6b175474e89094c44da98b954eedeac495271d0f");
    USDC = await ERC20.at("0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48");
    USDT = await ERC20.at("0xdac17f958d2ee523a2206206994597c13d831ec7");

    DAI.transfer(alice, toWei(1000000), {from: whale});

    USDC.transfer(bob, toWei(1000000, 6), {from: whale});

    USDT.transfer(john, toWei(1000000, 6), {from: whale});

    await controller.addPool(vs5Pool.address);
    await controller.updateStrategy(vs5Pool.address, strategy.address);
  });

  it("get balance should work", async () => {
    let _balance = await DAI.balanceOf(alice);
    assert.equal(_balance.toString(), toWei(1000000).toString(), "dai transfer failed");

    _balance = await USDC.balanceOf(bob);
    assert.equal(_balance.toString(), toWei(1000000, 6).toString(), "bob usdc transfer failed");

    _balance = await USDT.balanceOf(john);
    assert.equal(_balance.toString(), toWei(1000000, 6).toString(), "john usdt transfer failed");
  });

  it("deposit should work", async () => {
    console.log("========= Alice DAI deposit ==============");
    await DAI.approve(vs5Pool.address, toWei(1000000), {from: alice});
    await vs5Pool.deposit(DAI.address, toWei(1000000), {from: alice});
    console.log("alice vs10 share balance => ", fromWei((await vs5Pool.balanceOf(alice)).toString()));

    console.log("========= Bob usdc deposit ==============");
    await USDC.approve(vs5Pool.address, toWei(1000000, 6), {from: bob});
    await vs5Pool.deposit(USDC.address, toWei(1000000, 6), {from: bob});
    console.log("bob vs10 share balance => ", fromWei((await vs5Pool.balanceOf(bob)).toString()));

    console.log("========= John usdt deposit ==============");
    await USDT.approve(vs5Pool.address, toWei(1000000, 6), {from: john});
    await vs5Pool.deposit(USDT.address, toWei(1000000, 6), {from: john});
    console.log("john vs10 share balance => ", fromWei((await vs5Pool.balanceOf(john)).toString()));
  });

  it("get totalbalance should work", async () => {
    console.log("========= Pool total balance ============");
    const totalBalance = await vs5Pool.totalBalanceOfPool();
    console.log("total balance => ", fromWei(totalBalance.toString()));
    expect(totalBalance.toString()).equal(toWei(3000000).toString());
  });

  it("rebalance should work", async () => {
    console.log("======= Initial rebalance ========");
    await vs5Pool.rebalance();
    console.log("======= 30 days after ========");
    await increaseTime(60 * 60 * 24 * 30);
    console.log("======= second rebalance ========");
    await vs5Pool.rebalance();
  });

  it("withdraw should work", async () => {
    await withdrawFromPool(alice, await vs5Pool.balanceOf(alice));

    console.log("======= 3 months after ========");
    await increaseTime(60 * 60 * 24 * 90);
    console.log("======= third rebalance ========");
    await vs5Pool.rebalance();
    await withdrawFromPool(bob, await vs5Pool.balanceOf(bob));

    console.log("======= 3 months after ========");
    await increaseTime(60 * 60 * 24 * 90);
    console.log("======= 4th rebalance ========");
    await vs5Pool.rebalance();
    await withdrawFromPool(john, await vs5Pool.balanceOf(john));
    console.log("");
    console.log("DAI balance of vvsp  after all withdraw => ", fromWei((await DAI.balanceOf(vvsp)).toString()));
    console.log("USDC balance of vvsp  after all withdraw => ", fromWei((await USDC.balanceOf(vvsp)).toString(), 6));
    console.log("USDT balance of vvsp  after all withdraw => ", fromWei((await USDT.balanceOf(vvsp)).toString(), 6));
  });

  const withdrawFromPool = async (from, amount) => {
    console.log("============ Withdram from %s ===============", from);
    let _balanceDAIBefore = await DAI.balanceOf(from);
    let _balanceUSDCBefore = await USDC.balanceOf(from);
    let _balanceUSDTBefore = await USDT.balanceOf(from);

    console.log("balance of DAI Before => ", fromWei(_balanceDAIBefore.toString()));
    console.log("balance of USDC Before => ", fromWei(_balanceUSDCBefore.toString(), 6));
    console.log("balance of USDT Before => ", fromWei(_balanceUSDTBefore.toString(), 6));

    await vs5Pool.withdraw(amount, {from: from});

    let _balanceDAIAfter = await DAI.balanceOf(from);
    let _balanceUSDCAfter = await USDC.balanceOf(from);
    let _balanceUSDTAfter = await USDT.balanceOf(from);
    console.log("balance of DAI after => ", fromWei(_balanceDAIAfter.toString()));
    console.log("balance of USDC after => ", fromWei(_balanceUSDCAfter.toString(), 6));
    console.log("balance of USDT after => ", fromWei(_balanceUSDTAfter.toString(), 6));
    console.log("");
  };

  const increaseTime = async (sec) => {
    await network.provider.send("evm_increaseTime", [sec]);
    await network.provider.send("evm_mine");
  };
});
