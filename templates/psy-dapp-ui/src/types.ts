export type PsyAbiMethod = {
  name: string;
  methodId: number;
  mode?: string;
  isView?: boolean;
  params?: Array<{ name: string; type?: string }>;
  returns?: Array<{ name: string; type?: string }>;
  arity?: { inputs: number; outputs: number };
};

export type PsyAbi = {
  schema?: string;
  program?: string;
  target?: string;
  methods: PsyAbiMethod[];
};

export type PsyDeployment = {
  schema?: string;
  target?: string;
  network?: string;
  contractId?: number | null;
  contractUuid?: string | null;
  explorer?: string;
  contractPath?: string;
  callHint?: string;
};
