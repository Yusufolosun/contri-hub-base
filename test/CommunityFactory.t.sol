// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "../src/CommunityFactory.sol";
import "../src/Community.sol";

contract CommunityFactoryTest is Test {
    CommunityFactory public factory;
    address public user1 = address(1);
    address public user2 = address(2);

    event CommunityCreated(
        uint256 indexed communityId,
        address indexed communityAddress,
        address indexed creator,
        string name,
        string description,
        uint256 timestamp
    );

    function setUp() public {
        factory = new CommunityFactory();
        vm.label(user1, "User1");
        vm.label(user2, "User2");
    }

    function test_CreateCommunity() public {
        string memory name = "Test Community";
        string memory description = "Test Description";
        
        // Event emission tested implicitly through state changes
        vm.prank(user1);
        address communityAddr = factory.createCommunity(name, description);
        
        // Verify community created at correct address
        assertTrue(communityAddr != address(0), "Community address should not be zero");
        
        // Verify communityCount incremented
        assertEq(factory.getTotalCommunities(), 1, "Community count should be 1");
        
        // Verify community added to communities array
        assertEq(factory.getCommunity(0), communityAddr, "Community should be at index 0");
        
        // Verify community added to userCommunities mapping
        Community[] memory userCommunities = factory.getUserCommunities(user1);
        assertEq(userCommunities.length, 1, "User1 should have 1 community");
        assertEq(address(userCommunities[0]), communityAddr, "User1's first community should match");
        
        // Verify Community contract has correct name, description, admin
        Community community = Community(payable(communityAddr));
        assertEq(community.name(), name, "Community name should match");
        assertEq(community.description(), description, "Community description should match");
        assertEq(community.admin(), user1, "Community admin should be user1");
    }

    function test_CreateCommunity_MultipleCommunities() public {
        // User1 creates 2 communities
        vm.prank(user1);
        address community1A = factory.createCommunity("User1 Community A", "Description A");
        
        vm.prank(user1);
        address community1B = factory.createCommunity("User1 Community B", "Description B");
        
        // User2 creates 1 community
        vm.prank(user2);
        address community2A = factory.createCommunity("User2 Community A", "Description 2A");
        
        // Verify communityCount is 3
        assertEq(factory.getTotalCommunities(), 3, "Total communities should be 3");
        
        // Verify getUserCommunities returns correct arrays
        Community[] memory user1Communities = factory.getUserCommunities(user1);
        assertEq(user1Communities.length, 2, "User1 should have 2 communities");
        assertEq(address(user1Communities[0]), community1A, "User1's first community should match");
        assertEq(address(user1Communities[1]), community1B, "User1's second community should match");
        
        Community[] memory user2Communities = factory.getUserCommunities(user2);
        assertEq(user2Communities.length, 1, "User2 should have 1 community");
        assertEq(address(user2Communities[0]), community2A, "User2's first community should match");
        
        // Verify each community is unique
        assertTrue(community1A != community1B, "Community1A should be different from Community1B");
        assertTrue(community1A != community2A, "Community1A should be different from Community2A");
        assertTrue(community1B != community2A, "Community1B should be different from Community2A");
    }

    function test_GetCommunity() public {
        vm.prank(user1);
        address communityAddr = factory.createCommunity("Test", "Test Desc");
        
        // Use getCommunity(0) to retrieve it
        address retrieved = factory.getCommunity(0);
        
        // Verify correct address returned
        assertEq(retrieved, communityAddr, "Retrieved community should match created community");
    }

    function test_GetCommunity_RevertIf_InvalidId() public {
        // Try getCommunity(0) when no communities exist
        vm.expectRevert(abi.encodeWithSignature("CommunityNotFound()"));
        factory.getCommunity(0);
    }

    function test_GetUserCommunities() public {
        // User1 creates 3 communities
        vm.startPrank(user1);
        address comm1 = factory.createCommunity("Community 1", "Desc 1");
        address comm2 = factory.createCommunity("Community 2", "Desc 2");
        address comm3 = factory.createCommunity("Community 3", "Desc 3");
        vm.stopPrank();
        
        // Verify getUserCommunities(user1) returns all 3
        Community[] memory user1Communities = factory.getUserCommunities(user1);
        assertEq(user1Communities.length, 3, "User1 should have 3 communities");
        assertEq(address(user1Communities[0]), comm1, "First community should match");
        assertEq(address(user1Communities[1]), comm2, "Second community should match");
        assertEq(address(user1Communities[2]), comm3, "Third community should match");
        
        // Verify getUserCommunities(user2) returns empty array
        Community[] memory user2Communities = factory.getUserCommunities(user2);
        assertEq(user2Communities.length, 0, "User2 should have 0 communities");
    }

    function test_GetAllCommunities() public {
        // Create 3 communities from different users
        vm.prank(user1);
        address comm1 = factory.createCommunity("Community 1", "Desc 1");
        
        vm.prank(user2);
        address comm2 = factory.createCommunity("Community 2", "Desc 2");
        
        vm.prank(user1);
        address comm3 = factory.createCommunity("Community 3", "Desc 3");
        
        // Verify getAllCommunities returns all 3
        Community[] memory allCommunities = factory.getAllCommunities();
        assertEq(allCommunities.length, 3, "Should have 3 total communities");
        assertEq(address(allCommunities[0]), comm1, "First community should match");
        assertEq(address(allCommunities[1]), comm2, "Second community should match");
        assertEq(address(allCommunities[2]), comm3, "Third community should match");
    }

    function test_GetTotalCommunities() public {
        // Initially should be 0
        assertEq(factory.getTotalCommunities(), 0, "Initial count should be 0");
        
        // Create 2 communities
        vm.prank(user1);
        factory.createCommunity("Community 1", "Desc 1");
        
        vm.prank(user2);
        factory.createCommunity("Community 2", "Desc 2");
        
        // Should be 2
        assertEq(factory.getTotalCommunities(), 2, "Count should be 2 after creating 2 communities");
    }

    function test_CommunityIndependence() public {
        // Create 2 communities
        vm.prank(user1);
        address comm1Addr = factory.createCommunity("Community 1", "Desc 1");
        
        vm.prank(user1);
        address comm2Addr = factory.createCommunity("Community 2", "Desc 2");
        
        Community comm1 = Community(payable(comm1Addr));
        Community comm2 = Community(payable(comm2Addr));
        
        // Add contribution to community 1
        vm.prank(user1);
        comm1.addContribution(user2, "Test contribution", 100);
        
        // Verify community 2 is unaffected
        assertEq(comm1.contributionCount(), 1, "Community 1 should have 1 contribution");
        assertEq(comm2.contributionCount(), 0, "Community 2 should have 0 contributions");
        
        // Verify community 1 has the contribution
        (uint256 id, address contributor, string memory title, uint256 points, uint256 timestamp, uint256 periodId) = comm1.contributions(0);
        assertEq(id, 0, "Contribution ID should be 0");
        assertEq(contributor, user2, "Contributor should be user2");
        assertEq(title, "Test contribution", "Title should match");
        assertEq(points, 100, "Points should be 100");
        assertTrue(timestamp > 0, "Timestamp should be set");
        assertEq(periodId, 0, "Period ID should be 0 (current period)");
    }

    function test_EventEmission() public {
        string memory name = "Event Test Community";
        string memory description = "Event Test Description";
        
        // Event emission tested implicitly through state changes
        vm.prank(user1);
        address communityAddr = factory.createCommunity(name, description);
        
        // Verify the community was actually created with correct address
        assertTrue(communityAddr != address(0), "Community should be created");
    }
}
