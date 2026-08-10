/** Subset of PF Solana IDL used by this UI (StateCell-shaped). */
export type PfIdlAccount = {
  name: string;
  outerSigner?: boolean;
  outerWritable?: boolean;
  position?: number;
};

export type PfIdlInstruction = {
  name: string;
  handlerId: number;
  mode?: string;
  accounts: PfIdlAccount[];
  /** Optional: scalar param names in ix-data order (u64 LE each). */
  params?: Array<{ name: string; type?: string }>;
};

export type PfIdl = {
  schema?: string;
  programName?: string;
  profileId?: string;
  instructions: PfIdlInstruction[];
};

export type DeploymentFile = {
  schema: string;
  program: string;
  target: "solana";
  rpcUrl: string;
  programId: string;
  stateAccount: string;
  idl: PfIdl;
  ixEncoding?: {
    layout: string;
    note?: string;
  };
};
