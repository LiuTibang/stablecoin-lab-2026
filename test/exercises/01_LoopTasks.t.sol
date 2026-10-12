// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {MockUSDC} from "../../src/MockUSDC.sol";
import {SimpleStablecoin} from "../../src/SimpleStablecoin.sol";
import {Vault} from "../../src/Vault.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/// @title Ex2 + Ex4 — hands-on tasks: turn red into green
/// @notice Every `assertTrue(false, "TODO ...")` below is a placeholder. Write the real
///         assertion, watch the test go green, and that exercise is done.
///
///         Acceptance: make exercise (it should be red until you are finished)
///         Do not open test/Stablecoin.t.sol — it contains the answers. Write yours
///         first, and only look once you are stuck.
contract LoopTasksTest is Test {
    MockUSDC internal usdc;
    SimpleStablecoin internal stable;
    Vault internal vault;

    address internal admin = address(this);
    address internal alice = makeAddr("alice");
    address internal attacker = makeAddr("attacker");

    function setUp() public {
        usdc = new MockUSDC();
        stable = new SimpleStablecoin(admin);
        vault = new Vault(usdc, stable);
        stable.grantRole(stable.MINTER_ROLE(), address(vault));
    }

    // ==================================================================
    // Ex2 · the decimals trap: a 6-decimal stablecoin meets 18-decimal intuition
    // ==================================================================

    /// @dev For any legitimate amount x, totalSupply() must grow by exactly x after
    ///      deposit(x). Hint: use vm.assume to rule out x == 0, and faucet alice enough
    ///      usdc first.
    function test_Ex2_DepositIncreasesSupplyByExactly(uint96 raw) public {
    uint256 amount = uint256(raw) % 1_000_000e6;

    // Exclude zero amounts
    vm.assume(amount > 0);

    // Give Alice enough collateral
    usdc.faucet(alice, amount);

    // Record the initial supply
    uint256 supplyBefore = stable.totalSupply();

    // Simulate Alice
    vm.startPrank(alice);

    // Approve the vault
    usdc.approve(address(vault), amount);

    // Deposit collateral
    vault.deposit(amount);

    vm.stopPrank();

    // Verify that supply increased by exactly the deposited amount
    assertEq(stable.totalSupply() - supplyBefore, amount);

    // Verify the collateral invariant
    assertEq(vault.totalCollateral(), stable.totalSupply());
}

    /// @dev Run deposit with 1000e18 instead of 1000e6, see what happens, then assert what
    ///      you observed. MockUSDC has 6 decimals — 1000e18 is one billion USDC.
    ///      There is no expected answer here; the point is that you run it yourself and
    ///      read the numbers.
    function test_Ex2_DecimalsTrap() public {

    // Incorrect: using 18 decimals for a 6-decimal token
    uint256 wrongAmount = 1000e18;

    // Give Alice the incorrectly scaled amount
    usdc.faucet(alice, wrongAmount);

    vm.startPrank(alice);

    usdc.approve(address(vault), wrongAmount);

    // The deposit still succeeds
    vault.deposit(wrongAmount);

    vm.stopPrank();

    // Verify the raw supply
    assertEq(stable.totalSupply(), wrongAmount);

    // Verify the actual number of tokens
    assertEq(stable.totalSupply() / 1e6, 1e15);

    // The invariant still holds
    assertEq(vault.totalCollateral(), stable.totalSupply());
}

    // ==================================================================
    // Ex4 · permissions and pausing: where the guard is, who holds the key
    // ==================================================================

    /// @dev The attacker has no MINTER_ROLE, so calling mint directly must revert. Use
    ///      vm.expectRevert + abi.encodeWithSelector to pin down the exact error.
    function test_Ex4_Mint_RevertsForNonMinter() public {

    // 1. Confirm attacker does not have MINTER_ROLE
    assertFalse(
        stable.hasRole(stable.MINTER_ROLE(), attacker)
    );

    // 2. Expect the exact access control error
    vm.expectRevert(
        abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector,
            attacker,
            stable.MINTER_ROLE()
        )
    );

    // 3. Simulate the attacker calling the contract
    vm.prank(attacker);

    // 4. Unauthorized mint attempt
    stable.mint(attacker, 1000e6);

    // 5. Verify no new tokens were issued
    assertEq(stable.totalSupply(), 0);
}

    /// @dev After pause(), an ordinary transfer must revert
    function test_Ex4_Pause_BlocksTransfers() public {

    uint256 amount = 1000e6;

    // 1. Give Alice 1000 mUSDC
    usdc.faucet(alice, amount);

    // 2. Alice deposits collateral and receives sUSD
    vm.startPrank(alice);

    usdc.approve(address(vault), amount);
    vault.deposit(amount);

    vm.stopPrank();

    // 3. Confirm Alice has 1000 sUSD
    assertEq(stable.balanceOf(alice), amount);

    // 4. Admin pauses the stablecoin
    stable.pause();

    // 5. Confirm the contract is paused
    assertTrue(stable.paused());

    // 6. Expect transfer to fail because of pause
    vm.expectRevert(
        abi.encodeWithSelector(
            Pausable.EnforcedPause.selector
        )
    );

    // 7. Alice attempts to transfer 100 sUSD
    vm.prank(alice);

    stable.transfer(attacker, 100e6);

    // 8. Alice's balance must remain unchanged
    assertEq(stable.balanceOf(alice), amount);
}

    /// @dev What pause() freezes is _update, so redemption is frozen along with everything
    ///      else — why is that bad news in a real crisis?
    ///      (This is STUDENT-QUESTIONS.md B1 and B2.)
    function test_Ex4_Pause_BlocksRedeem() public {

    uint256 amount = 1000e6;

    // 1. Give Alice collateral
    usdc.faucet(alice, amount);

    // 2. Alice deposits collateral
    vm.startPrank(alice);

    usdc.approve(address(vault), amount);
    vault.deposit(amount);

    vm.stopPrank();

    // 3. Verify initial balances
    assertEq(stable.balanceOf(alice), amount);
    assertEq(vault.totalCollateral(), amount);

    // 4. Admin pauses stablecoin
    stable.pause();

    // 5. Redemption should revert
    vm.expectRevert(
        abi.encodeWithSelector(
            Pausable.EnforcedPause.selector
        )
    );

    // 6. Alice tries to redeem
    vm.prank(alice);

    vault.redeem(amount);

    // 7. Verify funds remain locked in the vault
    assertEq(stable.balanceOf(alice), amount);
    assertEq(vault.totalCollateral(), amount);
}

    /// @dev An attacker cannot burn someone else's balance
    function test_Ex4_AttackerCannotBurnOthersBalance() public {

    uint256 amount = 1000e6;

    // 1. Admin mints 1000 sUSD to Alice
    stable.mint(alice, amount);

    // 2. Verify Alice's balance
    assertEq(stable.balanceOf(alice), amount);

    // 3. Expect unauthorized access error
    vm.expectRevert(
        abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector,
            attacker,
            stable.MINTER_ROLE()
        )
    );

    // 4. Simulate attacker
    vm.prank(attacker);

    // 5. Attacker tries to burn Alice's tokens
    stable.burn(alice, 100e6);

    // 6. Verify Alice's balance remains unchanged
    assertEq(stable.balanceOf(alice), amount);
}

    /// @dev ...but the vault can, because it holds MINTER_ROLE and burn() answers to that
    ///      same role. This test proves the backdoor exists; it does not justify it.
    function test_Ex4_VaultHoldsTheKey_CanBurnAnyonesBalance()
    public
{
    uint256 amount = 1000e6;

    // 1. Admin gives Alice 1000 sUSD
    stable.mint(alice, amount);

    // 2. Verify Vault has MINTER_ROLE
    assertTrue(
        stable.hasRole(
            stable.MINTER_ROLE(),
            address(vault)
        )
    );

    // 3. Simulate a call originating from the Vault
    vm.prank(address(vault));

    // 4. Vault burns Alice's tokens
    stable.burn(alice, 100e6);

    // 5. Verify Alice now has only 900 sUSD
    assertEq(
        stable.balanceOf(alice),
        900e6
    );

    // 6. Verify total supply also decreased
    assertEq(
        stable.totalSupply(),
        900e6
    );
}
}
