// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Token.sol";
import "../src/Factory.sol";
import "../src/Exchange.sol";

contract FactoryTest is Test {
    Token public token;
    Factory public factory;

    function setUp() public {
        token = new Token("Test Token", "TKN", 31337);
        factory = new Factory();
    }

    function testCreateExchange() public {
        address exchangeAddress = factory.createExchange(address(token));
        assertEq(factory.getExchange(address(token)), exchangeAddress);

        Exchange exchange = Exchange(exchangeAddress);
        assertEq(exchange.name(), "Uniswap-V1");
        assertEq(exchange.symbol(), "UNI-V1");
        assertEq(exchange.factoryAddress(), address(factory));
    }

    function testCannotCreateExchangeIfExchangeAlreadyExists() public {
        factory.createExchange(address(token));

        vm.expectRevert(bytes("exchange already exists"));
        factory.createExchange(address(token));
    }
}
