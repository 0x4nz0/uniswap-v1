// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Token.sol";
import "../src/Exchange.sol";

contract ExchangeBaseSetup is Test {
    Token internal token;
    Exchange internal exchange;

    address internal owner;
    address internal user;

    function setUp() public virtual {
        token = new Token("Test Token", "TKN", 31337);
        exchange = new Exchange(address(token));

        owner = address(this);
        vm.label(owner, "Owner");

        user = vm.addr(1);
        vm.label(user, "User");
    }
}

contract AddLiquidityWithEmptyReservesTest is ExchangeBaseSetup {
    function setUp() public virtual override {
        ExchangeBaseSetup.setUp();
    }

    function testAddLiquidity() public {
        token.approve(address(exchange), 200 wei);
        exchange.addLiquidity{value: 100 wei}(200 wei);
        assertEq(address(exchange).balance, 100 wei);
        assertEq(exchange.getReserve(), 200 wei);
    }

    function testMintLPTokens() public {
        token.approve(address(exchange), 200 wei);
        exchange.addLiquidity{value: 100 wei}(200 wei);
        assertEq(exchange.balanceOf(address(this)), 100 wei);
        assertEq(exchange.totalSupply(), 100 wei);
    }
}

contract AddLiquidityWithExistingReservesTest is ExchangeBaseSetup {
    function setUp() public virtual override {
        ExchangeBaseSetup.setUp();
        token.approve(address(exchange), 300 wei);
        exchange.addLiquidity{value: 100 wei}(200 wei);
    }

    function testPreserveExchangeRate() public {
        exchange.addLiquidity{value: 50 wei}(200 wei);

        assertEq(address(exchange).balance, 150 wei);
        assertEq(exchange.getReserve(), 300 wei);
    }

    function testMintLPTokens() public {
        // liquidity = (100 * 50) / 100 = 50
        uint256 liquidity = exchange.addLiquidity{value: 50 wei}(200 wei);
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

    function testCannotMintLPTokens() public {
        // _tokenAmount = 50
        // ethReserve = 150 - 50 = 100
        // tokenReserve = 200
        // tokenAmount = (50 * 200) / 100 = 100
        // require(50 >= 100) -> revert
        vm.expectRevert(bytes("insufficient token amount"));
        exchange.addLiquidity{value: 50 wei}(50 wei);
    }
}

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

    function testGetTokenAmount() public {
        token.approve(address(exchange), 2000 wei);
        exchange.addLiquidity{value: 1000 wei}(2000 wei);

        uint256 tokensOut = exchange.getTokenAmount(1 wei);
        assertEq(tokensOut, 1); // ((1 * 99) * 2000) / ((1000 * 100) + (1 * 99)) = 1,978041739

        tokensOut = exchange.getTokenAmount(100 wei);
        assertEq(tokensOut, 180); // ((100 * 99) * 2000) / ((1000 * 100) + (100 * 99)) = 180,163785259

        tokensOut = exchange.getTokenAmount(1000 wei);
        assertEq(tokensOut, 994); // ((1000 * 99) * 2000) / ((1000 * 100) + (1000 * 99)) = 994,974874372
    }

    function testGetEthAmount() public {
        token.approve(address(exchange), 2000 wei);
        exchange.addLiquidity{value: 1000 wei}(2000 wei);

        uint256 ethOut = exchange.getEthAmount(2 wei);
        assertEq(ethOut, 0); // ((2 * 99) * 1000) / ((2000 * 100) + (2 * 99)) = 0,989020869

        ethOut = exchange.getEthAmount(100 wei);
        assertEq(ethOut, 47); // ((100 * 99) * 1000) / ((2000 * 100) + (100 * 99)) = 47,165316818

        ethOut = exchange.getEthAmount(2000 wei);
        assertEq(ethOut, 497); // ((2000 * 99) * 1000) / ((2000 * 100) + (2000 * 99)) = 497,487437186
    }
}
