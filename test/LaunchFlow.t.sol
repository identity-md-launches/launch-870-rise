// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Rise} from "../src/Rise.sol";

/// @dev Test fixture for constructor ownership and exact ERC-20 launch movements.
///      This is not ProjectFactory, a Merkle distributor, or a Uniswap pool implementation.
contract TokenDeployer {
    address private immutable controller = msg.sender;

    function deploy(bytes32 salt) external returns (Rise) {
        require(msg.sender == controller, "only test controller");
        return new Rise{salt: salt}();
    }

    function move(Rise token, address to, uint256 amount) external {
        require(msg.sender == controller, "only test controller");
        require(token.transfer(to, amount), "transfer failed");
    }
}

contract LaunchFlowTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000e18;
    address private constant DISTRIBUTOR = address(0xD157);
    address private constant POOL_MANAGER = address(0x9001);
    address private constant CREATOR = address(0xC0DE);
    address private constant CLAIMANT = address(0xC1A1);
    address private constant TRADER = address(0x7ADE);
    TokenDeployer private factory;
    Rise private token;

    function setUp() public {
        factory = new TokenDeployer();
        token = factory.deploy(bytes32(uint256(1)));
    }

    function test_create2UsesEmptyConstructorArgumentsAndMintsToFactory() public view {
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff), address(factory), bytes32(uint256(1)), keccak256(type(Rise).creationCode)
                        )
                    )
                )
            )
        );
        assertEq(address(token), predicted);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(CREATOR), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_duplicateCreate2FailsAndDoesNotRemint() public {
        vm.expectRevert();
        factory.deploy(bytes32(uint256(1)));
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
    }

    function test_launchAllocationClaimsAndPoolTokenLegsAreExact() public {
        uint256 swarm = SUPPLY * 1_000 / 10_000;
        uint256 pool = SUPPLY * 9_000 / 10_000;
        factory.move(token, DISTRIBUTOR, swarm);
        factory.move(token, POOL_MANAGER, pool);
        assertEq(token.balanceOf(DISTRIBUTOR), 100_000_000e18);
        assertEq(token.balanceOf(POOL_MANAGER), 900_000_000e18);
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(CREATOR), 0);

        vm.prank(DISTRIBUTOR);
        assertTrue(token.transfer(CLAIMANT, swarm));
        assertEq(token.balanceOf(CLAIMANT), swarm);
        assertEq(token.balanceOf(DISTRIBUTOR), 0);

        // Model only the token legs. Actual price, pool fees and swaps are external integration tests.
        vm.prank(POOL_MANAGER);
        assertTrue(token.transfer(TRADER, 123e18));
        assertEq(token.balanceOf(TRADER), 123e18);
        assertEq(token.balanceOf(POOL_MANAGER), pool - 123e18);
        vm.prank(TRADER);
        assertTrue(token.transfer(POOL_MANAGER, 123e18));
        assertEq(token.balanceOf(TRADER), 0);
        assertEq(token.balanceOf(POOL_MANAGER), pool);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
