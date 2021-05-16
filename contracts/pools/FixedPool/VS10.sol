// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./VFixedPoolBase.sol";

contract VS10Pool is VFixedPoolBase {
    string public constant NAME = "VS10 Fixed Rate Pool";

    constructor(address _controller) public VFixedPoolBase(_controller, 800, "VS10 PoolShare Token", "VS10") {}
}
