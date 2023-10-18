# DAppSCAN
DAppSCAN: Building Large-Scale Datasets for Smart Contract Weaknesses in DApp Projects. ([PDF](https://arxiv.org/abs/2305.08456))

DAppSCAN consists of two datasets: DAppSCAN-source and DAppSCAN-bytecode.

## DAppSCAN-source

- **contracts**: the source of smart contracts in the DApps.

- **audit_report**: the original audit reports of the DApps (in pdf form).

- **SWC_source**: the analysis report of SWCs in the source code.

## DAppSCAN-bytecode

- **bytecode**: the compiled bytecode of each smart contract in the DApps.

- **SWC_bytecode**: the analysisi report of SWCs in the compiled bytecode.

- **solc-DApp**: the code for compiling the source code into the bytecode in this repository.

## Audit_and_Repository_link.xlsx

An excel file that contains links to the Audit Report and Code Repositories for each DApp. The columns are:

- **File Name**: The name of each DApp directory in DAPPSCAN-source/\*/ and DAPPSCAN-bytecode/\*/.
  
- **Audit Company** and **Project Name**: The corresponding audit company and DApp project.
  
- **Audit Report Link**: Link to the audit report.
  
- **Code Repository**: Link to the code reporsitory or blockchain address.

## Contact
If you have any questions about our dataset, please contact sujzh3@mail2.sysu.edu.cn
