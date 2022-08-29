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
        assertEq(exchange.name(), "Uniswap-V1");
        assertEq(exchange.symbol(), "UNI-V1");
        assertEq(exchange.totalSupply(), 0);
    }

    function testAddLiquidity() public {
        token.approve(address(exchange), 200 wei);
        exchange.addLiquidity{value: 100 wei}(200 wei);

        assertEq(address(exchange).balance, 100 wei);
        assertEq(exchange.getReserve(), 200 wei);
    }

    function testMintLPTokensWithEmptyReserves() public {
        token.approve(address(exchange), 200 wei);
        exchange.addLiquidity{value: 100 wei}(200 wei);

        assertEq(exchange.balanceOf(address(this)), 100 wei);
        assertEq(exchange.totalSupply(), 100 wei);
    }

    function testMintLPTokensWithExistingReserves() public {
        token.approve(address(exchange), 300 wei);
        // addLiquidity with empty reserves
        uint256 liquidity = exchange.addLiquidity{value: 100 wei}(200 wei);
        assertEq(liquidity, 100 wei);

        // addLiquidity with existing reserves
        // liquidity = (100 * 50) / 100 = 50
        liquidity = exchange.addLiquidity{value: 50 wei}(200 wei);
        assertEq(liquidity, 50);

        // ethReserve = 150 - 50 = 100
        // tokenReserve = 200
        // tokenAmount = (50 * 200) / 100 = 100
        // reserve = 200 + 100 = 300
        assertEq(exchange.getReserve(), 300 wei);

        // totalSupply = 100 + 50 = 150
        assertEq(exchange.balanceOf(address(this)), 150 wei);
        assertEq(exchange.totalSupply(), 150 wei);
    }

    function testGetTokenAmount() public {
        token.approve(address(exchange), 2000 wei);
        exchange.addLiquidity{value: 1000 wei}(2000 wei);

        uint256 tokensOut = exchange.getTokenAmount(1 wei);
        assertEq(tokensOut, 1998); // ((1 * 2000) * 1000) / (1 + 1000)

        tokensOut = exchange.getTokenAmount(100 wei);
        assertEq(tokensOut, 181818); // ((100 * 2000) * 1000) / (100 + 1000)

        tokensOut = exchange.getTokenAmount(1000 wei);
        assertEq(tokensOut, 1000000); // ((1000 * 2000) * 1000) / (1000 + 1000)
    }

    function testGetEthAmount() public {
        token.approve(address(exchange), 2000 wei);
        exchange.addLiquidity{value: 1000 wei}(2000 wei);

        uint256 ethOut = exchange.getEthAmount(2 wei);
        assertEq(ethOut, 999); // ((2 * 1000) * 1000) / (2 + 2000)

        ethOut = exchange.getEthAmount(100 wei);
        assertEq(ethOut, 47619); // ((100 * 1000) * 1000) / (100 + 2000)

        ethOut = exchange.getEthAmount(2000 wei);
        assertEq(ethOut, 500000); // ((2000 * 1000) * 1000) / (2000 + 2000)
    }
}
