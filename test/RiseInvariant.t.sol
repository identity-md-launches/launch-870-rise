// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
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
        // Approvals may exceed the supply. Exercise the entire uint256 domain.
        amount = infinite ? type(uint256).max : amount;
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
        _spend(from, spender, to, amount, allowed);
    }

    function spendApproved(uint8 fromSeed, uint8 spenderSeed, uint8 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowed = expectedAllowance[from][spender];
        uint256 limit = expectedBalance[from] < allowed ? expectedBalance[from] : allowed;
        _spend(from, spender, to, bound(amount, 0, limit), allowed);
    }

    function _spend(address from, address spender, address to, uint256 amount, uint256 allowed) private {
        bool shouldSucceed = amount <= expectedBalance[from] && amount <= allowed;
        vm.prank(spender);
        (bool ok, bytes memory result) = address(token).call(abi.encodeCall(IERC20.transferFrom, (from, to, amount)));
        assertEq(ok, shouldSucceed);
        if (shouldSucceed) {
            assertTrue(abi.decode(result, (bool)));
            expectedBalance[from] -= amount;
            expectedBalance[to] += amount;
            if (allowed != type(uint256).max) expectedAllowance[from][spender] -= amount;
        } else if (amount > allowed) {
            assertEq(
                result,
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
            );
        } else {
            assertEq(
                result,
                abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientBalance.selector, from, expectedBalance[from], amount
                )
            );
        }
    }

    function revokeAndAttemptSpend(uint8 ownerSeed, uint8 spenderSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, 0));
        expectedAllowance[owner][spender] = 0;
        _spend(owner, spender, spender, 1, 0);
    }

    function rejectTransfer(uint8 fromSeed, uint256 amount, bool zeroReceiver) external {
        address from = actors[fromSeed % actors.length];
        uint256 balance = expectedBalance[from];
        address to = zeroReceiver ? address(0) : actors[(uint256(fromSeed) + 1) % actors.length];
        amount = zeroReceiver ? bound(amount, 0, balance) : balance + bound(amount, 1, type(uint256).max - balance);
        bytes memory error = zeroReceiver
            ? abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
            : abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount);
        vm.prank(from);
        (bool ok, bytes memory result) = address(token).call(abi.encodeCall(IERC20.transfer, (to, amount)));
        assertFalse(ok);
        assertEq(result, error);
        // Ghosts stay unchanged: both invariants check rollback for every actor and allowance.
    }

    function rejectDelegatedTransfer(
        uint8 fromSeed,
        uint8 spenderSeed,
        uint256 amount,
        bool zeroReceiver,
        bool infinite
    ) external {
        address from = actors[fromSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 balance = expectedBalance[from];
        address to = zeroReceiver ? address(0) : actors[(uint256(fromSeed) + 1) % actors.length];
        amount = zeroReceiver ? bound(amount, 0, balance) : balance + bound(amount, 1, type(uint256).max - balance);
        uint256 allowed = infinite ? type(uint256).max : amount;
        vm.prank(from);
        assertTrue(token.approve(spender, allowed));
        expectedAllowance[from][spender] = allowed;

        bytes memory error = zeroReceiver
            ? abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
            : abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount);
        vm.prank(spender);
        (bool ok, bytes memory result) = address(token).call(abi.encodeCall(IERC20.transferFrom, (from, to, amount)));
        assertFalse(ok);
        assertEq(result, error);
        assertEq(token.allowance(from, spender), allowed, "failed transfer spent allowance");
    }

    function rejectZeroSpender(uint8 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        vm.prank(owner);
        (bool ok, bytes memory result) = address(token).call(abi.encodeCall(IERC20.approve, (address(0), amount)));
        assertFalse(ok);
        assertEq(result, abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        assertEq(token.allowance(owner, address(0)), 0);
    }

    function fullBalanceRoundTrip(uint8 fromSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[(uint256(fromSeed) + 1) % actors.length];
        uint256 amount = expectedBalance[from];
        uint256 recipientBefore = expectedBalance[to];
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(from), 0, "holder could not transfer its whole balance");
        assertEq(token.balanceOf(to), recipientBefore + amount, "outbound transfer charged a fee");
        assertEq(token.totalSupply(), SUPPLY);
        vm.prank(to);
        assertTrue(token.transfer(from, amount));
        assertEq(token.balanceOf(from), amount);
        assertEq(token.balanceOf(to), recipientBefore);
        // A fee-free round trip is the identity; neither ghost ledger should change.
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 96
/// forge-config: default.invariant.fail-on-revert = true
contract RiseInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000e18;
    Rise private token;
    RiseHandler private handler;

    function setUp() public {
        token = new Rise();
        handler = new RiseHandler(token);
        token.transfer(address(handler), SUPPLY);
        // Seed all holders and an allowance ring so nonzero delegated spends are reachable immediately.
        for (uint8 i = 1; i < 5; ++i) {
            handler.transfer(0, i, SUPPLY / 5);
        }
        for (uint8 i; i < 5; ++i) {
            handler.approve(i, (i + 1) % 5, SUPPLY / 5, i % 2 == 0);
        }
        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = RiseHandler.transfer.selector;
        selectors[1] = RiseHandler.approve.selector;
        selectors[2] = RiseHandler.transferFrom.selector;
        selectors[3] = RiseHandler.spendApproved.selector;
        selectors[4] = RiseHandler.revokeAndAttemptSpend.selector;
        selectors[5] = RiseHandler.rejectTransfer.selector;
        selectors[6] = RiseHandler.rejectDelegatedTransfer.selector;
        selectors[7] = RiseHandler.rejectZeroSpender.selector;
        selectors[8] = RiseHandler.fullBalanceRoundTrip.selector;
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
        assertEq(token.balanceOf(address(token)), 0);
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
