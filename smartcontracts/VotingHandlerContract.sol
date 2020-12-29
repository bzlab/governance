/* GNU GPL 3.0-License-Identifier
 * Police Governance Framework  Copyright (C) 2020  Taner Dursun
 *   This program comes with ABSOLUTELY NO WARRANTY
 *   This is free software, and you are welcome to redistribute it
 *   by referencing its original source.
 *      Istanbul Technical University and TUBITAK BILGEM Blockchain Research Lab
 *   
 *
 * @title Voting Contract
 * @author Taner Dursun <tdursun@gmail.com>
 *
 * @dev Singleton Governance service interfacing all change proposals submitted by actors
 *      Creates a ProposalContract for each proposal 
 *      Applies the results of votings on proposals handled by Proposal Contracts.
 *      Only contract that can communicate with PEP embedded in protocol layer of node.
 *      This Contract was developed for the Police On-Chain blockchain governance project.
 */
 
 pragma solidity ^0.5.3;
//pragma experimental ABIEncoderV2;

import "./RegistryContract.sol"; //or include Interfaca in this file
import "./ProposalContract.sol";
import "./PoliceLib.sol";
import "./PoliceContract.sol";


contract VotingHandlerContract is PoliceContract{ //THINK rename as GovernanceContract
    
    enum ProposalType{ IMPROVEMENT, BUG, BUSINESS, OTHER}
    enum ProposalCategory{ CONSENSUSPROTOCOL, VM, P2P, CORE, GOVERNANCE, MINING, OTHER}
    enum ProposalStatus{ ACTIVE, REJECTED, WITHDRAWN, ACCEPTED}
    
    
    uint constant MIN_ELIGIBLE_BALANCE_TO_PROPOSE = 1 wei;
    event NewProposal(uint pid, string title, string discussionURL, address pContract);
    

    struct Policy{
        uint id; //free form short name
        string title;
        string description;
        bytes policy;   // encoded as policy sytnax supported by the Platform
        uint date;
    }
    
    struct Proposal{
        uint id;
        string title;
        string proposerDID;  //cascaded struct varsa mapping'e koydurtmuyor
        bytes policy;
        string discussionURL;
        ProposalType pType; 
        ProposalCategory pCategory;
        uint pDate;         //proposal issuing date
        uint pExpireDate;   //proposal is valid until
        bytes signature;  //signature created by proposer for all fields above
        
        //belows are out of signing scope
        ProposalStatus pStatus;
        uint lockedStake; //locked stake
        address proposalContract;
    }
    

    mapping(uint => Proposal) proposals; // all proposals proposed so far (proposalID, proposal)
    
    mapping(uint => address) proposalContracts; // all proposals contracts created so far (proposalID, proposal contract's address)
    
    uint public proposalCount=0;
    
    mapping (uint => Policy) public policies;    // active policy set being enforced
    
    //RegistryContract registryContract;  //address of the RegistryContract
    address registryContract;
    
    constructor(address regContractAddr) internal{
        registryContract = regContractAddr;
    }
    

    //to propose a new policy 
    function proposeNew (string memory did, bytes memory proposal) public payable registeredActor(did, registryContract) ownerOfDID(did, msg.sender, registryContract){
        //Parse proposal
        string memory title;
        string memory proposerDID;  //cascaded struct varsa mapping'e koydurtmuyor
        bytes memory policyProposed; 
        string memory discussionURL;
        ProposalType pType; 
        ProposalCategory pCategory;
        uint pDate;         //proposal issuing date
        uint pExpireDate;   //proposal is valid until
        bytes memory signature;  //signature created by proposer for all fields above
    
        (title, proposerDID, policyProposed, discussionURL, pType, pCategory, pDate, pExpireDate, signature) = abi.decode(proposal,
            (string, string, bytes, string, ProposalType, ProposalCategory, uint, uint, bytes));
        Proposal memory prop = Proposal(proposalCount+1, title, proposerDID, policyProposed, discussionURL, pType, pCategory, pDate, pExpireDate, signature,
                ProposalStatus.ACTIVE, msg.value, address(0x0));
        require(PoliceLib.compareStr(proposerDID,did));

        //Parse policy
        uint id;
        string memory pTitle;
        string memory description;
        bytes memory policy;   // encoded as policy sytnax supported by the Platform
        uint date;
        (id, pTitle, description, policy, date) = abi.decode(policyProposed,(uint,string,string,bytes, uint));
        
        //verify signature of proposal
        //address signer = registryContract.getDDO(prop.proposerDID).signAddress;
        //require(msg.sender==signer);
        
        //verify signature ... not required in fact.
        
        // lock stake of proposer
        //require(address(signer).balance>= MIN_ELIGIBLE_BALANCE_TO_PROPOSEN);
        require(msg.value>= MIN_ELIGIBLE_BALANCE_TO_PROPOSE);
        //address(signer).transfer(this,MIN_ELIGIBLE_BALANCE_TO_PROPOSEN); //this amount should be higher than creating a proposal contract. Otherwise not deterrent
        
        // create a new proposal contract (proposal, this, regC) 
        ProposalContract pc = new ProposalContract(prop.id, address(this), address(registryContract));
        proposalContracts[proposalCount]= address(pc);

        prop.proposalContract = address(pc);
        proposals[proposalCount]=prop;
        proposalCount++;

        // announce "a new voting started" 
        emit NewProposal(prop.id, title, discussionURL, address(pc));
        // start a new voting
    }
    
    //to propose removal of an existing policy 
    /*function proposeRemove (Proposal prop) public payable{ 
        // verify DID of proposer
        require(registry.isRegistered(prop.proposerDID),"Proposer is not known by the Governance Framework");
        
        //ensure that proposal var mi, policy field dolu olmayabilir
        
        
        //verify signature of proposal
        address signer = registry.getDDO(prop.proposerDID).signAddress;
        //verify signature
        
        // lock stake of proposer
        //require(address(signer).balance>= MIN_ELIGIBLE_BALANCE_TO_PROPOSEN);
        require(msg.value>= MIN_ELIGIBLE_BALANCE_TO_PROPOSEN);

        //address(signer).transfer(this,MIN_ELIGIBLE_BALANCE_TO_PROPOSEN); //this amount should be higher than creating a proposal contract. Otherwise not deterrent
        proposals[proposalCount]=Proposal;
        
        // create a new proposal contract (proposal, this, regC) 
        proposaContracs[proposalCount]=ProposalContract(address(this), prop);

        proposalCount++;
        // announce "a new voting started"
        emit NewProposal(prop);
        // start a new voting
    }*/
    function withdrawProposal(string memory pDID, uint pid ) public registeredActor(pDID, registryContract) ownerOfDID(pDID, msg.sender, registryContract){ 
        //proposal not sealaed
        require(proposals[pid].pStatus==ProposalStatus.ACTIVE);

        require(PoliceLib.compareStr(proposals[pid].proposerDID,pDID),"Only proposer can withdraw proposal");

        
        //for simplicity, ethernet account address is used as did keys
        
        //release locked stake of proposer
        msg.sender.transfer(proposals[pid].lockedStake);
        
        proposals[pid].pStatus==ProposalStatus.WITHDRAWN;
        //seal related proposal contract    
        //proposalContracts[pid].call(bytes4(keccak256("seal")));
        proposalContracts[pid].call(abi.encodeWithSignature("freeze()"));
        
    }
    
    //called by Proposal Contract who is triggered by a timeSevice call this or manual call
    function finalizeProposal (uint pid, ProposalStatus result) public { //onlyItsPropoer(pid){

        require((proposalContracts[pid]==msg.sender), "Caller ProposalContract is unknown");
        //do closing actions
        
        proposals[pid].pStatus = result;
        
        bytes memory policyBytes =  proposals[pid].policy;
        //Parse policy
        uint id;
        string memory pTitle;
        string memory description;
        bytes memory policy;   // encoded as policy sytnax supported by the Platform
        uint date;
        (id, pTitle, description, policy, date) = abi.decode(policyBytes,(uint,string,string,bytes, uint));
        
        
        if (result == ProposalStatus.ACCEPTED){ 
            policies[pid] = Policy(id, pTitle, description, policy,date);
             //trigger policy activation/deactivation
             if(!PoliceLib.compareStr(policy,"")){
                 //create a new policy
                 deployPolicy(policy);
                 
             }else{
                 //remove existing policy
                 undeployPolicy(id);
             }
        }
        
        // Unlock stake of proposer
        (bool success, bytes memory data) = registryContract.call(abi.encodeWithSignature("getAddress(string)", proposals[pid].proposerDID));
        (address  adr) = abi.decode(data,(address));
        
        //address(adr).transfer(proposals[pid].lockedStake);
        //require(address(adr).send(proposals[pid].lockedStake));
        address(adr).call.value(proposals[pid].lockedStake).gas(20317);
        //eth.getBalance(adr) += proposals[pid].lockedStake;
        
        
        //seal related proposal contract    
        proposalContracts[pid].call(abi.encodeWithSignature("freeze()"));
    }    
    
    
    // retrieve list of proposals
    /**
    function getAllProposals() public view returns (Proposal[] memory){
        Proposal[] memory ret = new Proposal[](proposalCount);
        for (uint i = 0; i < proposalCount; i++) {
            ret[i] = proposals[i];
        }
        return ret;
    }*/

}
