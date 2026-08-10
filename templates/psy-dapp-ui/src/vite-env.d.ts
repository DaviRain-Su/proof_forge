/// <reference types="vite/client" />

interface PsyProvider {
  requestAccounts(): Promise<string[]>;
  sendTransaction(
    account: string,
    call: { contract_id: bigint | number; method_name: string; inputs: bigint[] },
  ): Promise<string>;
  on?(event: string, cb: (...args: unknown[]) => void): void;
}

interface Window {
  psy?: PsyProvider;
}
