// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestToken is ERC20 {
    constructor(address[] memory mintTo) ERC20("MyToken", "MTK") {
        for (uint i; i < mintTo.length; i++) {
            mint(mintTo[i], 100000 * 10 ** decimals());
        }
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
