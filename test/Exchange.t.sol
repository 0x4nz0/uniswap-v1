// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Token.sol";
import "../src/Exchange.sol";
import "../src/Factory.sol";

contract ExchangeBaseSetup is Test {
    Token internal token;
    Factory internal factory;
    Exchange internal exchange;

    address internal owner;
    address internal user;

    receive() external payable {}

    function setUp() public virtual {
        owner = address(this);
        vm.label(owner, "Owner");

        user = vm.addr(1);
        vm.label(user, "User");

        token = new Token("Test Token", "TKN", 31337);
        factory = new Factory();

        address exchangeAddress = factory.createExchange(address(token));

        exchange = Exchange(exchangeAddress);
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
        assertEq(exchange.factoryAddress(), address(factory));
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

    function testShouldMintLPTokensWhenLiquidityIsAdded() public {
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

    function testShouldPreserveExchangeRateWhenLiquidityIsAdded() public {
        exchange.addLiquidity{value: 50 wei}(200 wei);

        assertEq(address(exchange).balance, 150 wei);
        assertEq(exchange.getReserve(), 300 wei);
    }

    function testShouldMintLPTokensWhenLiquidityIsAdded() public {
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

    function testCannotAddLiquidityIfNotEnoughTokens() public {
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

    function testShouldPayWhenLiquidityIsRemoved() public {
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

    function testShouldBurnLPTokensWhenLiquidityIsRemoved() public {
        assertEq(exchange.totalSupply(), 100 wei);
        exchange.removeLiquidity(25 wei);
        // _burn(msg.sender, 25)
        assertEq(exchange.totalSupply(), 75 wei); // 100 - 25
    }

    function testCannotRemoveLiquidityIfInvalidAmount() public {
        vm.expectRevert(stdError.arithmeticError); // burn amount exceeds balance
        exchange.removeLiquidity(101 wei);
    }
}

contract EthToTokenTransferTest is ExchangeBaseSetup {
    function setUp() public virtual override {
        ExchangeBaseSetup.setUp();
        token.approve(address(exchange), 2000 wei);
        exchange.addLiquidity{value: 1000 wei}(2000 wei);
    }

    function testEthToTokenTransfer() public {
        startHoax(user, 1 wei);
        uint256 userEtherBalanceBefore = user.balance;

        // tokenReserve = 2000
        // tokensBought = getAmount(1 wei, 1001 - 1 wei, 2000)
        // getAmount = ((1 * 99) * 2000) / ((1000 * 100) + (1 * 99)) = 1,976 ~ 1 token
        exchange.ethToTokenTransfer{value: 1 wei}(1 wei, user);

        uint256 userEtherBalanceAfter = user.balance;
        assertEq(userEtherBalanceBefore - userEtherBalanceAfter, 1 wei);

        // tokensBought = 1
        uint256 userTokenBalance = token.balanceOf(user);
        assertEq(userTokenBalance, 1 wei);

        // msg.value + 1000 wei
        uint256 exchangeEtherBalance = address(exchange).balance;
        assertEq(exchangeEtherBalance, 1001 wei);

        // 2000 - tokensBought
        uint256 exchangeTokenBalance = token.balanceOf(address(exchange));
        assertEq(exchangeTokenBalance, 1999 wei);
    }
}

contract EthToTokenSwapTest is ExchangeBaseSetup {
    function setUp() public virtual override {
        ExchangeBaseSetup.setUp();
        token.approve(address(exchange), 2000 wei);
        exchange.addLiquidity{value: 1000 wei}(2000 wei);
    }

    function testEthToTokenSwap() public {
        startHoax(user, 1 wei);
        uint256 userEtherBalanceBefore = user.balance;

        // tokenReserve = 2000
        // tokensBought = getAmount(1 wei, 1001 - 1 wei, 2000)
        // getAmount = ((1 * 99) * 2000) / ((1000 * 100) + (1 * 99)) = 1,976 ~ 1 token
        exchange.ethToTokenSwap{value: 1 wei}(1 wei);

        uint256 userEtherBalanceAfter = user.balance;
        assertEq(userEtherBalanceBefore - userEtherBalanceAfter, 1 wei);

        // tokensBought = 1
        uint256 userTokenBalance = token.balanceOf(user);
        assertEq(userTokenBalance, 1 wei);

        // msg.value + 1000 wei
        uint256 exchangeEtherBalance = address(exchange).balance;
        assertEq(exchangeEtherBalance, 1001 wei);

        // 2000 - tokensBought
        uint256 exchangeTokenBalance = token.balanceOf(address(exchange));
        assertEq(exchangeTokenBalance, 1999 wei);
    }

    function testShouldAffectExchangeRateWhenUserSwaps() public {
        uint256 tokensOut = exchange.getTokenAmount(10 wei);
        assertEq(tokensOut, 19 wei);

        // tokenReserve = 2000
        // tokensBought = getAmount(10 wei, 1010 - 10 wei, 2000)
        // getAmount = ((10 * 99) * 2000) / ((1000 * 100) + (10 * 99)) = 19,76 ~ 19 tokens
        hoax(user, 10 wei);
        exchange.ethToTokenSwap{value: 10 wei}(9 wei);

        tokensOut = exchange.getTokenAmount(10 wei);
        assertEq(tokensOut, 19 wei);
    }

    function testCannotEthToTokenSwapIfNotEnoughOutputAmount() public {
        hoax(user, 1 wei);
        vm.expectRevert(bytes("insufficient output amount"));
        // tokenReserve = 2000
        // tokensBought = getAmount(1 wei, 1001 - 1 wei, 2000)
        // getAmount = ((1 * 99) * 2000) / ((1000 * 100) + (1 * 99)) = 1,976 ~ 1 token
        // require(1 >= 2) -> revert
        exchange.ethToTokenSwap{value: 1 wei}(2 wei);
    }
}

contract TokenToEthSwapTest is ExchangeBaseSetup {
    function setUp() public virtual override {
        ExchangeBaseSetup.setUp();
        token.transfer(user, 22 wei);
        vm.prank(user);
        token.approve(address(exchange), 22 wei);

        token.approve(address(exchange), 2000 wei);
        exchange.addLiquidity{value: 1000 wei}(2000 wei);
    }

    function testTokenToEthSwap() public {
        startHoax(user, 1 wei);
        uint256 userEtherBalanceBefore = user.balance;
        uint256 exchangeEtherBalanceBefore = address(exchange).balance;

        // tokenReserve = 2000
        // ethBought = getAmount(3 wei, 2000, 1000)
        // getAmount = ((3 * 99) * 1000) / ((2000 * 100) + (3 * 99)) = 1,4827 ~ 1 wei
        exchange.tokenToEthSwap(3 wei, 1 wei);

        // (ethBought + 1 wei) - 1 wei = 1 wei
        uint256 userEtherBalanceAfter = user.balance;
        assertEq(userEtherBalanceAfter - userEtherBalanceBefore, 1 wei);

        // 22 - tokensBought = 19
        uint256 userTokenBalance = token.balanceOf(user);
        assertEq(userTokenBalance, 19 wei);

        // msg.value + 1000 wei
        uint256 exchangeEtherBalanceAfter = address(exchange).balance;
        assertEq(exchangeEtherBalanceBefore - exchangeEtherBalanceAfter, 1 wei);

        // 2000 + tokensSold
        uint256 exchangeTokenBalance = token.balanceOf(address(exchange));
        assertEq(exchangeTokenBalance, 2003 wei);
    }

    function testShouldAffectExchangeRateWhenUserSwaps() public {
        uint256 ethOut = exchange.getEthAmount(20 wei);
        assertEq(ethOut, 9 wei);

        // tokenReserve = 2000
        // ethBought = getAmount(20 wei, 2000, 1000)
        // getAmount = ((20 * 99) * 1000) / ((2000 * 100) + (20 * 99)) = 9,802 ~ 9 wei
        vm.prank(user);
        exchange.tokenToEthSwap(20 wei, 9 wei);

        ethOut = exchange.getEthAmount(20 wei);
        assertEq(ethOut, 9 wei);
    }

    function testCannotEthToTokenSwapIfNotEnoughOutputAmount() public {
        vm.expectRevert(bytes("insufficient output amount"));
        // tokenReserve = 2000
        // ethBought = getAmount(5 wei, 2000, 1000)
        // getAmount = ((3 * 99) * 1000) / ((2000 * 100) + (3 * 99)) = 1,4827 ~ 1 wei
        // require(1 >= 2) -> revert
        exchange.tokenToEthSwap(3 wei, 2 wei);
    }
}

contract TokenToTokenSwapTest is Test {
    Token internal tokenA;
    Token internal tokenB;

    Factory internal factory;

    Exchange internal exchangeA;
    Exchange internal exchangeB;

    address internal owner;
    address internal user;

    function setUp() public {
        owner = address(this);
        vm.label(owner, "Owner");

        user = vm.addr(1);
        vm.label(user, "User");

        tokenA = new Token("Token A", "TKNA", 31337);
        vm.label(address(tokenA), "Token A");

        vm.prank(user);
        tokenB = new Token("Token B", "TKNB", 31337);
        vm.label(address(tokenB), "Token B");

        factory = new Factory();

        address exchangeAddress = factory.createExchange(address(tokenA));
        exchangeA = Exchange(exchangeAddress);
        vm.label(exchangeAddress, "Exchange A");

        vm.prank(user);
        exchangeAddress = factory.createExchange(address(tokenB));
        exchangeB = Exchange(exchangeAddress);
        vm.label(exchangeAddress, "Exchange B");
    }

    function testTokenToTokenSwap() public {
        tokenA.approve(address(exchangeA), 2000 wei);
        exchangeA.addLiquidity{value: 1000 wei}(2000 wei);
        // balanceA = 1000, reservesA = 2000
        assertEq(address(exchangeA).balance, 1000 wei);
        assertEq(exchangeA.getReserve(), 2000 wei);

        vm.prank(user);
        tokenB.approve(address(exchangeB), 1000 wei);
        hoax(user, 1000 wei);
        exchangeB.addLiquidity{value: 1000 wei}(1000 wei);
        // balanceB = 1000, reservesB = 1000
        assertEq(address(exchangeB).balance, 1000 wei);
        assertEq(exchangeB.getReserve(), 1000 wei);

        assertEq(tokenB.balanceOf(owner), 0 wei);

        tokenA.approve(address(exchangeA), 10 wei);
        // exchangeAddressB
        // reservesA = 2000
        // ethBought = getAmount(10, 2000, 1000) = 4,9256 ~ 4
        // tokenA.transferFrom(Owner, Exchange A, 10)
        // exchangeB.ethToTokenTransfer{value: 4}(3, Owner) -> ethToToken{value: 4}(3, Owner)
        // reservesB = 1000
        // tokensBought = getAmount(4, 1004 - 4, 1000) = 3,9443 ~ 3
        // tokenB.transfer(Owner, 3) -> transfer(Exchange B, Owner, 3)
        exchangeA.tokenToTokenSwap(10 wei, 3 wei, address(tokenB));
        assertEq(tokenB.balanceOf(owner), 3);

        assertEq(address(exchangeA).balance, 996 wei); // 1000 - ethBought
        assertEq(exchangeA.getReserve(), 2010 wei); // 2000 + tokensSold
        assertEq(address(exchangeB).balance, 1004 wei); // 1000 + ethBought
        assertEq(exchangeB.getReserve(), 997 wei); // 1000 - tokensBought

        assertEq(tokenA.balanceOf(user), 0 wei);

        vm.prank(user);
        tokenB.approve(address(exchangeB), 10 wei);
        vm.prank(user);
        // exchangeAddressA
        // reservesB = 997
        // ethBought = getAmount(10, 997, 1004) = 9,8714 ~ 9
        // tokenB.transferFrom(User, Exchange B, 10)
        // exchangeA.ethToTokenTransfer{value: 9}(17, User) -> ethToToken{value: 9}(17, User)
        // reservesA = 2010
        // tokensBought = getAmount(9, 1005 - 9, 2010) = 17,6477 ~ 17
        // tokenA.transfer(User, 17) -> transfer(Exchange A, User, 17)
        exchangeB.tokenToTokenSwap(10 wei, 17 wei, address(tokenA));

        assertEq(tokenA.balanceOf(user), 17 wei);

        assertEq(address(exchangeA).balance, 1005 wei); // 996 + ethBought
        assertEq(exchangeA.getReserve(), 1993 wei); // 2010 - tokensBought
        assertEq(address(exchangeB).balance, 995 wei); // 1004 - ethBought
        assertEq(exchangeB.getReserve(), 1007 wei); // 997 + tokensSold
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
