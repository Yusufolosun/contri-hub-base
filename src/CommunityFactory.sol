// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "./Community.sol";

/// @title Community Factory
/// @notice Factory contract for deploying and managing Community contracts
/// @dev Creates new Community instances and tracks all deployed communities
contract CommunityFactory {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Array of all deployed Community contracts
    Community[] public communities;

    /// @notice Total number of communities created
    uint256 public communityCount;

    /// @notice Maps user addresses to their created communities
    /// @dev user address => array of Community contracts
    mapping(address => Community[]) public userCommunities;

    /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when requesting a community that doesn't exist
    error CommunityNotFound();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new community is created
    /// @param communityId The ID of the community (index in array)
    /// @param communityAddress The address of the deployed Community contract
    /// @param creator The address of the community creator
    /// @param name The name of the community
    /// @param description The description of the community
    /// @param timestamp The block timestamp when created
    event CommunityCreated(
        uint256 indexed communityId,
        address indexed communityAddress,
        address indexed creator,
        string name,
        string description,
        uint256 timestamp
    );

    /*//////////////////////////////////////////////////////////////
                            MAIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates and deploys a new Community contract
    /// @param _name The name for the new community
    /// @param _description The description for the new community
    /// @return The address of the newly deployed Community contract
    function createCommunity(
        string memory _name,
        string memory _description
    ) external returns (address) {
        // Deploy new Community contract with msg.sender as admin
        Community newCommunity = new Community(_name, _description, msg.sender);

        // Store in communities array
        communities.push(newCommunity);

        // Add to user's communities
        userCommunities[msg.sender].push(newCommunity);

        // Emit event with community ID (current count before incrementing)
        emit CommunityCreated(
            communityCount,
            address(newCommunity),
            msg.sender,
            _name,
            _description,
            block.timestamp
        );

        // Increment counter
        communityCount++;

        return address(newCommunity);
    }

    /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Gets a community contract by its ID
    /// @param _communityId The ID of the community to retrieve
    /// @return The address of the Community contract
    function getCommunity(uint256 _communityId)
        external
        view
        returns (address)
    {
        if (_communityId >= communities.length) revert CommunityNotFound();
        return address(communities[_communityId]);
    }

    /// @notice Gets all communities created by a specific user
    /// @param _user The address of the user
    /// @return Array of Community contracts created by the user
    function getUserCommunities(address _user)
        external
        view
        returns (Community[] memory)
    {
        return userCommunities[_user];
    }

    /// @notice Gets all deployed communities
    /// @return Array of all Community contracts
    function getAllCommunities() external view returns (Community[] memory) {
        return communities;
    }

    /// @notice Gets the total number of communities created
    /// @return The total count of communities
    function getTotalCommunities() external view returns (uint256) {
        return communityCount;
    }
}
