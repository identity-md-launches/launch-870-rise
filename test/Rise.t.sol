// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Rise} from "../src/Rise.sol";

contract RejectsCallbacks {
    fallback() external {
        revert("ERC-20 transfers must not call recipients");
    }
}

contract RiseTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000e18;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);
    Rise private token;

    function setUp() public {
        token = new Rise();
    }

    function test_metadataAndEntireSupplyBelongToDeployer() public view {
        assertEq(token.name(), "Rise");
        assertEq(token.symbol(), "RISE");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function test_constructorEmitsSingleMintToActualDeployer() public {
        vm.recordLogs();
        vm.prank(ALICE);
        Rise other = new Rise();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(other));
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(ALICE))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
        assertEq(other.balanceOf(ALICE), SUPPLY);
        assertEq(other.balanceOf(address(this)), 0);
    }

    function test_transferDeliversExactAmountAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), ALICE, 17e18);
        assertTrue(token.transfer(ALICE, 17e18));
        assertEq(token.balanceOf(ALICE), 17e18);
        assertEq(token.balanceOf(address(this)), SUPPLY - 17e18);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_entireSupplyAndSmallestUnitTransfer() public {
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 1));
        assertEq(token.balanceOf(ALICE), SUPPLY - 1);
        assertEq(token.balanceOf(BOB), 1);
    }

    function test_zeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferInsufficientBalanceRevertsWithoutMutation() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(BOB, 1);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferMaximumUintReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(ALICE, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_transferToZeroRevertsIncludingZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_approveEmitsEventAndDoesNotMoveFunds() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), SPENDER, 100e18);
        assertTrue(token.approve(SPENDER, 100e18));
        assertEq(token.allowance(address(this), SPENDER), 100e18);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(SPENDER), 0);
    }

    function test_approveReplacesAndCanRevokeAllowance() public {
        token.approve(SPENDER, 100);
        token.approve(SPENDER, 7);
        assertEq(token.allowance(address(this), SPENDER), 7);
        token.approve(SPENDER, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_approveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_transferFromConsumesExactAllowanceAndEmitsTransfer() public {
        token.approve(SPENDER, 5e18);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), ALICE, 3e18);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 3e18));
        assertEq(token.allowance(address(this), SPENDER), 2e18);
        assertEq(token.balanceOf(ALICE), 3e18);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, 2e18));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(BOB), 2e18);
        assertEq(token.balanceOf(address(this)), SUPPLY - 5e18);
    }

    function test_infiniteAllowanceRemainsUnchanged() public {
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, SUPPLY));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), SUPPLY);
    }

    function test_transferFromZeroAmountNeedsNoAllowance() public {
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromToSelfStillConsumesAllowance() public {
        token.approve(SPENDER, 10);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), address(this), 10));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_transferFromRequiresAllowanceEvenWhenCallerIsHolder() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), ALICE, 1);
    }

    function test_transferFromInsufficientAllowanceIsAtomic() public {
        token.approve(SPENDER, 9);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 9, 10));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 10);
        assertEq(token.allowance(address(this), SPENDER), 9);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_transferFromInsufficientBalanceRestoresAllowance() public {
        vm.prank(ALICE);
        token.approve(SPENDER, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 10));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 10);
        assertEq(token.allowance(ALICE, SPENDER), 10);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferFromToZeroRestoresAllowance() public {
        token.approve(SPENDER, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 10);
        assertEq(token.allowance(address(this), SPENDER), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromZeroSenderRevertsEvenForZeroAmount() public {
        // Allowance validation runs before the transfer and rejects a zero approver first.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), ALICE, 0);
    }

    function test_contractRecipientIsNotCalled() public {
        RejectsCallbacks receiver = new RejectsCallbacks();
        assertTrue(token.transfer(address(receiver), 1e18));
        assertEq(token.balanceOf(address(receiver)), 1e18);
    }

    function test_nativeCurrencyIsRejected() public {
        vm.deal(address(this), 1 ether);
        (bool accepted,) = address(token).call{value: 1 ether}("");
        assertFalse(accepted);
        assertEq(address(token).balance, 0);
    }

    function test_deployerAndStrangerHaveNoAdministrativeEntryPoints() public {
        token.transfer(ALICE, 100e18);
        bytes[] memory calls = new bytes[](19);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", BOB, 1);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[4] = abi.encodeWithSignature("burnFrom(address,uint256)", ALICE, 1);
        calls[5] = abi.encodeWithSignature("pause()");
        calls[6] = abi.encodeWithSignature("unpause()");
        calls[7] = abi.encodeWithSignature("blacklist(address)", ALICE);
        calls[8] = abi.encodeWithSignature("setBlacklist(address,bool)", ALICE, true);
        calls[9] = abi.encodeWithSignature("freeze(address)", ALICE);
        calls[10] = abi.encodeWithSignature("seize(address)", ALICE);
        calls[11] = abi.encodeWithSignature("transferOwnership(address)", BOB);
        calls[12] = abi.encodeWithSignature("upgradeTo(address)", BOB);
        calls[13] = abi.encodeWithSignature("upgradeToAndCall(address,bytes)", BOB, bytes(""));
        calls[14] = abi.encodeWithSignature("initialize(address)", BOB);
        calls[15] = abi.encodeWithSignature("setMinter(address)", BOB);
        calls[16] = abi.encodeWithSignature("setFee(uint256)", 100);
        calls[17] = abi.encodeWithSignature("owner()");
        calls[18] = abi.encodeWithSignature("disableTransfers()");
        for (uint256 i; i < calls.length; ++i) {
            (bool deployerAccepted,) = address(token).call(calls[i]);
            assertFalse(deployerAccepted);
            vm.prank(BOB);
            (bool strangerAccepted,) = address(token).call(calls[i]);
            assertFalse(strangerAccepted);
        }
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(ALICE, address(this), 1);
        assertEq(token.balanceOf(ALICE), 100e18);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100e18));
        assertEq(token.balanceOf(BOB), 100e18);
    }

    function test_runtimeHasNoForbiddenOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
                continue;
            }
            assertTrue(opcode != 0xf4 && opcode != 0xf2 && opcode != 0xff);
        }
    }

    function testFuzz_transferConservesSupply(uint256 funding, uint256 amount) public {
        funding = bound(funding, 0, SUPPLY);
        amount = bound(amount, 0, funding);
        token.transfer(ALICE, funding);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, amount));
        assertEq(token.balanceOf(ALICE), funding - amount);
        assertEq(token.balanceOf(BOB), amount);
        assertEq(token.balanceOf(address(this)) + token.balanceOf(ALICE) + token.balanceOf(BOB), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_delegatedTransfer(uint256 allowed, uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        allowed = bound(allowed, amount, type(uint256).max);
        token.approve(SPENDER, allowed);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, amount));
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(address(this), SPENDER), allowed == type(uint256).max ? allowed : allowed - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_overspendReverts(uint256 balance, uint256 excess) public {
        balance = bound(balance, 0, SUPPLY);
        excess = bound(excess, 1, type(uint256).max - balance);
        token.transfer(ALICE, balance);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, balance + excess)
        );
        vm.prank(ALICE);
        token.transfer(BOB, balance + excess);
        assertEq(token.balanceOf(ALICE), balance);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
