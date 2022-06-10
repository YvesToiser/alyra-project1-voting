// SPDX-License-Identifier: MIT

pragma solidity ^0.8.14;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/contracts/access/Ownable.sol";

contract Voting is Ownable{

    /**
        These variable are specified in the specs.
        That's why we did not use uint8.
    */
    struct Voter {
        bool isRegistered;
        bool hasVoted;
        uint votedProposalId;
    }

    struct Proposal {
        string description;
        uint voteCount;
    }

    enum WorkflowStatus {
        RegisteringVoters,
        ProposalsRegistrationStarted,
        ProposalsRegistrationEnded,
        VotingSessionStarted,
        VotingSessionEnded,
        VotesTallied
    }

    uint public winningProposalId;

    event VoterRegistered(address voterAddress);
    event WorkflowStatusChange(WorkflowStatus previousStatus, WorkflowStatus newStatus);
    event ProposalRegistered(uint proposalId);
    event Voted (address voter, uint proposalId);
    // custom events for quorum
    event VotingQuorumEvent(bool reached);
    event WinningQuorumEvent(bool reached);

    /**
        Handle the workflow status
        Automatically initialized as -> WorkflowStatus.RegisteringVoters
    */
    WorkflowStatus public currentStatus;

    // Whitelist of registered voters and array of proposals.
    // Whitelist is Public so that everybody can see the votes as per the specs.
    mapping(address => Voter) public whitelist;
    Proposal[] public proposals;

    /**
        These variables are added for quorum settlement
        uint8 variables are declared together for memory optimisation
        automatically initialized as -> 0 (No quorum by default)
    */
    uint8 votingQuorum;
    uint8 winningQuorum;
    uint8 registeredVoters;
    uint8 votersNb;

    /**
        This function is visible for everyone.
    */

    function getWinner() external view returns(string memory){
        require(currentStatus == WorkflowStatus.VotesTallied,
            "Can not show winning proposal before closing the counts.");
        return proposals[winningProposalId].description;
    }

    /**
        These functions are for registered voters only.
        They use a custom modifier onlyVoter.
        You can register proposals or vote depending on the workflow status.
        Specs were not very clear. As we could not contact PO for clarification,
        we decided that a voter can register as many proposal as he wants
        but can only vote once.
    */

    modifier onlyVoter {
        require(whitelist[msg.sender].isRegistered == true,
            "You are not registered as a voter.");
        _;
    }

    function registerProposal(string calldata _description) external onlyVoter {
        require(currentStatus == WorkflowStatus.ProposalsRegistrationStarted,
            "The proposal registration period is now closed.");
        proposals.push(Proposal(_description, 0));
        emit ProposalRegistered(proposals.length - 1);
    }

    function voteForProposal(uint _propId) external onlyVoter {
        require(currentStatus == WorkflowStatus.VotingSessionStarted,
            "The voting period is now closed.");
        require(_propId < proposals.length,
            "This proposal does not exists. Please vote again.");
        require(whitelist[msg.sender].hasVoted == false,
            "You have already voted. Cannot vote a second time.");
        proposals[_propId].voteCount ++;
        whitelist[msg.sender].votedProposalId = _propId;
        whitelist[msg.sender].hasVoted = true;
        votersNb ++;
        emit Voted(msg.sender, _propId);
    }

    /**
        These functions are for admin management, therefore they have the modifier onlyowner.
        The first one add voters to the whitelist while the following ones handle the workflow.
        For convenience, we decided to handle the last step of the workflow automatically.
        This would have to be confirmed with Po in real situation.
    */

    function addToWhitelist(address _address) external onlyOwner {
        require(currentStatus == WorkflowStatus.RegisteringVoters,
            "Whitelist registration period is closed.");
        require(whitelist[_address].isRegistered == false,
            "Voter is already registered.");
        whitelist[_address] = Voter(true, false, 0);
        registeredVoters ++;
        emit VoterRegistered(_address);
    }

    function startProposalRegistration() external onlyOwner {
        require(currentStatus == WorkflowStatus.RegisteringVoters,
            "Can not start proposal registration in this workflow phase.");
        proposals.push(Proposal("Vote Blanc", 0));
        currentStatus = WorkflowStatus.ProposalsRegistrationStarted;
        emit WorkflowStatusChange(WorkflowStatus.RegisteringVoters,
            WorkflowStatus.ProposalsRegistrationStarted);
    }

    function endProposalRegistration() external onlyOwner {
        require(currentStatus == WorkflowStatus.ProposalsRegistrationStarted,
            "Can not end proposal registration in this workflow phase.");
        currentStatus = WorkflowStatus.ProposalsRegistrationEnded;
        emit WorkflowStatusChange(WorkflowStatus.ProposalsRegistrationStarted,
            WorkflowStatus.ProposalsRegistrationEnded);
    }

    function startVotingSession() external onlyOwner {
        require(currentStatus == WorkflowStatus.ProposalsRegistrationEnded,
            "Can not start voting session in this workflow phase.");
        currentStatus = WorkflowStatus.VotingSessionStarted;
        emit WorkflowStatusChange(WorkflowStatus.ProposalsRegistrationEnded,
            WorkflowStatus.VotingSessionStarted);
    }

    function endVotingSession() external onlyOwner {
        require(currentStatus == WorkflowStatus.VotingSessionStarted,
            "Can not end voting session in this workflow phase.");
        currentStatus = WorkflowStatus.VotingSessionEnded;
        emit WorkflowStatusChange(WorkflowStatus.VotingSessionStarted,
            WorkflowStatus.VotingSessionEnded);
        doCounts();
    }

    function setVotingQuorum(uint8 _vq) external onlyOwner {
        require(currentStatus == WorkflowStatus.ProposalsRegistrationEnded,
            "Can not set quorum in this workflow phase.");
        require(_vq <= 100, "Quorum must be expressed in percentage. Value must be between 0 and 100.");
        votingQuorum = _vq;
    }

    function setWiningQuorum(uint8 _wq) external onlyOwner {
        require(currentStatus == WorkflowStatus.ProposalsRegistrationEnded,
            "Can not set quorum in this workflow phase.");
        require(_wq <= 100, "Quorum must be expressed in percentage. Value must be between 0 and 100.");
        winningQuorum = _wq;
    }

    /**
        Theses functions are called internally.
        When the admin end the voting session, it triggers the function "doCounts".
        These function determines the winning proposal id and then trigger the function "closeCounts".
        The last step of the workflow is then done automatically.
    */

    function doCounts() private {
        uint _highestVote = proposals[0].voteCount;
        uint8 _winId = 0;
        for (uint8 i = 1; i < proposals.length; i++) {
            if(proposals[i].voteCount > _highestVote){
                _highestVote = proposals[i].voteCount;
                _winId = i;
            }
        }
        // If 2 proposals have the same number of votes we choose the first one
        // as this case is not handled in the specs.
        // if the quorum are reached, we register the winning Id.
        // else we leave the winning id at 0 which is the "empty vote"
        if (checkQuorum(_winId)) {
            winningProposalId = _winId;
        }
        closeCounts();
    }

    function closeCounts() private {
        require(currentStatus == WorkflowStatus.VotingSessionEnded,
            "Can not close counts in this workflow phase.");
        currentStatus = WorkflowStatus.VotesTallied;
        emit WorkflowStatusChange(WorkflowStatus.VotingSessionEnded,
            WorkflowStatus.VotesTallied);
    }

    function checkQuorum(uint8 _winId) private returns(bool){
        bool votingQuorumReached = 100 * votersNb / registeredVoters >= votingQuorum;
        emit VotingQuorumEvent(votingQuorumReached);
        bool winningQuorumReached = 100 * uint8 (proposals[_winId].voteCount) / votersNb >= winningQuorum;
        emit WinningQuorumEvent(winningQuorumReached);

        return (votingQuorumReached && winningQuorumReached);
    }

}