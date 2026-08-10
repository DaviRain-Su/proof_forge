import type { Abi } from "viem";

export type DeploymentFile = {
  schema: string;
  target: "evm";
  network: string;
  rpcUrl: string;
  chainId: number;
  contractAddress: `0x${string}`;
  program: string;
  constructorInitial: number;
  abi: Abi;
  bytecode?: `0x${string}`;
  notes?: string[];
};
