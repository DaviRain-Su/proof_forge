import type { Abi } from "viem";

export type DeploymentFile = {
  schema: "proofship.rwa-share.deployment.v1";
  target: "evm";
  network: string;
  rpcUrl: string;
  chainId: number;
  contractAddress: `0x${string}`;
  program: string;
  ctor: { supply: string; perTx: string; windowCap: string };
  abi: Abi;
  bytecode?: `0x${string}`;
  notes?: string[];
};

export type GateReportProof = {
  file: string;
  program: string;
  proofStatus: string;
  proofTheoremCount: number;
  proofCertificationDigest: string;
};

export type GateReport = {
  schema: "proofship.gate-report.v1";
  generatedAt: string;
  program: string;
  sourceDigest: string;
  semanticDigest: string;
  build: { target: string; profile: string; deployable: boolean; outputSetDigest: string };
  proofs: GateReportProof[];
  negative: { file: string; exitCode: number; diagnostic: string; artifacts: string };
  anvil: { scenarios: number; result: string };
};
