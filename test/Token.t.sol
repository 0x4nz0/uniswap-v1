// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Token.sol";

contract TokenTest is Test {
    Token public token;

    function setUp() public {
        token = new Token("Test Token", "TKN", 31337);
    }

    function testDeploymentInvariants() public {
        assertEq(token.name(), "Test Token");
        assertEq(token.symbol(), "TKN");
        assertEq(token.totalSupply(), 31337);
        assertEq(token.balanceOf(address(this)), 31337);
    }
}
