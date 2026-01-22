// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "../src/Community.sol";

contract CommunityTest is Test {
    Community public community;
    
    address public admin = address(1);
    address public user1 = address(2);
    address public user2 = address(3);
    address public user3 = address(4);
    
    string public name = "Test Community";
    string public description = "Test Description";

    event ContributionAdded(
        uint256 indexed id,
        address indexed contributor,
        uint256 points,
        uint256 indexed periodId,
        string title
    );
    event RewardsDeposited(uint256 amount, uint256 indexed periodId);
    event PeriodClosed(uint256 indexed periodId, uint256 totalPoints, uint256 rewardPool);
    event RewardsClaimed(address indexed user, uint256 indexed periodId, uint256 amount);
    event AdminUpdated(address indexed oldAdmin, address indexed newAdmin);

    function setUp() public {
        // Deploy Community contract
        vm.prank(admin);
        community = new Community(name, description, admin);
        
        // Label addresses for better trace output
        vm.label(admin, "Admin");
        vm.label(user1, "User1");
        vm.label(user2, "User2");
        vm.label(user3, "User3");
        
        // Fund test accounts
        vm.deal(admin, 100 ether);
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(user3, 10 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constructor() public view {
        // Verify basic properties
        assertEq(community.name(), name);
        assertEq(community.description(), description);
        assertEq(community.admin(), admin);
        assertEq(community.createdAt(), block.timestamp);
        assertEq(community.currentPeriodId(), 0);
        assertEq(community.contributionCount(), 0);
        
        // Verify first period is created and active
        Community.Period memory period = community.getPeriodInfo(0);
        assertEq(period.id, 0);
        assertEq(period.startTime, block.timestamp);
        assertEq(period.endTime, 0);
        assertEq(period.totalPoints, 0);
        assertEq(period.rewardPool, 0);
        assertTrue(period.isActive);
    }

    function test_Constructor_RevertIf_ZeroAddress() public {
        vm.expectRevert(Community.ZeroAddress.selector);
        new Community(name, description, address(0));
    }

    /*//////////////////////////////////////////////////////////////
                    ADD CONTRIBUTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_AddContribution() public {
        string memory title = "Great contribution";
        uint256 points = 100;
        
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit ContributionAdded(0, user1, points, 0, title);
        community.addContribution(user1, title, points);
        
        // Verify contribution stored
        (
            uint256 id,
            address contributor,
            string memory storedTitle,
            uint256 storedPoints,
            uint256 timestamp,
            uint256 periodId
        ) = community.contributions(0);
        
        assertEq(id, 0);
        assertEq(contributor, user1);
        assertEq(storedTitle, title);
        assertEq(storedPoints, points);
        assertEq(timestamp, block.timestamp);
        assertEq(periodId, 0);
        
        // Verify mappings updated
        assertEq(community.userPointsPerPeriod(0, user1), points);
        assertEq(community.totalUserPoints(user1), points);
        assertEq(community.contributionCount(), 1);
        
        // Verify period updated
        Community.Period memory period = community.getPeriodInfo(0);
        assertEq(period.totalPoints, points);
    }

    function test_AddContribution_MultipleContributions() public {
        vm.startPrank(admin);
        
        // Add multiple contributions
        community.addContribution(user1, "Contribution 1", 100);
        community.addContribution(user2, "Contribution 2", 150);
        community.addContribution(user1, "Contribution 3", 50);
        
        vm.stopPrank();
        
        // Verify totals
        assertEq(community.userPointsPerPeriod(0, user1), 150);
        assertEq(community.userPointsPerPeriod(0, user2), 150);
        assertEq(community.totalUserPoints(user1), 150);
        assertEq(community.totalUserPoints(user2), 150);
        assertEq(community.contributionCount(), 3);
        
        // Verify period total
        Community.Period memory period = community.getPeriodInfo(0);
        assertEq(period.totalPoints, 300);
    }

    function test_AddContribution_RevertIf_NotAdmin() public {
        vm.prank(user1);
        vm.expectRevert(Community.OnlyAdmin.selector);
        community.addContribution(user1, "Test", 100);
    }

    function test_AddContribution_RevertIf_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(Community.ZeroAddress.selector);
        community.addContribution(address(0), "Test", 100);
    }

    function test_AddContribution_RevertIf_ZeroPoints() public {
        vm.prank(admin);
        vm.expectRevert(Community.InvalidPoints.selector);
        community.addContribution(user1, "Test", 0);
    }

    /*//////////////////////////////////////////////////////////////
                    DEPOSIT REWARDS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_DepositRewards() public {
        uint256 depositAmount = 1 ether;
        
        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit RewardsDeposited(depositAmount, 0);
        community.depositRewards{value: depositAmount}();
        
        // Verify period rewardPool updated
        Community.Period memory period = community.getPeriodInfo(0);
        assertEq(period.rewardPool, depositAmount);
    }

    function test_DepositRewards_Multiple() public {
        vm.startPrank(admin);
        
        community.depositRewards{value: 1 ether}();
        community.depositRewards{value: 0.5 ether}();
        
        vm.stopPrank();
        
        // Verify total
        Community.Period memory period = community.getPeriodInfo(0);
        assertEq(period.rewardPool, 1.5 ether);
    }

    function test_DepositRewards_RevertIf_NotAdmin() public {
        vm.prank(user1);
        vm.expectRevert(Community.OnlyAdmin.selector);
        community.depositRewards{value: 1 ether}();
    }

    /*//////////////////////////////////////////////////////////////
                    CLOSE PERIOD TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ClosePeriod() public {
        // Add contributions and rewards
        vm.startPrank(admin);
        community.addContribution(user1, "Test", 100);
        community.depositRewards{value: 1 ether}();
        
        // Close period
        vm.expectEmit(true, false, false, true);
        emit PeriodClosed(0, 100, 1 ether);
        community.closePeriod();
        
        vm.stopPrank();
        
        // Verify old period is inactive
        Community.Period memory oldPeriod = community.getPeriodInfo(0);
        assertFalse(oldPeriod.isActive);
        assertEq(oldPeriod.endTime, block.timestamp);
        assertEq(oldPeriod.totalPoints, 100);
        assertEq(oldPeriod.rewardPool, 1 ether);
        
        // Verify new period is created
        assertEq(community.currentPeriodId(), 1);
        Community.Period memory newPeriod = community.getPeriodInfo(1);
        assertEq(newPeriod.id, 1);
        assertTrue(newPeriod.isActive);
        assertEq(newPeriod.startTime, block.timestamp);
        assertEq(newPeriod.endTime, 0);
        assertEq(newPeriod.totalPoints, 0);
        assertEq(newPeriod.rewardPool, 0);
    }

    function test_ClosePeriod_RevertIf_NotAdmin() public {
        vm.prank(user1);
        vm.expectRevert(Community.OnlyAdmin.selector);
        community.closePeriod();
    }

    /*//////////////////////////////////////////////////////////////
                    CLAIM REWARDS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ClaimRewards() public {
        // Setup: Add contributions
        vm.startPrank(admin);
        community.addContribution(user1, "User1 Contribution", 100);
        community.addContribution(user2, "User2 Contribution", 150);
        
        // Deposit rewards
        community.depositRewards{value: 1 ether}();
        
        // Close period
        community.closePeriod();
        vm.stopPrank();
        
        // User1 claims
        uint256 user1BalanceBefore = user1.balance;
        uint256 expectedUser1Reward = (100 * 1 ether) / 250; // 0.4 ether
        
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit RewardsClaimed(user1, 0, expectedUser1Reward);
        community.claimRewards(0);
        
        assertEq(user1.balance - user1BalanceBefore, expectedUser1Reward);
        assertTrue(community.hasClaimed(0, user1));
        
        // User2 claims
        uint256 user2BalanceBefore = user2.balance;
        uint256 expectedUser2Reward = (150 * 1 ether) / 250; // 0.6 ether
        
        vm.prank(user2);
        vm.expectEmit(true, true, false, true);
        emit RewardsClaimed(user2, 0, expectedUser2Reward);
        community.claimRewards(0);
        
        assertEq(user2.balance - user2BalanceBefore, expectedUser2Reward);
        assertTrue(community.hasClaimed(0, user2));
    }

    function test_ClaimRewards_PreciseDistribution() public {
        // Test with precise numbers
        vm.startPrank(admin);
        community.addContribution(user1, "Test", 1000);
        community.addContribution(user2, "Test", 3000);
        community.addContribution(user3, "Test", 6000);
        
        community.depositRewards{value: 10 ether}();
        community.closePeriod();
        vm.stopPrank();
        
        // Total points: 10000
        // User1: 1000/10000 * 10 = 1 ether
        // User2: 3000/10000 * 10 = 3 ether
        // User3: 6000/10000 * 10 = 6 ether
        
        vm.prank(user1);
        community.claimRewards(0);
        assertEq(user1.balance, 11 ether); // Started with 10
        
        vm.prank(user2);
        community.claimRewards(0);
        assertEq(user2.balance, 13 ether);
        
        vm.prank(user3);
        community.claimRewards(0);
        assertEq(user3.balance, 16 ether);
    }

    function test_ClaimRewards_RevertIf_PeriodActive() public {
        vm.startPrank(admin);
        community.addContribution(user1, "Test", 100);
        community.depositRewards{value: 1 ether}();
        // Don't close period
        vm.stopPrank();
        
        vm.prank(user1);
        vm.expectRevert(Community.PeriodStillActive.selector);
        community.claimRewards(0);
    }

    function test_ClaimRewards_RevertIf_AlreadyClaimed() public {
        vm.startPrank(admin);
        community.addContribution(user1, "Test", 100);
        community.depositRewards{value: 1 ether}();
        community.closePeriod();
        vm.stopPrank();
        
        // Claim successfully
        vm.prank(user1);
        community.claimRewards(0);
        
        // Try to claim again
        vm.prank(user1);
        vm.expectRevert(Community.AlreadyClaimed.selector);
        community.claimRewards(0);
    }

    function test_ClaimRewards_RevertIf_NoPoints() public {
        vm.startPrank(admin);
        community.addContribution(user1, "Test", 100);
        community.depositRewards{value: 1 ether}();
        community.closePeriod();
        vm.stopPrank();
        
        // User2 has no points
        vm.prank(user2);
        vm.expectRevert(Community.NoPointsInPeriod.selector);
        community.claimRewards(0);
    }

    function test_ClaimRewards_RevertIf_PeriodNotFound() public {
        vm.prank(user1);
        vm.expectRevert(Community.PeriodNotFound.selector);
        community.claimRewards(999);
    }

    /*//////////////////////////////////////////////////////////////
                    UPDATE ADMIN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_UpdateAdmin() public {
        address newAdmin = address(10);
        
        vm.prank(admin);
        vm.expectEmit(true, true, false, false);
        emit AdminUpdated(admin, newAdmin);
        community.updateAdmin(newAdmin);
        
        assertEq(community.admin(), newAdmin);
        
        // Verify new admin can perform admin functions
        vm.prank(newAdmin);
        community.addContribution(user1, "Test", 100);
        
        // Verify old admin cannot
        vm.prank(admin);
        vm.expectRevert(Community.OnlyAdmin.selector);
        community.addContribution(user1, "Test", 100);
    }

    function test_UpdateAdmin_RevertIf_NotAdmin() public {
        vm.prank(user1);
        vm.expectRevert(Community.OnlyAdmin.selector);
        community.updateAdmin(user1);
    }

    function test_UpdateAdmin_RevertIf_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(Community.ZeroAddress.selector);
        community.updateAdmin(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                    VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetClaimableAmount() public {
        vm.startPrank(admin);
        community.addContribution(user1, "Test", 100);
        community.addContribution(user2, "Test", 150);
        community.depositRewards{value: 1 ether}();
        community.closePeriod();
        vm.stopPrank();
        
        // Check claimable amounts
        uint256 user1Claimable = community.getClaimableAmount(user1, 0);
        uint256 user2Claimable = community.getClaimableAmount(user2, 0);
        
        assertEq(user1Claimable, (100 * 1 ether) / 250);
        assertEq(user2Claimable, (150 * 1 ether) / 250);
        
        // After claiming, should return 0
        vm.prank(user1);
        community.claimRewards(0);
        
        assertEq(community.getClaimableAmount(user1, 0), 0);
    }

    function test_GetClaimableAmount_NoPoints() public {
        vm.startPrank(admin);
        community.addContribution(user1, "Test", 100);
        community.depositRewards{value: 1 ether}();
        community.closePeriod();
        vm.stopPrank();
        
        // User2 has no points
        assertEq(community.getClaimableAmount(user2, 0), 0);
    }

    function test_GetUserPoints() public {
        vm.startPrank(admin);
        community.addContribution(user1, "Contribution 1", 100);
        community.addContribution(user1, "Contribution 2", 50);
        vm.stopPrank();
        
        assertEq(community.getUserPoints(user1, 0), 150);
        assertEq(community.getUserPoints(user2, 0), 0);
    }

    function test_GetPeriodInfo() public {
        vm.startPrank(admin);
        community.addContribution(user1, "Test", 100);
        community.depositRewards{value: 1 ether}();
        vm.stopPrank();
        
        Community.Period memory period = community.getPeriodInfo(0);
        
        assertEq(period.id, 0);
        assertEq(period.totalPoints, 100);
        assertEq(period.rewardPool, 1 ether);
        assertTrue(period.isActive);
    }

    function test_GetContributions() public {
        vm.startPrank(admin);
        community.addContribution(user1, "First", 100);
        community.addContribution(user2, "Second", 150);
        vm.stopPrank();
        
        Community.Contribution[] memory contributions = community.getContributions();
        
        assertEq(contributions.length, 2);
        assertEq(contributions[0].contributor, user1);
        assertEq(contributions[0].points, 100);
        assertEq(contributions[1].contributor, user2);
        assertEq(contributions[1].points, 150);
    }

    function test_GetTotalContributions() public {
        assertEq(community.getTotalContributions(), 0);
        
        vm.startPrank(admin);
        community.addContribution(user1, "Test", 100);
        assertEq(community.getTotalContributions(), 1);
        
        community.addContribution(user2, "Test", 150);
        assertEq(community.getTotalContributions(), 2);
        vm.stopPrank();
    }

    function test_GetCommunityStats() public {
        (
            string memory communityName,
            string memory communityDescription,
            address communityAdmin,
            uint256 totalContributions,
            uint256 activePeriodId,
            uint256 communityCreatedAt
        ) = community.getCommunityStats();
        
        assertEq(communityName, name);
        assertEq(communityDescription, description);
        assertEq(communityAdmin, admin);
        assertEq(totalContributions, 0);
        assertEq(activePeriodId, 0);
        assertEq(communityCreatedAt, block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                    MULTI-PERIOD TESTS
    //////////////////////////////////////////////////////////////*/

    function test_MultiPeriod_UserPointsPersistedAcrossPeriods() public {
        vm.startPrank(admin);
        
        // Period 0
        community.addContribution(user1, "Period 0", 100);
        community.depositRewards{value: 1 ether}();
        community.closePeriod();
        
        // Period 1
        community.addContribution(user1, "Period 1", 200);
        community.addContribution(user2, "Period 1", 300);
        community.depositRewards{value: 2 ether}();
        community.closePeriod();
        
        vm.stopPrank();
        
        // Verify points per period
        assertEq(community.getUserPoints(user1, 0), 100);
        assertEq(community.getUserPoints(user1, 1), 200);
        assertEq(community.getUserPoints(user2, 0), 0);
        assertEq(community.getUserPoints(user2, 1), 300);
        
        // Verify total points
        assertEq(community.totalUserPoints(user1), 300);
        assertEq(community.totalUserPoints(user2), 300);
        
        // Claim from both periods
        vm.prank(user1);
        community.claimRewards(0); // 1 ether
        
        vm.prank(user1);
        community.claimRewards(1); // 200/500 * 2 = 0.8 ether
        
        assertEq(user1.balance, 11.8 ether);
    }

    /*//////////////////////////////////////////////////////////////
                    EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ClaimRewards_ZeroRewardPool() public {
        vm.startPrank(admin);
        community.addContribution(user1, "Test", 100);
        // Don't deposit rewards
        community.closePeriod();
        vm.stopPrank();
        
        uint256 balanceBefore = user1.balance;
        
        vm.prank(user1);
        community.claimRewards(0);
        
        // Should successfully claim 0
        assertEq(user1.balance, balanceBefore);
        assertTrue(community.hasClaimed(0, user1));
    }

    function test_GetClaimableAmount_RevertIf_PeriodNotFound() public {
        vm.expectRevert(Community.PeriodNotFound.selector);
        community.getClaimableAmount(user1, 999);
    }
}
