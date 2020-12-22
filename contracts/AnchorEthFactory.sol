// AnchorEthFactory.sol: Factory contract for all account contracts
pragma solidity >=0.6.0 <0.8.0;

import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '../interfaces/IShuttleAsset.sol';
import '../interfaces/IAnchorAccount.sol';

contract AnchorEthFactory is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    mapping(address => address) public ContractMap;
    mapping(address => bytes32) public AddressMap; // eth address => bech32 decoded terra address

    address[] private ContractsList;
    IShuttleAsset public terrausd;
    IShuttleAsset public anchorust;

    boolean public isMigrated = false;

    constructor(IShuttleAsset _terrausd, IShuttleAsset _anchorust) public {
        terrausd = _terrausd;
        anchorust = _anchorust;
    }

    // **MUST** be called after calling openzeppelin upgradable_contract_deploy_proxy
    function migrate(address newContract) onlyOwner {
        // migrate subcontract ownership to new contract
        for (uint i = 0; i < ContractsList.length; i++) {
            IAnchorAccount(ContractsList[i]).transferOwnership(newContract);
        }
        isMigrated = true;
    }

    function setUSTAddess(address _terrausd) onlyOwner {
        terrausd = _terrausd;
    }

    function setaUSTAddress(address _anchorust) onlyOwner {
        anchorust = _anchorust;
    }

    function assignTerraAddress(address eth, bytes32 terra) onlyOwner {
        AddressMap[eth] = terra;
    }

    function initDepositStable(uint256 amount, bytes32 to) public {
        // check if msg.sender already has corresponding subcontract
        if (bytes(ContractMap[msg.sender]).length > 0) {
            // execute subcontract
            IAnchorAccount(ContractMap[msg.sender]).initDepositStable(amount, to);
        }
        else {
            // create new contract
            deployContract();
        }
    }

    function finishDepositStable(uint256 amount) public {
        // check if msg.sender already has corresponding subcontract
        if (bytes(ContractMap[msg.sender]).length > 0) {
            // execute subcontract
            IAnchorAccount(ContractMap[msg.sender]).finshDepositStable(amount);
        }
        else {
            // create new contract
            deployContract();
        }
    }

    function initRedeemStable(uint256 amount, bytes32 to) public {
        // check if msg.sender already has corresponding subcontract
        if (bytes(ContractMap[msg.sender]).length > 0) {
            // execute subcontract
            IAnchorAccount(ContractMap[msg.sender]).initRedeemStable(amount, to);
        }
        else {
            // create new contract
            deployContract();
        }
    }

    function finishRedeemStable(uint256 amount) public {
        // check if msg.sender already has corresponding subcontract
        if (bytes(ContractMap[msg.sender]).length > 0) {
            // execute subcontract
            IAnchorAccount(ContractMap[msg.sender]).finishRedeemStable(amount);
        }
        else {
            // create new contract
            deployContract();
        }
    }

    function deployContract() public {
        // create new contract
        AnchorAccount accountContract = new AnchorAccount(address(this), msg.sender, terrausd, anchorust);
        // append to map
        ContractMap[msg.sender] = accountContract;
        ContractsList.push(accountContract);
        // emit contractdeployed event
        emit ContractDeployed(accountContract, msg.sender);
    }

    // Events
    event ContractDeployed(address account, address sender);
}

contract AnchorAccount is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IShuttleAsset public terrausd;
    IShuttleAsset public anchorust;

    address public anchorFactory;
    address public walletAddress;
    bool private DepositFlag = false;
    bool private RedemptionFlag = false;

    constructor(address _anchorFactory, address _walletAddress, IShuttleAsset _terrausd, IShuttleAsset _anchorust) public {
        anchorFactory = _anchorFactory;
        walletAddress = _walletAddress;
        terrausd = _terrausd;
        anchorust = _anchorust;
    }

    modifier checkDepositInit() {
        require(DepositFlag == false, "AnchorAccount: init deposit operation: init already called");
        _;
    }

    modifier checkDepositFinish() {
        require(DepositFlag == true, "AnchorAccount: finish deposit operation: init not called yet");
        _;
    }

    modifier checkRedemptionInit() {
        require(RedemptionFlag == false, "AnchorAccount: init redemption operation: init already called");
        _;
    }

    modifier checkRedemptionFinish() {
        require(RedemptionFlag == true, "AnchorAccount: finish redemption operation: init not called yet");
        _;
    }

    modifier onlyAuthSender() {
        require(walletAddress == tx.origin, "AnchorAccount: unauthorized sender");
        _;
    }

    function initDepositStable(uint256 amount, bytes32 to) public onlyAuthSender checkDepositInit {        
        // transfer UST to contract address
        terrausd.safeTransferFrom(msg.sender, address(this), amount);

        // transfer UST to Shuttle
        // TODO: Shuttle may fail - is an asynchronous status check mechanism possible?
        terrausd.burn(amount, to);

        // set DepositFlag to true
        DepositFlag = true;

        // emit initdeposit event
        emit InitDeposit(tx.origin, amount, to);
    }

    function finishDepositStable() public onlyAuthSender checkDepositFinish {
        // transfer aUST to msg.sender
        // call will fail if aUST was not returned from Shuttle/Anchorbot/Terra contracts
        require(anchorust.balanceOf(address(this)) > 0, "AnchorAccount: finish deposit operation: not enough aust");
        anchorust.safeTransfer(msg.sender, anchorust.balanceOf(address(this)));

        // set DepositFlag to false
        DepositFlag = false;

        // emit finishdeposit event
        emit FinishDeposit(tx.origin);
    }

    function initRedeemStable(uint256 amount, bytes32 to) public onlyAuthSender checkRedemptionInit {
        // transfer aUST to contract address
        anchorust.safeTransferFrom(msg.sender, address(this), amount);

        // transfer aUST to Shuttle
        // TODO: Shuttle may fail - is an asynchronous status check mechanism possible?
        anchorust.burn(amount, to);

        // set RedemptionFlag to true
        RedemptionFlag = true;

        // emit initredemption event
        emit InitRedemption(tx.origin, amount, to);
    }

    function finishRedeemStable() public onlyAuthSender checkRedemptionFinish {
        // transfer UST to msg.sender
        // call will fail if aUST was not returned from Shuttle/Anchorbot/Terra contracts
        require(terrausd.balanceOf(address(this)) > 0, "AnchorAccount: finish redemption operation: not enough ust");
        terrausd.safeTransfer(msg.sender, terrausd.balanceOf(address(this)));
        
        // set RedemptionFlag to false
        RedemptionFlag = false;

        // emit finishredemption event
        emit FinishRedemption(tx.origin);
    }

    // Events
    event InitDeposit(address sender, uint256 amount, bytes32 to);
    event FinishDeposit(address sender);
    event InitRedemption(address sender, uint256 amount, bytes32 to);
    event FinishRedemption(address sender);
}