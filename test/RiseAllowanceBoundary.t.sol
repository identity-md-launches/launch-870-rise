// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Rise} from "src/Rise.sol";

/// @dev Complements RiseTest with allowance lifecycles and failure/retry sequences.
/// forge-config: default.fuzz.runs = 1000
contract RiseAllowanceBoundaryTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000e18;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);
    address private constant OTHER = address(0x07E5);
    Rise private token;

    function setUp() public {
        token = new Rise();
    }

    function test_maximumFiniteAllowanceIsNotInfinite() public {
        token.approve(SPENDER, type(uint256).max - 1);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max - 2);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, SUPPLY - 1));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max - 1 - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(BOB), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_infiniteApprovalCanBeReducedAndRevoked() public {
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);

        token.approve(SPENDER, 2);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 2));
        assertEq(token.allowance(address(this), SPENDER), 0);
        _expectNoAllowance(address(this), ALICE);

        token.approve(SPENDER, type(uint256).max);
        token.approve(SPENDER, 0);
        _expectNoAllowance(address(this), ALICE);
        assertEq(token.balanceOf(ALICE), 3);
        assertEq(token.balanceOf(address(this)), SUPPLY - 3);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function testFuzz_approvalIsReplacementAndIdempotent(uint256 first, uint256 replacement) public {
        token.approve(SPENDER, first);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), SPENDER, replacement);
        assertTrue(token.approve(SPENDER, replacement));
        assertEq(token.allowance(address(this), SPENDER), replacement);
        assertTrue(token.approve(SPENDER, replacement));
        assertEq(token.allowance(address(this), SPENDER), replacement);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_allowancesAreScopedToOwnerAndSpender(uint256 allowed, uint256 spent) public {
        allowed = bound(allowed, 1, SUPPLY / 2);
        spent = bound(spent, 1, allowed);
        token.transfer(ALICE, SUPPLY / 2);
        token.transfer(BOB, SUPPLY / 2);
        vm.prank(ALICE);
        token.approve(SPENDER, allowed);
        vm.prank(BOB);
        token.approve(SPENDER, type(uint256).max);
        vm.prank(ALICE);
        token.approve(OTHER, 7);

        // The deployer cannot use an approval granted to someone else.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(ALICE, address(this), 1);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, OTHER, spent));
        assertEq(token.allowance(ALICE, SPENDER), allowed - spent);
        assertEq(token.allowance(BOB, SPENDER), type(uint256).max);
        assertEq(token.allowance(ALICE, OTHER), 7);
        assertEq(token.allowance(SPENDER, ALICE), 0);
        assertEq(token.allowance(ALICE, address(this)), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY / 2 - spent);
        assertEq(token.balanceOf(BOB), SUPPLY / 2);
        assertEq(token.balanceOf(OTHER), spent);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function testFuzz_exhaustedAllowanceCannotBeReplayed(uint256 amount) public {
        amount = bound(amount, 1, SUPPLY / 2);
        token.transfer(ALICE, SUPPLY);
        vm.prank(ALICE);
        token.approve(SPENDER, amount);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, amount));
        // ALICE still has funds: rejection must come from authorization, not an empty balance.
        _expectNoAllowance(ALICE, BOB);
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY - amount);
        assertEq(token.balanceOf(BOB), amount);
    }

    function testFuzz_balanceFailurePreservesApprovalForRetry(uint256 funded, uint256 extra, bool infinite) public {
        funded = bound(funded, 0, SUPPLY - 1);
        extra = bound(extra, 1, SUPPLY - funded);
        uint256 amount = funded + extra;
        uint256 allowed = infinite ? type(uint256).max : amount;
        token.transfer(ALICE, funded);
        vm.prank(ALICE);
        token.approve(SPENDER, allowed);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, funded, amount));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, amount);
        assertEq(token.allowance(ALICE, SPENDER), allowed);
        assertEq(token.balanceOf(ALICE), funded);
        assertEq(token.balanceOf(BOB), 0);

        token.transfer(ALICE, extra);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, amount));
        assertEq(token.allowance(ALICE, SPENDER), infinite ? type(uint256).max : 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_directTransferDoesNotSpendOrMoveApprovals(uint256 allowed, uint256 amount) public {
        amount = bound(amount, 1, SUPPLY);
        token.transfer(ALICE, SUPPLY);
        vm.prank(ALICE);
        token.approve(SPENDER, allowed);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, amount));
        assertEq(token.allowance(ALICE, SPENDER), allowed);
        assertEq(token.allowance(BOB, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY - amount);
        assertEq(token.balanceOf(BOB), amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(BOB, OTHER, 1);
        assertEq(token.balanceOf(BOB), amount);
        assertEq(token.balanceOf(OTHER), 0);
    }

    function testFuzz_zeroDelegatedTransferEmitsEventAndPreservesApproval(uint256 allowed) public {
        vm.prank(ALICE);
        token.approve(SPENDER, allowed);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(ALICE, BOB, 0);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.allowance(ALICE, SPENDER), allowed);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroApprovalToZeroSpenderStillReverts() public {
        token.approve(SPENDER, 17);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), SPENDER), 17);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_approvedSelfTransferCannotExceedBalance() public {
        token.transfer(ALICE, 1);
        vm.prank(ALICE);
        token.approve(SPENDER, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 1, 2));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, ALICE, 2);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.allowance(ALICE, SPENDER), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroDelegatedTransferToZeroCannotBurnOrConsumeApproval() public {
        token.approve(SPENDER, 17);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(address(this), SPENDER), 17);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _expectNoAllowance(address owner, address recipient) private {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(owner, recipient, 1);
    }
}
