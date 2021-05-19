// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./VFixedPoolBase.sol";

contract VS5Pool is VFixedPoolBase {
    string public constant NAME = "VS5 Fixed Rate Pool";

    constructor(address _controller) public VFixedPoolBase(_controller, 500, "VS5 PoolShare Token", "VS5") {}
}
