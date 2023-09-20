  pragma solidity ^0.4.0;

  /**
  * @title ConstitutionalDNA
  * @author ola
  * --- Collaborators ---
  * @author zlatinov
  * @author panos
  * @author yemi
  * @author archil
  * @author anthony
  */
  contract ConstitutionalDNA {

      struct Person{
          address addr;
          bytes name;
          bytes role;
          uint rank;
      }

      bool onceFlag = false;
      bool isRatified = false;
      address home = 0x0; //consensusX housing
      address[]foundingTeamAddresses; // iterable list of addresses

      mapping (address => Person) public foundingTeam; //foundingteam
      mapping(address => bool) mutify;

      uint ratifyCount;

      /**
      * @notice Deploying Constitution contract. Setting `msg.sender.address()` as Founder
      * @dev Deploy and instantiate the Constitution contract
      */
      function ConstitutionalDNA(){
          foundingTeam[msg.sender].addr = msg.sender;
          foundingTeam[msg.sender].role = "Founder";
          foundingTeam[msg.sender].rank = 1;
          foundingTeamAddresses.push(msg.sender);
      }

      struct Articles {
          bytes article;
          uint articleNum;
          uint itemNums;
          bytes[] items;
          bool amendable;
          bool set;
      }

      uint articleNumbers = 0;
      Articles[] public constitutionalArticles;

      event ArticleAddedEvent(uint indexed articleId, bytes articleHeading, bool amendable);
      event ArticleItemAddedEvent(uint indexed articleId, uint indexed itemId, bytes itemText);
      event ArticleAmendedEvent(uint indexed articleId, uint indexed itemId, bytes newItemText);
      event ProfileUpdateEvent(address profileAddress, bytes profileName);
      event FoundingTeamSetEvent(address[] foundingTeam, uint[] ranks);
      event HomeSetEvent(address home);

      /**
      * @notice Adding new article: `_aticle`
      * @dev Add new article to the constituitionalDNA. And fire event if successful
      * @param _article Article name or title to be stored
      * @param _amendable True if Article is amendable
      */
      function addArticle(bytes _article, bool _amendable) external
          founderCheck
          ratified
          homeIsSet
      {
          constitutionalArticles.length = articleNumbers+1;
          constitutionalArticles[articleNumbers].article = _article;
          constitutionalArticles[articleNumbers].articleNum = articleNumbers;
          constitutionalArticles[articleNumbers].amendable = _amendable;
          constitutionalArticles[articleNumbers].set = true;

          ArticleAddedEvent(articleNumbers, _article, _amendable);
          articleNumbers++;
      }


      /**
      * @notice Adding new Item to article: `String(constitutionalArticles[_articleNum].article)`
      * @dev Add a new Item to an article denoted by articleNum which is the article's index in the constitutionalArticles array.
      Fires the AddedItem event if successful
      * @param _articleNum The index of  the article in the constitutionalArticles array which the item is added to
      * @param _itemText The Content/Data of the item
      */
      function addArticleItem(uint _articleNum, bytes _itemText) external
          founderCheck
          articleSet(_articleNum)
          ratified
          homeIsSet
      {
          uint itemId = constitutionalArticles[_articleNum].itemNums;
          constitutionalArticles[_articleNum].items.length = itemId+1;

          constitutionalArticles[_articleNum].items[itemId] = _itemText;
          constitutionalArticles[_articleNum].itemNums++;

          ArticleItemAddedEvent(_articleNum, itemId, _itemText);
      }

      /**
      * @notice Updating item with index: `_item` of article: `String(constitutionalArticles[_articleNum].article)`
      * @dev Update Content of Item by idicating the item index in the article.items array and the article index in the constitutionalArticles array.
      Fires the Amended event if successful
      * @param _articleNum The index of the article in the constitutionalArticles array
      * @param _item The index of the item in the article.item array
      * @param _textChange The data to be updated into the item Position in the article.item array
      */
      function amendArticleItem(uint _articleNum, uint _item, bytes _textChange)
          articleSet(_articleNum)
          updaterCheck
          amendable(_articleNum)
      {
          constitutionalArticles[_articleNum].items[_item] = _textChange;

          ArticleAmendedEvent(_articleNum, _item, _textChange);
      }

      /**
      * @notice Retreiving article item details from item: `_item` of article: `String(constitutionalArticles[_articleNum].article)`
      * @dev Retreive Item data from Article array
      * @param _articleNum The index of the article in the constitutionalArticles array
      * @param _item The index of the item in the article.item array
      * @return article Name/Title of the article under which the item is indexed
      * @return articleNum The index of the article in the constitutionalArticles array
      * @return amendable True if the item is amendable or can be updated
      * @return items[_item] The data of the Item being retreived
      */
      function getArticleItem(uint _articleNum, uint _item) public constant returns (bytes article, uint articleNum, bool amendible, bytes itemText)
      {

          return (
              constitutionalArticles[_articleNum].article,
              constitutionalArticles[_articleNum].articleNum,
              constitutionalArticles[_articleNum].amendable,
              constitutionalArticles[_articleNum].items[_item]
          );
      }


      /**
      * @notice `msg.sender.address()` confirming the contract and articles
      * @dev Founding Team ratify/approve the contract and articles. Once completed by all founding team members,
      Incrementing ratifyCount at each turn. Deactivates adding articles or items
      * @return True if completely ratified else false
      */
      function initializedRatify()
          external
          foundingTeamCheck
          foundationNotSet
          mutifyAlreadySet
          returns (bool success)
      {
          if (ratifyCount == foundingTeamAddresses.length)
          {
              isRatified = true;
              return true;
          }
          else
          {
              mutify[msg.sender] == true;
              ratifyCount++;
              return false;
          }
      }


      /**
      * @notice Adding founding team members to founding Team list
      * @dev Add array of new Founding team member to the foundingTeam list
      * @param _founderRanks Array of rank/index of the founding Team members
      * @param _founderAddrs Array of founding Team members matching the indexes in the _founderRanks array
      */
      function setFoundingTeam(uint[] _founderRanks, address[] _founderAddrs)
          external
          founderCheck
          foundingTeamListHasFounder(_founderRanks,_founderAddrs)
          foundingTeamMatchRank(_founderRanks,_founderAddrs)
      {
          for(uint i = 1; i <_founderRanks.length; i++)
          {
              foundingTeamAddresses.push(_founderAddrs[i]);
              foundingTeam[_founderAddrs[i]].addr = _founderAddrs[i];
              foundingTeam[_founderAddrs[i]].rank = _founderRanks[i];
          }

          FoundingTeamSetEvent(_founderAddrs, _founderRanks);
      }

      /**
      * @notice Updating Profile information of `msg.sender.address()`
      * @dev Update the profile information of a founding Team member using mssg.sender as the index.
      Enable any founder to update name and address. Fire FounderUpdate event if successful
      * @param _addr Address of the founding Team member
      * @param _profileName Profile name to be updated to the founding Team Array
      */
      function updateProfile(address _addr, bytes _profileName)
          foundingTeamCheck
      {
          foundingTeam[_addr].addr = _addr;
          foundingTeam[msg.sender].name = _profileName;

          ProfileUpdateEvent(_addr, _profileName);
      }


      /**
      * @notice Setting consensusX address to `_consensusX.address()`
      * @dev set consensusX in which the Constitution is housed
      * @param _consensusX Address of the consensusX on the blockchain
      */
      function setHome (address _consensusX)
          founderCheck
          once
      {
          home = _consensusX;
          HomeSetEvent(home);
      }


      modifier founderCheck()  {
          var (tempAddr, tempRank) = (foundingTeam[msg.sender].addr, foundingTeam[msg.sender].rank);
          if(tempAddr != msg.sender || tempRank != 1 ) throw;
          _;
      }

      modifier foundationNotSet(){
          if(foundingTeam[msg.sender].rank != 1 && mutify[foundingTeamAddresses[0]] == false) throw;
          _;
      }

      modifier mutifyAlreadySet(){
          if (mutify[msg.sender] == true) throw;
          _;
      }

      modifier foundingTeamCheck(){
          if(msg.sender != foundingTeam[msg.sender].addr) throw;
          _;
      }

      modifier articleSet(uint _articleNumber){
          if(constitutionalArticles[_articleNumber].set != true) throw;
          _;
      }

      modifier updaterCheck(){
          if (msg.sender != home) throw;
          _;
      }

      modifier once(){
          if (onceFlag == true) throw;
          onceFlag = true;
          _;
      }

      modifier amendable(uint _articleNum){
          if (constitutionalArticles[_articleNum].amendable == false) throw;
          _;
      }

      modifier homeIsSet(){
          if (home == 0x0) throw;
          _;
      }

      modifier ratified(){
          if (foundingTeam[msg.sender].rank == 1 && isRatified == true) throw;
          _;
      }

      modifier foundingTeamMatchRank(uint[] _founderRanks,address[] _founderAddrs){
          if(_founderRanks.length != _founderAddrs.length) throw;
          _;
      }

      modifier foundingTeamListHasFounder(uint[] _founderRanks,address[] _founderAddrs){
          if(_founderAddrs[0] != foundingTeamAddresses[0] || _founderRanks[0] != 1) throw;
          _;
      }

      /*
      * Safeguard function.
      * This function gets executed if a transaction with invalid data is sent to
      * the contract or just ether without data.
      */
      function (){
          throw;
      }
  }
