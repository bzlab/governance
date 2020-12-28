/* GNU GPL 3.0-License-Identifier
 * Police Governance Framework  Copyright (C) 2020  Taner Dursun
 *   This program comes with ABSOLUTELY NO WARRANTY
 *   This is free software, and you are welcome to redistribute it
 *   by referencing its original source.
 *      Istanbul Technical University and TUBITAK BILGEM Blockchain Research Lab
 *   
 *
 * @title Proposal Contract
 * @author Taner Dursun <tdursun@gmail.com>
 *
 * @dev Encapsulates all decision making process related to a single Chane Proposal 
 *      Uses the RegistryContract during evaluation of votes casted by fovernance actors.
 *      Informs the VotingContract for the end of the decision voting.
 *      This Contract was developed for the Police On-Chain blockchain governance project.
 */
 
pragma solidity ^0.5.3;
import "./PoliceLib.sol";
import "./PoliceContract.sol";


contract ProposalContract{
    
    enum CredentialType{ACCOUNT_POSSESSION, MINERSHIP, ROLE, DELEGATION}

    bool frozen = false; //voting in progress
    uint constant MIN_MINER_ACCOUNT_BALANCE = 10000000 wei;
    uint constant MIN_NUM_OF_EXCHANGE_ACCOUNT = 100000;
    uint constant MIN_EXCHANGE_TOTAL_BALANCE= 1000000000 wei;
    uint constant ELIGIBLE_BALANCE_BACKWARD_WINDOW=1000; //number of block
    
        //vote weights per roles
    uint constant WEIGHT_FOUNDER = 1;
    uint constant WEIGHT_INIT_DEV = 1;
    uint constant WEIGHT_USER = 1;
    uint constant WEIGHT_MINER = 1;
    uint constant WEIGHT_EXCHANGE_OWNER = 1;
    uint constant WEIGHT_EXCHANGE_USER = 1;
    
    
    //VotingHandlerContract handler;
    address votingHandlerContract;
    address registryContract;
    //Proposal public prop;  //proposal details
    
    //make sure that caller is a registered actor
    modifier registeredActor(string memory did) {
      (bool success, bytes memory data) = registryContract.call(abi.encodeWithSignature("isRegistered(string)", did));
      //registryContract.call(bytes4(keccak256("isRegistered(string)")),did);
      (bool  registered) = abi.decode(data,(bool));
      if (registered) {
         _;
      }
    }

    modifier ownerOfDID(string memory did, address adr) {
        //msg.sender available ise adr parametresne gerek yok
      //bool sonuc = registryContract.call(bytes4(keccak256("checkAddress(string,address)")),did, adr);
      (bool success, bytes memory data) = registryContract.call(abi.encodeWithSignature("checkAddress(string,address)", did, adr));
      bool  sonuc = abi.decode(data,(bool));
      
      if (sonuc) {
         _;
      }
    }
   
    modifier notSealed() {
      if (frozen==false) {
         _;
      }
    }
        struct AccountProof{
        address accountAdr;
        bytes proofOfPossession;  // sign(PID)
    }
    
    struct VCCommon{
        CredentialType cType;
        string issuedByDID; //issuer
        string issuedToDID; //subject of VC
        bytes signature;
        //attributes
        //bytes body; 
    }
    
    struct VCRole{
        VCCommon common;
        //attributes
        PoliceLib.ActorType role; 
    }
    
    struct VCAccountPossession{
        VCCommon common;
        //attributes
        address[] addresses; 
        bytes32[] proofs; //a signature applied for each account (signature(proposalID))
    }
    
    struct VCMinership{
        VCAccountPossession possession;
        //attributes
        address[] cbAddresses; //coinbase addresses
        uint[] blockNumbers;
        bytes32[] cbProofs; //a signature applied for each account (signature(proposalID))
    }
    struct VCDelegation{
        VCCommon common;
        //attributes
        address[] addresses; 
        bytes32[] proofs; //a signature for each account 
    }
    
    struct Vote{
        string voterDID;
        PoliceLib.DecisionType decision; 
        uint vDate;  // timestamp
        bytes credentials; //Struct inheritance not supported. So we use pirimitive type 

        string signature; // signature cretaed by proposer for all fields above
        bytes32 vcProposalBinding;  // bind VC to this proposal to prevent replay attacks
        uint index;  //index num in votes array
        
        //fields derived i.e. filled by this contract 
        PoliceLib.ActorType role;    // verified role of voter 
        uint eligibleBalance;
    }
    
    
    //Vote[] votes;  //accumulates votes submitted: (voter, vote, role, weight, accounts)
    mapping (string => uint) voteIndeks; // accumulates votes submitted: (voter, vote, role, weight, accounts)
    Vote [] votes; // accumulates votes submitted: (voter, vote, role, weight, accounts)
    
    mapping(address=> bool) accountsUsedforVote;   //account address, true
    string[] public voters;
    
    //FOLLOWS HANDLING
    struct Expert {
        string did;
        uint expertListIndex; // needed to delete a "One"
        // One Folowed has many Follows
        string[] followerKeys;    //followers' dids   for iteration purpose
        mapping(string => uint) followerListIndeks;  // dollower's did --> followerKeys.index
        // more app data
    }
    mapping(string => Expert) public experts;
    string[] public expertList;
    
    struct Follow{
        string followedDID;
        string followerDID;
        bytes credentials;
        PoliceLib.DecisionType backupVote;  //use this if followed wont vote
        address [] accountUsed;  //<-- bunlar da VCs içinde var. VC doğrulandığında, kolaylık olsun diye buraya yazılabilir.
        uint eligibleBalance; //created by system
        PoliceLib.ActorType role; //created by system
        uint date;  // timestamp
        //
        //ActorType role;  <-- This info is included in VCs. When VC is verified, it can be store here for easy access puprpose.
        bool valid;
        uint followersIndex; //followerList.index for this follow
    }
    mapping(string => Follow) public followers;  //follower-->Follow
    string[] public followerList;
    
    //mapping(string => Follow[]) followOrders;  //followed expert's did and follow orders for her. Bu sekilde organize etmemize gerek yok gibi.
    //mapping(address=> string) followAccountsUsed; //account-address, owner-did
    //string [] followIterator;
    uint propID;

    // CONSTRUCTOR
    constructor(uint proposalID, address vhc, address rc) public{
        votingHandlerContract = vhc;
        registryContract = rc;
        propID = proposalID;
    }
    

    // VOTE
    function submitVote(string memory voterDID, PoliceLib.DecisionType vote, uint vDate, 
                        bytes memory credentials, string memory signature, bytes32 binding) public 
                    registeredActor(voterDID) 
                    ownerOfDID(voterDID, msg.sender)  //check Vote issued by actor herself (registered address must be used)
                    notSealed{
                        
        string memory voterDIDx=voterDID;
        PoliceLib.DecisionType votex = vote;
        uint vDatex = vDate; 
        bytes memory credentialsx=credentials;
        string memory signaturex=signature;
        bytes32 bindingx=binding;
                        
        //ensure that the voter didn’t vote before. Overriding his vote would be possible
        require((voteIndeks[voterDIDx]!=votes[voteIndeks[voterDIDx]].index),"Already voted");
        
        //verify that the VCs are bound to this voting (against replay attacks) 
        // vote:vcProposalBinding must be equal to hash (proposalID || v.verifiableCredentials)
        require(verifyBinding(bindingx, credentialsx),"Credentials are not produced for this proposal, specifically");

        // verify signature of vote <-- this step can be ignored due to equivalent contol at method modifier of ownerOfDID
        //caller is the Voter specified in the Vote

        //verify VCs consistency and adequacy (if any, VCDelagations are also processed inside)
        bool parseOK=false;
        uint eligibleBalance=0;
        address[] memory usedAccounts; //!!!kullanmadik. Zira parseEvaluateVerifiableCredentials, bu adresleri zaten isaretliyor
        PoliceLib.ActorType verifiedRole;
        
        //calculate eligible balance of actor from VCAcconts presented
        (parseOK, verifiedRole, usedAccounts, eligibleBalance) = parseEvaluateVerifiableCredentials(voterDIDx, credentialsx);
 
        // delete follow order by this actor, if any
        unfollow(voterDIDx);
        
        
        Vote memory v = Vote(voterDIDx,
                            votex,
                            vDatex,
                            credentialsx,
                            signaturex,
                            bindingx,
                            votes.length,
                            verifiedRole,
                            eligibleBalance);
                            //Vote({ id: i, rol: 0 .....});
        // store vote including eligible balance of both voter and [if any] delegator(s)
        uint newLen = votes.push(v);
        voteIndeks[v.voterDID] = newLen-1;

        //vote for followers
        require(hasAnyFollow(v.voterDID));
        
        uint totalFollowedWeight=0;
        totalFollowedWeight = processFollow(v.voterDID, v.decision);
        // Update reputation value of the followed actor
        registryContract.call(abi.encodeWithSignature("updateReputation(string,uint)", v.voterDID,totalFollowedWeight));
        
    }
    
    function processFollow(string memory did, PoliceLib.DecisionType expertDecision) 
      private
      returns(uint)
    {
        //Stopping condition
        //follows of me
        uint fCount = experts[did].followerKeys.length; //TODO If she is not unlinked even though she has voted, this control is wrong
        if(fCount==0){
            //process Follow
            Follow memory follow = followers[did];
            
            //if it couldn't find itself then exit and break the recursive call chain
            if(!follow.valid) return 0;
            
            //Vote memory vf = Vote({voterDID:did}); 
            Vote memory vf = Vote(did,
                            expertDecision,
                            now,
                            follow.credentials,
                            "0x0",//empty signautre
                            "0x0", //empty binding
                            votes.length,
                            follow.role,
                            follow.eligibleBalance);
            
            uint newLen = votes.push(vf);
            voteIndeks[did] = newLen-1;

            //update reputation of Expert
            follow.valid=false;
            //break link? between follow---followed  is required?
            // delete from the Many table
            uint rowToDelete = follow.followersIndex;
            string memory keyToMove = followerList[followerList.length-1];
            followerList[rowToDelete] = keyToMove;
            followerList.length--;
            
            // we ALSO have to delete this key from the list in the ONE
            string memory oneId = follow.followedDID; 
            rowToDelete = experts[oneId].followerListIndeks[did];
            
            keyToMove = experts[oneId].followerKeys[experts[oneId].followerKeys.length-1];
            experts[oneId].followerKeys[rowToDelete] = keyToMove;
            
            experts[oneId].followerListIndeks[keyToMove] = rowToDelete;// update index of moved Item
            experts[oneId].followerKeys.length--;

            return vf.eligibleBalance*getWeight(vf.role);
        }else{
            //for each follower of did process follower recursively
            uint totalFollowedWeight = 0;
            for (uint i=0; i<fCount; i++) {
                string memory fdid = experts[did].followerKeys[i];
                totalFollowedWeight = totalFollowedWeight + processFollow(fdid, expertDecision);
            }
            return totalFollowedWeight;
        }
    }
    

    function hasAnyFollow(string memory did) 
      private
      view
      returns(bool) 
    {
        if(expertList.length==0) return false;
        string memory tmp = expertList[experts[did].expertListIndex];
        return PoliceLib.compareStr(tmp,did);
    }
    
    
    //THINK actor would be able both to vote himself with some of his accounts and to follow one/mor expert(s) with his other accounts
    //For simplicity this feature is not allowed. Either vote himself or follow. And Only one FollowOrder is allowed for each actor
    function follow (string memory followedDID, string memory followerDID, bytes memory credentials, PoliceLib.DecisionType backupVote) public 
                        registeredActor(followerDID)
                        ownerOfDID(followerDID, msg.sender)
                        notSealed{
        //These are for walkaround of "CompilerError: Stack too deep, try removing local variables"
        string memory followedDIDx = followedDID;
        string memory followerDIDx = followerDID;
        bytes memory credentialsx=credentials;
        PoliceLib.DecisionType backupVotex = backupVote;
        
        //ensure that caller didn’t cast a vote before
        require((voteIndeks[followerDIDx]!=votes[voteIndeks[followerDIDx]].index),"Already voted. Follow is not possible");

        //ensure that followed != follower
        require(PoliceLib.compareStr(followerDIDx,followedDIDx));//hata string compare

        //ensure follow once
        require(!followers[followerDIDx].valid,"Already has a follow order");
        //remove other follow order of the caller (if any)
        
        //Verify VC presented by Follower
        //confirm content of VCs and ensure that follower has possessions of accounts and verify role of the follower
                //verify VCs consistency and adequacy (if any, VCDelagations are also processed inside)
        bool parseOK=false;
        uint eligibleBalance=0;
        address[] memory usedAccounts;
        PoliceLib.ActorType verifiedRole;
        
        //calculate eligible balance of actor from VCAcconts presented
        (parseOK, verifiedRole, usedAccounts, eligibleBalance) = parseEvaluateVerifiableCredentials(followerDIDx, credentialsx);


        //if the Expert already voted, convert this follow to a Vote (So, should we still create a follow relationship or update Expert.reputation?)
        if((voteIndeks[followedDIDx]!=votes[voteIndeks[followedDIDx]].index)){//already voted
            //Vote this actor too, recursively
            uint totalFollowedWeight=0;
            totalFollowedWeight = processFollow(followerDIDx, votes[voteIndeks[followedDIDx]].decision);
            // Update reputation value of the followed actor
            registryContract.call(abi.encodeWithSignature("updateReputation(string,uint)", followedDIDx, totalFollowedWeight));
            
            //THINK For statistical purpose, Should we still add the follows record and make its status false?

        }else{
            //Create Follow Order
            if(!hasAnyFollow(followedDIDx)){ //not exist, first time then create it
                Expert memory fd = Expert(followedDIDx,
                                        0, //expertListIndex  to be updated
                                        new string[](0) //followerKeys
                                        //new mapping(string => uint) //followerListIndex
                                    ); 

                fd.expertListIndex = expertList.push(followedDIDx)-1;   //ATTENTION, push does not return length any more?
                experts[followedDIDx]=fd;
            }
            
            //create one-to-many relation  EXPERT-FOLLOW
            // We also maintain a list of "Many" that refer to the "One", so ... 
            experts[followedDIDx].followerListIndeks[followerDIDx] =  experts[followedDIDx].followerKeys.push(followerDIDx) - 1;
            //add into experts[i].followerKey
            
            Follow memory f = Follow(followedDIDx, 
                                    followerDIDx, 
                                    credentialsx, 
                                    backupVotex,
                                    usedAccounts,  //put this to use in any case of unfollow
                                    eligibleBalance,
                                    verifiedRole,
                                    now,
                                    true,
                                    followerList.push(followerDIDx)-1
                                    );

            followers[followerDIDx] = f;
            followerList.push(followerDIDx);
        }

    }
    
    //cancel follow issued by this DID
    function unfollow (string memory did) public 
                                registeredActor(did)
                                ownerOfDID(did, msg.sender)
                                notSealed{
        string memory didx = did;
        //ensure that caller has a valid follow to cancel
        require(followers[did].valid);  //existing follow
        //OR
        require(followerList.length==0);
        require(PoliceLib.compareStr(followerList[followers[did].followersIndex],did));

        //ensure that caller didn’t cast a vote before
        require((voteIndeks[did]!=votes[voteIndeks[did]].index),"Already voted. Canceling Follow is not possible");
        
        //cancel this follow request
        address[] memory tmp = followers[did].accountUsed;
        
        //delete flags related to accountsUsedforVote from mapping
        uint arrayLength=tmp.length;
        for (uint i=0; i<arrayLength; i++) {
            accountsUsedforVote[tmp[i]]=false;
            delete accountsUsedforVote[tmp[i]];
        }
        
        //unlink Follow and Expert
        // delete from the Follow table (MANY)
        uint rowToDelete = followers[did].followersIndex;
        string memory lastElementToMove = followerList[followerList.length-1];
        followerList[rowToDelete] = lastElementToMove;
        followerList.length--;
        
        // we ALSO have to delete this key from the list in the Expert (ONE)
        string memory oneId = followers[didx].followedDID; 
        rowToDelete = experts[oneId].followerListIndeks[didx];
        
        lastElementToMove = experts[oneId].followerKeys[experts[oneId].followerKeys.length-1];
        experts[oneId].followerKeys[rowToDelete] = lastElementToMove;
        
        experts[oneId].followerListIndeks[lastElementToMove] = rowToDelete;// update indekx of moved Item
        experts[oneId].followerKeys.length--;
        
        followers[didx].valid=false;
        delete followers[didx]; //mapping icermeyeni silmek
    }


    function closeVoting ( ) public notSealed{
        //check closing conditions (time, participation)
        
        //take the remaining follow requests into account
        //check whether followed expert Voted
        uint fCount = followerList.length;
        for (uint i=0; i<fCount; i++) {
            Follow memory flw = followers[followerList[i]];
            if(!flw.valid) continue; //not converted to Vote
            
            //use follow.backupVote
            //In fact Fa-->Fb-->Fc    all of them shall use backup Vote of the Fc
            //TODO
            Vote memory v = Vote(flw.followerDID,
                            flw.backupVote,
                            now,
                            "", //new byte[0] //flw.credentials, //not important, use as emtyp
                            "0x",//signature
                            0x0, //binding
                            votes.length,
                            flw.role,
                            flw.eligibleBalance);
                            //Vote({ id: i, rol: 0 .....});
            uint newLen = votes.push(v);
            voteIndeks[flw.followerDID] = newLen-1;
        }
        
        // count the votes (by weighting each vote with role, balance) in Votes and calculate decision of ballot
        PoliceLib.ProposalStatus result;     

        uint arrayLength = votes.length;
        uint totalYes;
        uint totalNo;
        uint totalAbstain;
        for (uint i=0; i<arrayLength; i++) {
            Vote memory v = votes[i];
            if(v.decision==PoliceLib.DecisionType.YES){
                totalYes= totalYes + v.eligibleBalance*getWeight(v.role); //use weights
            }
            if(v.decision==PoliceLib.DecisionType.NO){
                totalNo= totalNo + v.eligibleBalance*getWeight(v.role); //use weights
            }
            if(v.decision==PoliceLib.DecisionType.ABSTAIN){
                totalAbstain= totalAbstain + v.eligibleBalance*getWeight(v.role); //use weights
            }
            
        }
        
        if((totalYes>totalNo) && (totalYes>totalAbstain)){
            result = PoliceLib.ProposalStatus.ACCEPTED;
        }else if((totalNo>totalYes) && (totalNo>totalAbstain)){
            result = PoliceLib.ProposalStatus.REJECTED;     
        }else{
            //handle sub scenarios
            result = PoliceLib.ProposalStatus.REJECTED;     
        }
        // trigger VotingContract and forward the result of ballot
        //votingHandlerContract.call(bytes4(keccak256("finalizeProposal(uint,ProposalStatus)")),propID, result);
        (bool success, bytes memory data) = registryContract.call(abi.encodeWithSignature("finalizeProposal(uint,ProposalStatus)", propID, result));

    }
    
    function getWeight(PoliceLib.ActorType t) public view returns (uint){
        if (t==PoliceLib.ActorType.FOUNDER) return WEIGHT_FOUNDER;
        if (t==PoliceLib.ActorType.INITIAL_DEVELOPER) return WEIGHT_INIT_DEV;
        if (t==PoliceLib.ActorType.MINER) return WEIGHT_MINER;
        if (t==PoliceLib.ActorType.USER) return WEIGHT_USER;
        if (t==PoliceLib.ActorType.EXCHANGE_OWNER) return WEIGHT_EXCHANGE_OWNER;
        if (t==PoliceLib.ActorType.EXCHANGE_USER) return WEIGHT_EXCHANGE_USER;
        return 0;
    }
    

    function freeze() public notSealed{
        //only VotingHandlerContract can freeze this contract
        require(votingHandlerContract==msg.sender);
        frozen = true;
    }
    
    struct LocalVars {
        string didx;
        bytes credentialsx;
        uint32 vcCount;
        uint32 ptr;
        uint totalEligibleBalance;
        address[] validatedAccounts;// = new address[]();

    }

    // totalVCCount(4 byte) || [ VClen(4 byte) || VCtype(1 byte) || VC body (vcLen bytes) ]*  
    // parse VCs, evaluate validity, calculate role and eligible balances
    function parseEvaluateVerifiableCredentials(string memory did, bytes memory credentials) 
            internal /*view**/ returns (bool, PoliceLib.ActorType,  address[] memory, uint){
        LocalVars memory vars;
        vars.didx = did;
        vars.credentialsx=credentials;
        vars.vcCount=PoliceLib.toUint32(credentials,0);
        //vars.ptr=4;
        //string memory didx = did;
        //bytes memory credentialsx = credentials;
        //uint32 vcCount = PoliceLib.toUint32(credentials,0);
        uint32 ptr = 4;
        VCRole memory vcrole;
        VCDelegation [] memory vcdelegations = new VCDelegation[](vars.vcCount);  //in fact length is smaller than vcCount. But we don't know, yet.
        uint vcDelegationsCount = 0;
        VCMinership memory vcminership;
        VCAccountPossession memory vcownership;
        
        for (uint i=0; i<vars.vcCount; i++) { //parse each VC
            uint32 vcLen = PoliceLib.toUint32(vars.credentialsx,ptr);  //go forward 4  
            CredentialType vcTypeC = CredentialType(PoliceLib.toUint8(vars.credentialsx,ptr+1)); //go forward 1
            ptr=ptr+5; //go ahead (size of VCLen + VCType fields) = 5"
            bytes memory vcBytes = PoliceLib.slice(vars.credentialsx, ptr, vcLen);
            
            string memory issuedByDID; //issuer
            string memory issuedToDID; //subject of VC
            bytes memory signature;

            if(vcTypeC==CredentialType.ROLE){  //or vcType == uint8(CredentialType.ROLE)
                PoliceLib.ActorType role;
                (, issuedByDID, issuedToDID, signature, role) = abi.decode(vcBytes, (CredentialType, string,string, bytes, PoliceLib.ActorType));
                //require(PoliceLib.compareStr(didx, issuedToDID),"VC Role not issued for this actor");
                //issuedToDID = didx;
                vcrole = VCRole(VCCommon(vcTypeC, issuedByDID,issuedToDID,signature),role);
                
                require(verifyVCRole(issuedByDID,issuedToDID,signature,role),"Role cannot be verified"); //ensure this VCRole issued to the caller of this function
            }else if (vcTypeC==CredentialType.ACCOUNT_POSSESSION){
                //secenek1
                address[] memory accounts;
                bytes32[] memory proofs;
                //secenek2
                //bytes[] proofs; //bunu further parsing to address + bytes32 (sha3(pid))
                
                (, issuedByDID, issuedToDID, signature, accounts, proofs) = abi.decode(vcBytes, (CredentialType, string,string, bytes, address[],bytes32[]));
                //parsedVCs.push(new VCCommon(cType, issuedByDID,issuedToDID,signature));
                vcownership = VCAccountPossession(VCCommon(vcTypeC, issuedByDID,issuedToDID,signature),accounts, proofs);
            }else if (vcTypeC==CredentialType.DELEGATION){//Ayni bir actor icin n adet olabilir
                //secenek1
                address[] memory accounts;
                bytes32[] memory proofs;
                //secenek2
                //bytes[] proofs; //bunu further parsing to : address + bytes32 (sha3(pid))
                
                (, issuedByDID, issuedToDID, signature, accounts, proofs) = abi.decode(vcBytes, (CredentialType, string,string, bytes, address[],bytes32[]));
                //parsedVCs.push(new VCCommon(cType, issuedByDID,issuedToDID,signature));
                vcdelegations[vcDelegationsCount]=VCDelegation(VCCommon(vcTypeC, issuedByDID,issuedToDID,signature),accounts,proofs );
                vcDelegationsCount++;
            }else if (vcTypeC==CredentialType.MINERSHIP){
                //secenek1
                address[] memory accounts;
                bytes32[] memory proofs;
                address[] memory cbAccounts;
                uint[] memory blockNumbers;
                bytes32[] memory cbProofs;
                //secenek2
                //bytes[] proofs; //bunu further parsing to address + bytes32 (sha3(pid))
                
                (, issuedByDID, issuedToDID, signature, accounts, proofs, cbAccounts, blockNumbers, cbProofs) = abi.decode(vcBytes, (CredentialType, string,string, bytes, address[],bytes32[],address[], uint[], bytes32[]));
                //parsedVCs.push(new VCCommon(cType, issuedByDID,issuedToDID,signature));
                vcminership= VCMinership(VCAccountPossession(VCCommon(vcTypeC, issuedByDID,issuedToDID,signature),accounts,proofs), cbAccounts, blockNumbers, cbProofs);  
            }else{
                revert("Unknown VC type");
            }
            ptr=ptr+vcLen;
            
        }//for
        
        //Every Voter must provide VCRole credential except FOUNDERs, INITDEVs and DEVs
        (, bytes memory data) = registryContract.call(abi.encodeWithSignature("isFounder(string)",vars.didx));
        (bool  result) = abi.decode(data,(bool));
        if(!result){//founder
            (, data) = registryContract.call(abi.encodeWithSignature("isInitDev(string)",vars.didx));
            (result) = abi.decode(data,(bool));
            if(!result){//initDev"
                (, data) = registryContract.call(abi.encodeWithSignature("isDev(string)",vars.didx));
                (result) = abi.decode(data,(bool));
                if(!result){//Dev
                    require(vcrole.common.cType == CredentialType.ROLE); // ensure that role VC exists
                }else{
                    vcrole = VCRole({common:VCCommon(CredentialType.ROLE,"0x0","0x0","0x0"), role: PoliceLib.ActorType.DEVELOPER});
                }
            }else{
                vcrole = VCRole({common:VCCommon(CredentialType.ROLE,"0x0","0x0","0x0"), role: PoliceLib.ActorType.INITIAL_DEVELOPER});
            }
        }else{
            vcrole = VCRole({common:VCCommon(CredentialType.ROLE,"0x0","0x0","0x0"), role: PoliceLib.ActorType.FOUNDER});
        }
        
        //Evaluate parsed VCs per Role except VCRole credential which is already evaluated above
        //to Verify credentials' complete, genuine and consistent with other VCS and role

        //uint totalEligibleBalance =0;
        vars.totalEligibleBalance = 0;
        //address[] memory validatedAccounts;// = new address[]();
        bool valid;
        uint b;
        address[] memory aa;       
        if(vcrole.role == PoliceLib.ActorType.USER ){
            require(vcownership.common.cType==CredentialType.ACCOUNT_POSSESSION,"Account Possession credential must be provided");
            
            bytes memory data1 = abi.encode(CredentialType.ACCOUNT_POSSESSION, vars.didx, vcownership.common.issuedByDID, vcownership.addresses, vcownership.proofs); 
            require(verifyVCSignature(data1, vcownership.common.issuedByDID,vcownership.common.signature),"Signature is not correct");
            
            (valid, aa, b)=verifyVCAccountPossession(vcownership.addresses, vcownership.proofs);
            require(valid);
            vars.totalEligibleBalance = vars.totalEligibleBalance + b;
            vars.validatedAccounts = PoliceLib.concatenateArrays(vars.validatedAccounts,aa);
            
        }else if(vcrole.role == PoliceLib.ActorType.EXCHANGE_OWNER ){
            require(vcownership.common.cType==CredentialType.ACCOUNT_POSSESSION,"Account Possession credential must be provided");
            
            bytes memory data1 = abi.encode(CredentialType.ACCOUNT_POSSESSION, vars.didx, vcownership.common.issuedByDID, vcownership.addresses, vcownership.proofs); 
            require(verifyVCSignature(data1, vcownership.common.issuedByDID,vcownership.common.signature),"Signature is not correct");

            (valid, aa, b)=verifyVCAccountPossession(vcownership.addresses, vcownership.proofs);
            require(valid);
            
            //ensure that EO has private keys for enough number of accounts with enough balance
            require(b>MIN_EXCHANGE_TOTAL_BALANCE,"Exchange balance does not fit minimum requirements");
            require(vcownership.addresses.length>MIN_NUM_OF_EXCHANGE_ACCOUNT,"Exchange account number does not fit minimum requirements");
            
            vars.totalEligibleBalance = vars.totalEligibleBalance + b;
            vars.validatedAccounts = PoliceLib.concatenateArrays(vars.validatedAccounts,aa);

        }else if(vcrole.role == PoliceLib.ActorType.EXCHANGE_USER ){
            //A valid EO issued AccountPossession + VCDelegation (evaluated belowe)
            require(vcownership.common.cType==CredentialType.ACCOUNT_POSSESSION,"Account Possession credential must be provided");
            
            bytes memory data1 = abi.encode(CredentialType.ACCOUNT_POSSESSION, vcownership.common.issuedToDID, vcownership.common.issuedByDID, vcownership.addresses, vcownership.proofs); 
            require(verifyVCSignature(data1, vcownership.common.issuedByDID,vcownership.common.signature),"Signature is not correct");

            (valid, aa, b)=verifyVCAccountPossession(vcownership.addresses, vcownership.proofs);
            require(valid);
            //ignore the aa, since it is used just for the proof of ExchangeOwnership
            
            //ensure that EO has private keys for enough number of accounts with enough balance
            require(b>MIN_EXCHANGE_TOTAL_BALANCE,"Exchange balance does not fit minimum requirements");
            require(vcownership.addresses.length>MIN_NUM_OF_EXCHANGE_ACCOUNT,"Exchange account number does not fit minimum requirements");

            //EO issued VCRole to voterDID
            require(PoliceLib.compareStr(vcownership.common.issuedByDID,vcrole.common.issuedByDID),"VC dependency is not correct (Role and AccountPossession)");
            
            //EO issued VCDelegation?AccountPossession to voterDID
            require(vcdelegations.length>0,"Delegation credential must be provided");
            uint len = vcdelegations.length;
            for (uint i=0; i<len; i++) { //
                require(PoliceLib.compareStr(vcownership.common.issuedByDID,vcdelegations[i].common.issuedByDID),"VC dependency is not correct (Delegation and AccountPossession)");
            }
            //Ensure that Delegated VC.elegibleBalance must be > ....
            //TODO
            //Accounts were not used for voting to this proposal (OR TO ANY OTHER PROPOSAL?)
        }else if(vcrole.role == PoliceLib.ActorType.MINER ){
            require(vcminership.possession.common.cType==CredentialType.MINERSHIP,"Minership Account Possession credential must be provided");

            bytes memory data1 = abi.encode(CredentialType.ACCOUNT_POSSESSION, vars.didx, vcminership.possession.common.issuedByDID, 
                                            vcminership.possession.addresses, vcminership.possession.proofs, 
                                            vcminership.cbAddresses, vcminership.blockNumbers, vcminership.cbProofs); 
            require(verifyVCSignature(data1,vcminership.possession.common.issuedByDID, vcminership.possession.common.signature),"Signature is not correct");
//          
            (valid, aa, b)=verifyVCMinership(
                                            vcminership.possession.addresses, vcminership.possession.proofs, 
                                            vcminership.cbAddresses, 
                                            vcminership.blockNumbers, 
                                            vcminership.cbProofs);
            require(valid);
            vars.totalEligibleBalance = vars.totalEligibleBalance + b;
            vars.validatedAccounts = PoliceLib.concatenateArrays(vars.validatedAccounts,aa);
            
        }else if(vcrole.role == PoliceLib.ActorType.DEVELOPER ){
            //verify that actor’s role credential was issued by a Founder
            //No need to check. This check was already performed above. Since Developers are registered into RegistryContract so they are not supposed to provide a VCRole
        }else{
            revert("unsupported role");
        }
        
        //evaluate VCDelegations, if any

        for (uint i=0; i<vcDelegationsCount; i++) { //
            (valid, aa, b)=verifyVCDelegation(vcdelegations[i].common.issuedByDID, vars.didx,vcdelegations[i].common.signature, 
                                                vcdelegations[i].addresses, 
                                                vcdelegations[i].proofs);
            require(valid);
            vars.totalEligibleBalance = vars.totalEligibleBalance + b;
            vars.validatedAccounts = PoliceLib.concatenateArrays(vars.validatedAccounts,aa);
        }
        //In fact, accounts used can be added to the global accountsUsedforVote list. For now, in the VCxVerify functions, they are added to the global list.
        //for each item in validatedAccounts accountsUsedforVote[validatedAccounts[i]]=true;
        //TODO
        return (true, vcrole.role, vars.validatedAccounts, vars.totalEligibleBalance);
    }
    
    
    function verifyBinding(bytes32 binding, bytes memory credentials ) internal view returns (bool)
    {
        //assert (vote:vcProposalBinding = hash (proposalID || encode(v.verifiableCredentials)) )
        bytes memory data = abi.encode(propID, credentials); 
        bytes32 hash = keccak256(data);
        return (hash == binding);
    }
    
    function verifyVCSignature(bytes memory data1, string memory didIssuer, bytes memory signature) internal returns (bool)
    {
        bytes32 hash = keccak256(data1);
        
        (bool success, bytes memory data) = registryContract.call(abi.encodeWithSignature("getAddress(string)",didIssuer));
        (bool b, address a) = abi.decode(data,(bool, address));
        require(b, "Actor not found");
        bool sonuc = PoliceLib.verify(a, hash, signature);
        return sonuc;
    }
    
    function verifyVCRole(string memory didIssuer, string memory didSubject, bytes memory signature, PoliceLib.ActorType role) internal returns (bool)
    {
        bytes memory data1 = abi.encode(CredentialType.ROLE, didSubject, didIssuer, role); 
        return verifyVCSignature(data1, didIssuer, signature);
    }
    
    
    
    function verifyVCAccountPossession( address[] memory addresses, bytes32[] memory proofs) internal returns (bool, address[] memory, uint)
    {
        address [] memory validAccounts;
        
        //now evaluate validity each account proof
        require(addresses.length==proofs.length, "Address list is empty");
        uint len = addresses.length;
        uint eBalance = 0;
        for (uint i=0; i<len; i++) { //
            bytes memory data = abi.encode(addresses[i],propID);
            bytes32 hash = keccak256(data);
            bool psonuc = PoliceLib.verify(addresses[i], hash, abi.encodePacked(proofs[i]));
            //require(psonuc, "address not verified"); //do not stop, just ignore this account
            if(psonuc){
                //ensure that this account not used and tag it as used now
                //require(!accountsUsedforVote[addresses[i]],"account used before");
                if(!accountsUsedforVote[addresses[i]]){
                    eBalance = eBalance + eligibleBalance(addresses[i]);
                    accountsUsedforVote[addresses[i]]=true;
                    //validAccounts.push(addresses[i]);
                    address[] memory tmp = new address[](1);
                    tmp[0] = addresses[i];
                    validAccounts= PoliceLib.concatenateArrays(validAccounts, tmp);
                }else{
                    //ignore this account
                }
            }
        }
        return (true, validAccounts, eBalance);
    }
    
    function verifyVCMinership(  
                address[] memory addresses, bytes32[] memory proofs, 
                address[] memory cbAddresses, uint[] memory blockNumbers, bytes32[] memory cbProofs) 
                internal returns (bool, address[] memory,uint)
    {
        address [] memory validAccounts;
        //now evaluate validity each account proof
        require(cbAddresses.length==cbProofs.length, "Coinbase Address list is empty");
        uint len = cbAddresses.length;
        uint eBalance = 0;
        for (uint i=0; i<len; i++) { //
            bytes memory data = abi.encode(cbAddresses[i],propID);
            //bytes32 hash = ;
            bool psonuc = PoliceLib.verify(cbAddresses[i], keccak256(data), abi.encodePacked(cbProofs[i]));
            require(psonuc, "coinbase address not verified");
            
            //ensure that this account is really a miner account
            //TODO
            //block.coinbase(blockNumbers[i]);
            //blockhash(blockNumbers[i]); <-- replace in bytecode
            //if not revert("Account provided is not a coinbase account");
            
            //ensure that this account not used and tag it as used now
            if(!accountsUsedforVote[cbAddresses[i]]){
                eBalance = eBalance + eligibleBalance(cbAddresses[i]);
                accountsUsedforVote[cbAddresses[i]]=true;
                
                //validAccounts.push(cbAddresses[i]);
                address[] memory tmp = new address[](1);
                tmp[0] = cbAddresses[i];
                validAccounts= PoliceLib.concatenateArrays(validAccounts, tmp);
            }
        }
        require(eBalance>MIN_MINER_ACCOUNT_BALANCE, "Miner account does not have enough stake");
        
        //evaluate ordinary accounts belonging to the miner, if presented
        len = addresses.length;
        for (uint i=0; i<len; i++) { //
            bool psonuc = PoliceLib.verify(addresses[i], keccak256(abi.encode(addresses[i],propID)), abi.encodePacked(proofs[i]));
            require(psonuc, "address not verified");
            
            //ensure that this account not used and tag it as used now
            if(!accountsUsedforVote[addresses[i]]){
                eBalance = eBalance + eligibleBalance(addresses[i]);
                accountsUsedforVote[addresses[i]]=true;
                //validAccounts.push(addresses[i]);
                address[] memory tmp = new address[](1);
                tmp[0] = addresses[i];
                validAccounts= PoliceLib.concatenateArrays(validAccounts, tmp);
                
            }
        }
        return (true, validAccounts,eBalance);
    }
    
    function verifyVCDelegation(string memory didIssuer, string memory didSubject, bytes memory signature, address[] memory addresses, bytes32[] memory proofs) internal returns (bool, address[] memory, uint)
    {
        //check total signature, first
        (, bytes memory data) = registryContract.call(abi.encodeWithSignature("getAddress(string)",didIssuer));
        (bool b, address a) = abi.decode(data,(bool, address));
        require(b, "Actor not found");
        
        require(PoliceLib.verify(a, 
                                keccak256(abi.encode(CredentialType.DELEGATION, didSubject, didIssuer, addresses, proofs)), 
                                signature), "Signature of VC is not correct");
        
        address [] memory validAccounts;
        
        //now evaluate validity each account proof
        require(addresses.length==proofs.length, "Address list is empty");
        uint len = addresses.length;
        uint eBalance = 0;
        for (uint i=0; i<len; i++) { //
            //hash = ;
            require(PoliceLib.verify(addresses[i], keccak256(abi.encode(addresses[i],propID)), abi.encodePacked(proofs[i])), "address not verified");
            
            //ensure that this account not used and tag it as used now
            if(!accountsUsedforVote[addresses[i]]){
                eBalance = eBalance + eligibleBalance(addresses[i]);
                accountsUsedforVote[addresses[i]]=true;
                //validAccounts.push(addresses[i]);
                address[] memory tmp = new address[](1);
                tmp[0] = addresses[i];
                validAccounts= PoliceLib.concatenateArrays(validAccounts, tmp);
            }
        }
        return (true, validAccounts, eBalance);
    }
    
    
    function eligibleBalance(address account) internal view returns (uint)
    {
        uint backward = ELIGIBLE_BALANCE_BACKWARD_WINDOW;
        return account.balance; //in wei
        //TODO calculate eligible balance : mean of balance through last n block
        //replace to special command and pass n value too.
        //call precompiled contract LedgerDataRetrieve.sol
    }
    
    //block.coinbase
    //blockhash(uint blockNumber) returns (bytes32)
    //block.timestamp (uint)
    
}
