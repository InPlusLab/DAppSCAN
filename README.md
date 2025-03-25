# DAppSCAN
DAppSCAN: Building Large-Scale Datasets for Smart Contract Weaknesses in DApp Projects. ([PDF](https://arxiv.org/abs/2305.08456))

DAppSCAN consists of two datasets: DAppSCAN-source and DAppSCAN-bytecode.

## DAppSCAN-source

### Description of the files

- **contracts**: the source of smart contracts in the DApps.

- **audit_report**: the original audit reports of the DApps (in pdf form).

- **SWC_source**: the analysis report of SWCs in the source code.

### Statistics of the dataset (as the Table 3 in the paper).
| Information | Numbers |
| - | - |
| Total audit reports | 608 |
| Total DApps | 682 |
| Total Solidity files | 21457 |
| Average Solidity files in a DApp | 31 |
| Average LOC in a DApp | 4318 |

## DAppSCAN-bytecode

### Description of the files

- **bytecode**: the compiled bytecode of each smart contract in the DApps.

- **SWC_bytecode**: the analysisi report of SWCs in the compiled bytecode.

- **solc-DApp**: the code for compiling the source code into the bytecode in this repository.

## Audit_and_Repository_link.xlsx

An excel file that contains links to the Audit Report and Code Repositories for each DApp. The columns are:

- **File Name**: The name of each DApp directory in DAPPSCAN-source/\*/ and DAPPSCAN-bytecode/\*/.
  
- **Audit Company** and **Project Name**: The corresponding audit company and DApp project.
  
- **Audit Report Link**: Link to the audit report.
  
- **Code Repository**: Link to the code reporsitory or blockchain address.

## Statistics of the SWC weaknesses (as the Table 4 in paper).

| ID | Title | #SWC in DAppSCAN-source | #SWC in DAppSCAN-bytecode |
| - | - | - | - |
|135 | Code With No Effects | 291 | 161 |
|101 | Integer Overflow and Underflow | 204 | 123 |
|107 | Reentrancy | 138 | 86 |
|104 | Unchecked Call Return Value | 116 | 201 |
|102 | Outdated Compiler Version | 115 | 20 |
|103 | Floating Pragma | 105 | 90 |
|128 | DoS With Block Gas Limit | 103 | 49 |
|114 | Transaction Order Dependence | 86 | 47 |
|100 | Function Default Visibility | 75 | 8 |
|116 | Block values as a proxy for time | 65 | 3 |
|131 | Presence of unused variables | 51 | 46 |
|105 | Unprotected Ether Withdrawal | 42 | 15 |
|108 | State Variable Default Visibility | 36 | 6 |
|119 | Shadowing State Variables | 34 | 0 |
|113 | DoS with Failed Call | 30 | 7 |
|120 | Weak Sources of Randomness from Chain Attributes | 23 | 5 |
|129 | Typographical Error | 22 | 0 |
|123 | Requirement Violation | 14 | 0 |
|134 | Message call with hardcoded gas amount | 12 | 0 |
|112 | Delegatecall to Untrusted Callee | 12 | 10 |
|111 | Use of Deprecated Solidity Functions | 11 | 0 |
|126 | Insufficient Gas Griefing | 9 | 1 |
|124 | Write to Arbitrary Storage Location | 9 | 0 |
|115 | Authorization through tx.origin | 8 | 1 |
|110 | Assert Violation | 7 | 0 |
|122 | Lack of Proper Signature Verification | 5 | 2 |
|125 | Incorrect Inheritance Order | 4 | 1 |
|117 | Signature Malleability | 4 | 1 |
|133 | Hash Collisions With Multiple Variable Length Arguments | 3 | 2 |
|121 | Missing Protection against Signature Replay Attacks | 3 | 1 |
|118 | Incorrect Constructor Name | 3 | 0 |
|106 | Unprotected SELFDESTRUCT Instruction | 3 | 1 |
|132 | Unexpected Ether balance | 2 | 0 |
|109 | Uninitialized Storage Pointer | 1 | 1 |
|136 | Unencrypted Private Data On-Chain | 0 | 0 |
|130 | Right-To-Left-Override control character (U+202E) | 0 | 0 |
|127 | Arbitrary Jump with Function Type Variable | 0 | 0 |
| | Total | 1646 | 888 | 

## Contact
If you have any questions about our dataset, please contact sujzh3@mail2.sysu.edu.cn
