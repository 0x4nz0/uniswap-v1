// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Token.sol";
import "../src/Exchange.sol";

contract ExchangeTest is Test {
    Token public token;
    Exchange public exchange;

    function setUp() public {
        token = new Token("Test Token", "TKN", 31337);
        exchange = new Exchange(address(token));
    }

    function testDeploymentInvariants() public {
        assertEq(exchange.tokenAddress(), address(token));
    }

    function testAddLiquidity() public {
        token.approve(address(exchange), 200 wei);
        exchange.addLiquidity{value: 100 wei}(200 wei);

        assertEq(address(exchange).balance, 100 wei);
        assertEq(exchange.getReserve(), 200 wei);
    }

    function testPrice() public {
        token.approve(address(exchange), 2000 wei);
        exchange.addLiquidity{value: 1000 wei}(2000 wei);

        uint256 tokenReserve = exchange.getReserve();
        uint256 etherReserve = address(exchange).balance;

        // ETH per Token
        assertEq(exchange.getPrice(etherReserve, tokenReserve), 500); // (1000 * 1000) / 2000 = 500

        // Token per ETH
        assertEq(exchange.getPrice(tokenReserve, etherReserve), 2000); // (2000 * 1000) / 1000 = 20000
    }
}
