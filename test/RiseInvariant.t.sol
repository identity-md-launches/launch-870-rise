// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Rise} from "../src/Rise.sol";

/// @dev Closed set of five holders and an independent balance/allowance model.
contract RiseHandler is Test {
    uint256 private constant SUPPLY = 1_000_000_000e18;
    Rise public immutable token;
    address[5] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(Rise token_) {
        token = token_;
        actors = [address(this), address(0xA11CE), address(0xB0B), address(0xCA11), address(0xD15)];
        expectedBalance[address(this)] = SUPPLY;
    }

    function transfer(uint8 fromSeed, uint8 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint8 ownerSeed, uint8 spenderSeed, uint256 amount, bool infinite) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = infinite ? type(uint256).max : bound(amount, 0, SUPPLY);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint8 fromSeed, uint8 spenderSeed, uint8 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        // Includes zero transfers and one unit above the balance, so success and failure mix.
        amount = bound(amount, 0, expectedBalance[from] + 1);
        uint256 allowed = expectedAllowance[from][spender];
        bool shouldSucceed = amount <= expectedBalance[from] && amount <= allowed;
        vm.prank(spender);
        (bool ok, bytes memory result) = address(token).call(abi.encodeCall(IERC20.transferFrom, (from, to, amount)));
        assertEq(ok, shouldSucceed);
        if (shouldSucceed) {
            assertTrue(abi.decode(result, (bool)));
            expectedBalance[from] -= amount;
            expectedBalance[to] += amount;
            if (allowed != type(uint256).max) expectedAllowance[from][spender] -= amount;
        }
    }
}

contract RiseInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000e18;
    Rise private token;
    RiseHandler private handler;

    function setUp() public {
        token = new Rise();
        handler = new RiseHandler(token);
        token.transfer(address(handler), SUPPLY);
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = RiseHandler.transfer.selector;
        selectors[1] = RiseHandler.approve.selector;
        selectors[2] = RiseHandler.transferFrom.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_supplyAndBalancesMatchModel() public view {
        assertEq(token.totalSupply(), SUPPLY);
        uint256 sum;
        for (uint256 i; i < 5; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalance(actor));
            sum += balance;
        }
        assertEq(sum, SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function invariant_allowancesMatchModelIncludingFailedSpends() public view {
        for (uint256 i; i < 5; ++i) {
            for (uint256 j; j < 5; ++j) {
                address owner = handler.actors(i);
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }
}
