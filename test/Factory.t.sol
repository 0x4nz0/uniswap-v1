// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Token.sol";
import "../src/Factory.sol";

contract FactoryTest is Test {
    Token public token;
    Factory public factory;

    function setUp() public {
        token = new Token("Test Token", "TKN", 31337);
        factory = new Factory();
    }
}
