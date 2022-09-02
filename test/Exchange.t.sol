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

    receive() external payable {}

    function setUp() public virtual {
        token = new Token("Test Token", "TKN", 31337);
        exchange = new Exchange(address(token));

        owner = address(this);
        vm.label(owner, "Owner");

        user = vm.addr(1);
        vm.label(user, "User");
    }
}

contract DeploymentTest is ExchangeBaseSetup {
    function setUp() public virtual override {
        ExchangeBaseSetup.setUp();
    }

    function testDeploymentInvariants() public {
        assertEq(exchange.tokenAddress(), address(token));
        assertEq(exchange.name(), "Uniswap-V1");
        assertEq(exchange.symbol(), "UNI-V1");
        assertEq(exchange.totalSupply(), 0);
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
        assertEq(exchange.balanceOf(owner), 100 wei);
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
        assertEq(exchange.balanceOf(owner), 150 wei);
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

contract RemoveLiquidityTest is ExchangeBaseSetup {
    function setUp() public virtual override {
        ExchangeBaseSetup.setUp();
        token.approve(address(exchange), 300 wei);
        exchange.addLiquidity{value: 100 wei}(200 wei);
    }

    function testRemoveSomeLiquidity() public {
        uint256 userEtherBalanceBefore = owner.balance; // x
        uint256 userTokenBalanceBefore = token.balanceOf(owner); // y

        (uint256 ethAmount, uint256 tokenAmount) = exchange.removeLiquidity(25 wei);

        // ethAmount = (100 * 25) / 100 = 25
        assertEq(ethAmount, 25 wei);
        // tokenAmount = (200 * 25) / 100 = 50
        assertEq(tokenAmount, 50 wei);

        // reserve = 200 - 50 = 150
        assertEq(exchange.getReserve(), 150 wei);
        // _burn(msg.sender, 25)
        // totalSupply = 100 - 25 = 75
        assertEq(exchange.totalSupply(), 75 wei);

        // x + ethAmount = x + 25
        uint256 userEtherBalanceAfter = owner.balance;
        // y + tokenAmount = y + 50
        uint256 userTokenBalanceAfter = token.balanceOf(owner);

        assertEq(userEtherBalanceAfter - userEtherBalanceBefore, 25); // x + 25 - x
        assertEq(userTokenBalanceAfter - userTokenBalanceBefore, 50); // y + 50 - y
    }

    function testRemoveAllLiquidity() public {
        uint256 userEtherBalanceBefore = owner.balance; // x
        uint256 userTokenBalanceBefore = token.balanceOf(owner); // y

        (uint256 ethAmount, uint256 tokenAmount) = exchange.removeLiquidity(100 wei);

        // ethAmount = (100 * 100) / 100 = 100
        assertEq(ethAmount, 100 wei);
        // tokenAmount = (200 * 100) / 100 = 200
        assertEq(tokenAmount, 200 wei);

        // reserve = 200 - 200 = 0
        assertEq(exchange.getReserve(), 0 wei);
        // _burn(msg.sender, 100)
        // totalSupply = 100 - 100 = 0
        assertEq(exchange.totalSupply(), 0 wei);

        // x + ethAmount = x + 100
        uint256 userEtherBalanceAfter = owner.balance;
        // y + tokenAmount = y + 200
        uint256 userTokenBalanceAfter = token.balanceOf(owner);

        assertEq(userEtherBalanceAfter - userEtherBalanceBefore, 100); // x + 100 - x
        assertEq(userTokenBalanceAfter - userTokenBalanceBefore, 200); // y + 200 - y
    }

    function testPaymentForLiquidityProvided() public {
        uint256 userEtherBalanceBefore = owner.balance; // x
        uint256 userTokenBalanceBefore = token.balanceOf(owner); // y

        hoax(user);
        // tokenReserve = 200
        // tokensBought = getAmount(10 wei, 110 - 10 wei, 200)
        // getAmount = ((10 * 99) * 200) / ((100 * 100) + (10 * 99)) = 18,016378526 ~ 18 tokens
        exchange.ethToTokenSwap{value: 10 wei}(18 wei);

        (uint256 ethAmount, uint256 tokenAmount) = exchange.removeLiquidity(100 wei);

        // ethAmount = (110 * 100) / 100 = 110
        assertEq(ethAmount, 110 wei);
        // tokenAmount = ((200 - 18) * 100) / 100 = 182
        assertEq(tokenAmount, 182 wei);

        // reserve = (200 - 18) - 182 = 0
        assertEq(exchange.getReserve(), 0 wei);
        // balance = (100 + 10) - 110 = 0
        assertEq(address(exchange).balance, 0 wei);

        // x + ethAmount = x + 110
        uint256 userEtherBalanceAfter = owner.balance;
        // y + tokenAmount = y + 182
        uint256 userTokenBalanceAfter = token.balanceOf(owner);

        assertEq(userEtherBalanceAfter - userEtherBalanceBefore, 110 wei); // x + 110 - x
        assertEq(userTokenBalanceAfter - userTokenBalanceBefore, 182 wei); // y + 182 - y
    }

    function testBurnLPTokens() public {
        assertEq(exchange.totalSupply(), 100 wei);
        exchange.removeLiquidity(25 wei);
        // _burn(msg.sender, 25)
        assertEq(exchange.totalSupply(), 75 wei); // 100 - 25
    }

    function testCannotRemoveLiquidity() public {
        vm.expectRevert(stdError.arithmeticError); // burn amount exceeds balance
        exchange.removeLiquidity(101 wei);
    }
}

contract GetAmountTest is ExchangeBaseSetup {
    function setUp() public virtual override {
        ExchangeBaseSetup.setUp();
        token.approve(address(exchange), 2000 wei);
        exchange.addLiquidity{value: 1000 wei}(2000 wei);
    }

    function testGetTokenAmount() public {
        uint256 tokensOut = exchange.getTokenAmount(1 wei);
        assertEq(tokensOut, 1); // ((1 * 99) * 2000) / ((1000 * 100) + (1 * 99)) = 1,978041739

        tokensOut = exchange.getTokenAmount(100 wei);
        assertEq(tokensOut, 180); // ((100 * 99) * 2000) / ((1000 * 100) + (100 * 99)) = 180,163785259

        tokensOut = exchange.getTokenAmount(1000 wei);
        assertEq(tokensOut, 994); // ((1000 * 99) * 2000) / ((1000 * 100) + (1000 * 99)) = 994,974874372
    }

    function testGetEthAmount() public {
        uint256 ethOut = exchange.getEthAmount(2 wei);
        assertEq(ethOut, 0); // ((2 * 99) * 1000) / ((2000 * 100) + (2 * 99)) = 0,989020869

        ethOut = exchange.getEthAmount(100 wei);
        assertEq(ethOut, 47); // ((100 * 99) * 1000) / ((2000 * 100) + (100 * 99)) = 47,165316818

        ethOut = exchange.getEthAmount(2000 wei);
        assertEq(ethOut, 497); // ((2000 * 99) * 1000) / ((2000 * 100) + (2000 * 99)) = 497,487437186
    }
}
