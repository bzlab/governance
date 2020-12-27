pragma solidity ^0.5.3;

import "./PoliceLib.sol";

contract RegistryContract {

    uint constant FOUNDER_ALLOWED_ONBOARD_LIMIT = 5;
    
    struct Signature{
        uint8 v;
        bytes32 r; 
        bytes32 s;
    }
    
    // DDO type.
    struct DDO {
        address signAddress; //address used in governance interactions
        //bytes pubKey;  or accountAddress
        string onboarder;
        string did;
        bytes signature;  
        uint8 flag; //default value 38
    }

    mapping (string => uint256) reputations;   // reputations of experts

    mapping (string => DDO) founders; // DDOs of founders. Created in Genesis Transactions. RO (Read-only)
    mapping (string => DDO) initialDevelopers; // DDOs of initial developers. Created in Genesis Transactions. RO (Read-only)
    mapping (string => DDO) developers; // DDOs of developers onboarded by Founders.
    mapping (string => DDO) actors; // registered DDOs of other actors
    mapping (string => uint) founderOnboardCounts; //number of Developer onboarded by a founder
    //if we do not manage Developers in this contract how come we know the number of Developers?
    
    uint public numActors=0;
    
    //EVENTS
    event HashCalculated(bytes32 hashl);
    event SignCalculated(bool result);

    //CONSTRUCTOR
    constructor() internal{
        // Note that the following intial values are used for just experimental purpose.
        //create founder numDDOs
        //bytes memory pubf1 = "0x627306090abaB3A6e1400e9345bC60c78a8BEf57";
        address pubf1=0x627306090abaB3A6e1400e9345bC60c78a8BEf57;
        //address pubf1=0x627306090abab3a6e1400e9345bc60c78a8bef57;
        founders["did.founder.1"] = DDO(pubf1, "genesis", "did.founder.1","0x1b53d364ef136d5733e9afa8c64bb2214feed913d19cee907538b57e9472b181b96db15d9133d99b061e58d3b8e96486beccf0672583e6225ae367aeb6eb0e58ca", 38);
        //founders["did.founder.2"] = DDO(hex"627306090abaB3A6e1400e9345bC60c78a8BEf57", "", "did.founder.2","0x00010203");
        founders["did.founder.2"] = DDO(0xf17f52151EbEF6C7334FAD080c5704D77216b732, "genesis", "did.founder.2","0x1bfe01a181d6aa664726a69a69614d2e57af45d90520e8ad4b58d129b7a1e204a53ccaa3696fc365682b6242f2fb1bbdebace8f817ad489e76f43a8fdf1f07b2cb",38);

        //initial DevelopersDDOs
        initialDevelopers["did.idev.1"] = DDO(0x5c23c7AEA30d8BeAb849b408094F91ee99330337, "did.founder.1", "did.idev.1", "0x1c63916122f693090e24351645efe0508e5fd4337e745c8e6ed490d47a4ee66224569de15ac137bfea7529f473b838e8021e69d628dea7d3e07dc25be2689e8a1b",38);
        initialDevelopers["did.idev.2"] = DDO(0x485C4366C12Ba102E4B7CDf48352aa57741740e5, "did.founder.1", "did.idev.2", "0x1c229f162b6b4cebadd5af4d3fa68e55c8dc0b90b26762af7dca4e4739920110124ae9bd006763065a4bf8430724167121aa30534d4690e3c30478ff16f29f3c38",38);
        initialDevelopers["did.idev.3"] = DDO(0x815B380128e9514e9e08303597cfD9c3745403A2, "did.founder.1", "did.idev.3", "0x1c828a3cb5caf3305e1b422fdeeb6d68287f3695e2444d1bfa640c8e0aa9f8aea47ca903673eb759ecd3cc9c2c8effe7d08676b58a25229a9c04b2bc64f7f639b7",38);
    }

    function onboardActor(address pubAdr, string memory onboarderDid, string memory did, bytes memory signature) public returns (bool result) {
        //check existance
        require(actors[did].flag != 38, "Already exists");
        
        // verify DDO_of_Actor 
        //check signature
        
        DDO memory ob = founders[onboarderDid];
        if (ob.flag != 38){ //check onboarder is registered
            ob = actors[onboarderDid];  // onboarder may be another actor
            if(ob.flag != 38){//self onboarder. User or Miner
                onboarderDid=did;
                ob.signAddress = pubAdr;
            }
        }else{//founder is onboarding a Developer
            // verify that allowed FOUNDER_ALLOWED_ONBOARD_LIMIT is not violated by founder 
            uint num = founderOnboardCounts[onboarderDid];
            require(num<FOUNDER_ALLOWED_ONBOARD_LIMIT-1,"onboard limit error");
        }
        
        //calculate hash of   signAddress ||onboarder||did||signature;
        //abi.encodePacked("\x19Ethereum Signed Message:\n32", hash)
        //bytes32 prefixedHash = keccak256("\x19Ethereum Signed Message:\n", uint2str(_msgHex.length), _msgHex);
        bytes memory data = abi.encode(pubAdr, onboarderDid, did); //paddingli encode yapar
        bytes32 hash = keccak256(data);
        emit HashCalculated(hash);
        bool sonuc = PoliceLib.verify(ob.signAddress, hash, signature);   //LIBRARY YAP
        
        emit SignCalculated(true);
        require(sonuc,"DDO's signature cannot be verified");
        
        
        if(isFounder(onboarderDid)){
            //add to registry DDO_of_Developer
            developers[did] = DDO(pubAdr, onboarderDid, did, signature,38);
            uint num = founderOnboardCounts[onboarderDid];
            founderOnboardCounts[onboarderDid] = num++;
        }else{
            //add to registry DDO_of_Actor
            actors[did] = DDO(pubAdr, onboarderDid, did, signature,38);
        }
        reputations[did] = 0; //default reputation
        numActors++; // num of actors

        return sonuc;
    }

    function unregisterActor(string memory did, bytes memory signature) public returns (bool result) {
        //check existance
        require(actors[did].flag == 38, "Not enrolled Actor");
        //check authorization of caller
        //TODO
        //Delete actor's registration
        //TODO
        return false;
    }


    function getDDO(string memory did) public view returns (PoliceLib.ActorType t, address signAddress, string memory onboarder, bytes memory signature) {
        DDO memory found;
        PoliceLib.ActorType fActor; 
        if(founders[did].flag==38){
            fActor=PoliceLib.ActorType.FOUNDER;
            found = founders[did];
            //return (PoliceLib.ActorType.FOUNDER,founders[did].signAddress, founders[did].onboarder, founders[did].signature);
        }
        if(initialDevelopers[did].flag==38){
            fActor=PoliceLib.ActorType.INITIAL_DEVELOPER;
            found = initialDevelopers[did];
            //return (PoliceLib.ActorType.INITIAL_DEVELOPER, initialDevelopers[did]);
        }
        if(developers[did].flag==38){
            fActor=PoliceLib.ActorType.DEVELOPER;
            found = developers[did];
            //return (PoliceLib.ActorType.DEVELOPER, developers[did]);
        }
        if(actors[did].flag==38){
            found = actors[did];
            fActor=PoliceLib.ActorType.OTHER;
        }else{
            //revert();           
            return (fActor,address(0x0), "", "0x0");
        }

        //require(actors[did].flag==38);//check if found
        //return (PoliceLib.ActorType.OTHER, found);
        return (fActor,found.signAddress, found.onboarder, found.signature);
            // DDO type.
    }
    
    function checkAddress(string memory did, address adr) public view returns (bool) {
        address signAddress; 
        string memory onboarder;
        bytes memory signature;  
        PoliceLib.ActorType t;
        (t,signAddress,onboarder,signature) = getDDO(did);
        
        if(signAddress!=address(0x0)){
            return (signAddress == adr);
        }else{
            return false;   
        }
    }
    
    function getAddress(string memory did) public view returns (bool, address) {
        address signAddress; 
        string memory onboarder;
        bytes memory signature;  
        PoliceLib.ActorType t;
        (t,signAddress,onboarder,signature) = getDDO(did);
        if(signAddress!=address(0x0)){
            return (true, signAddress);
        }else{
            return (false, address(0x0));   
        }
    }
 
    function isRegistered(string memory did) public view returns (bool) {
        if(founders[did].flag==38){
            return true;
        }
        if(initialDevelopers[did].flag==38){
          return true;
        }
        if(developers[did].flag==38){
          return true;
        }
        if(actors[did].flag==38){
            return true;
        }else{
            return false;
        }

    }
    function isFounder(string memory did) public view returns (bool) {
        return (founders[did].flag==38);
    }
    function isInitDev(string memory did) public view returns (bool) {
        return (initialDevelopers[did].flag==38);
    }
    function isDev(string memory did) public view returns (bool) {
        return (developers[did].flag==38);
    }

    function updateReputation(string memory did, uint value) public {
        //existance control
        require(isRegistered(did), "Unknown actor");
        reputations[did]= value;
    }
    
    function reportAbuse (string memory didMissbehave, string memory didReporter, uint pid) public{
        //verify claim
        //freeze DID
    }
    
    function() external payable {}

}
