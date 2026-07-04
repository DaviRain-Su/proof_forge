import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.Target.Registry

namespace ProofForge.Contract.Token

open ProofForge.Target

inductive TokenStandard where
  | erc20
  | splToken
  | splToken2022
  deriving BEq, DecidableEq, Repr

def TokenStandard.id : TokenStandard → String
  | .erc20 => "erc20"
  | .splToken => "spl-token"
  | .splToken2022 => "spl-token-2022"

inductive TokenFeature where
  | mintable
  | burnable
  | capped
  | pausable
  | permit
  | transferFee
  | nonTransferable
  | confidentialTransfer
  | transferHook
  | metadataPointer
  | defaultAccountState
  | immutableOwner
  deriving BEq, DecidableEq, Repr

def TokenFeature.id : TokenFeature → String
  | .mintable => "mintable"
  | .burnable => "burnable"
  | .capped => "capped"
  | .pausable => "pausable"
  | .permit => "permit"
  | .transferFee => "transfer_fee"
  | .nonTransferable => "non_transferable"
  | .confidentialTransfer => "confidential_transfer"
  | .transferHook => "transfer_hook"
  | .metadataPointer => "metadata_pointer"
  | .defaultAccountState => "default_account_state"
  | .immutableOwner => "immutable_owner"

def knownFeatureIds : Array String := #[
  TokenFeature.mintable.id,
  TokenFeature.burnable.id,
  TokenFeature.capped.id,
  TokenFeature.pausable.id,
  TokenFeature.permit.id,
  TokenFeature.transferFee.id,
  TokenFeature.nonTransferable.id,
  TokenFeature.confidentialTransfer.id,
  TokenFeature.transferHook.id,
  TokenFeature.metadataPointer.id,
  TokenFeature.defaultAccountState.id,
  TokenFeature.immutableOwner.id
]

def TokenFeature.ofId? (id : String) : Option TokenFeature :=
  match id with
  | "mintable" => some .mintable
  | "burnable" => some .burnable
  | "capped" => some .capped
  | "pausable" => some .pausable
  | "permit" => some .permit
  | "transfer_fee" => some .transferFee
  | "non_transferable" => some .nonTransferable
  | "confidential_transfer" => some .confidentialTransfer
  | "transfer_hook" => some .transferHook
  | "metadata_pointer" => some .metadataPointer
  | "default_account_state" => some .defaultAccountState
  | "immutable_owner" => some .immutableOwner
  | _ => none

def TokenFeature.parse (id : String) : Except String TokenFeature :=
  match TokenFeature.ofId? id with
  | some feature => .ok feature
  | none =>
      .error s!"unknown token feature `{id}`; known features: {String.intercalate ", " knownFeatureIds.toList}"

structure TokenSpec where
  name : String
  symbol : String
  decimals : Nat
  initialSupply? : Option Nat := none
  features : Array TokenFeature := #[]
  deriving Repr

def TokenSpec.hasFeature (spec : TokenSpec) (feature : TokenFeature) : Bool :=
  spec.features.any (fun item => item == feature)

def TokenSpec.needsToken2022 (spec : TokenSpec) : Bool :=
  spec.hasFeature .transferFee ||
  spec.hasFeature .nonTransferable ||
  spec.hasFeature .confidentialTransfer ||
  spec.hasFeature .transferHook ||
  spec.hasFeature .metadataPointer ||
  spec.hasFeature .defaultAccountState ||
  spec.hasFeature .immutableOwner

inductive TokenArtifactKind where
  | evmErc20Contract
  | solanaSplTokenPlan
  | solanaToken2022Plan
  deriving BEq, DecidableEq, Repr

def TokenArtifactKind.id : TokenArtifactKind → String
  | .evmErc20Contract => "evm-erc20-contract"
  | .solanaSplTokenPlan => "solana-spl-token-plan"
  | .solanaToken2022Plan => "solana-token-2022-plan"

structure TokenPlan where
  targetId : String
  standard : TokenStandard
  artifactKind : TokenArtifactKind
  capabilities : CapabilitySet
  operations : Array String
  notes : Array String := #[]
  deriving Repr

structure SolanaTokenAccountPlan where
  name : String
  role : String
  ownerProgram? : Option String := none
  signer : Bool := false
  writable : Bool := false
  derivation? : Option String := none
  deriving Repr

structure SolanaTokenInstructionParam where
  name : String
  type : String
  source : String
  deriving Repr

structure SolanaTokenInstructionPlan where
  order : Nat
  name : String
  operation : String
  programId : String
  accounts : Array String
  params : Array SolanaTokenInstructionParam := #[]
  feature? : Option String := none
  token2022Only : Bool := false
  deriving Repr

structure SolanaTokenExtensionPlan where
  feature : String
  extension : String
  scope : String
  initInstruction : String
  requiresConfig : Bool := false
  notes : Array String := #[]
  deriving Repr

structure SolanaTokenAuthorityChangePlan where
  name : String
  authorityType : String
  currentAuthority : String
  newAuthority : String
  operation : String
  reason : String
  deriving Repr

structure SolanaTokenReference where
  label : String
  url : String
  deriving Repr

structure SolanaTokenDeploymentPlan where
  standard : TokenStandard
  tokenProgramId : String
  associatedTokenProgramId : String
  systemProgramId : String
  rentSysvarId : String
  accounts : Array SolanaTokenAccountPlan
  instructions : Array SolanaTokenInstructionPlan
  extensions : Array SolanaTokenExtensionPlan
  authorityChanges : Array SolanaTokenAuthorityChangePlan
  references : Array SolanaTokenReference
  deriving Repr

def baseErc20Operations : Array String := #[
  "erc20.total_supply",
  "erc20.balance_of",
  "erc20.transfer",
  "erc20.approve",
  "erc20.allowance",
  "erc20.transfer_from",
  "erc20.events"
]

def evmFeatureOperations (spec : TokenSpec) : Array String :=
  #[] ++
  (if spec.hasFeature .mintable then #["erc20.mint"] else #[]) ++
  (if spec.hasFeature .burnable then #["erc20.burn"] else #[]) ++
  (if spec.hasFeature .capped then #["erc20.cap"] else #[]) ++
  (if spec.hasFeature .pausable then #["erc20.pause"] else #[]) ++
  (if spec.hasFeature .permit then #["erc20.permit"] else #[])

def evmErc20Plan (target : TargetProfile) (spec : TokenSpec) : TokenPlan := {
  targetId := target.id
  standard := .erc20
  artifactKind := .evmErc20Contract
  capabilities := #[
    .storageScalar,
    .storageMap,
    .callerSender,
    .eventsEmit,
    .controlConditional,
    .assertions
  ]
  operations := baseErc20Operations ++ evmFeatureOperations spec
  notes := #[
    "EVM lowers a TokenSpec into a per-token ERC-20-compatible contract artifact.",
    "Deployment creates contract bytecode plus ABI/deploy metadata."
  ]
}

def baseSplTokenOperations : Array String := #[
  "spl-token.create_mint",
  "spl-token.create_token_account",
  "spl-token.mint_to",
  "spl-token.transfer_checked",
  "spl-token.approve",
  "spl-token.burn",
  "spl-token.revoke",
  "spl-token.set_authority"
]

def token2022FeatureOperations (spec : TokenSpec) : Array String :=
  #[] ++
  (if spec.hasFeature .transferFee then #[
    "token-2022.extension.transfer_fee",
    "token-2022.transfer_checked_with_fee",
    "token-2022.withdraw_withheld_tokens_from_accounts",
    "token-2022.harvest_withheld_tokens_to_mint",
    "token-2022.withdraw_withheld_tokens_from_mint"
  ] else #[]) ++
  (if spec.hasFeature .nonTransferable then #["token-2022.extension.non_transferable"] else #[]) ++
  (if spec.hasFeature .confidentialTransfer then #["token-2022.extension.confidential_transfer"] else #[]) ++
  (if spec.hasFeature .transferHook then #["token-2022.extension.transfer_hook"] else #[]) ++
  (if spec.hasFeature .metadataPointer then #["token-2022.extension.metadata_pointer"] else #[]) ++
  (if spec.hasFeature .defaultAccountState then #["token-2022.extension.default_account_state"] else #[]) ++
  (if spec.hasFeature .immutableOwner then #["token-2022.extension.immutable_owner"] else #[])

def solanaSplTokenProgramId : String :=
  "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"

def solanaToken2022ProgramId : String :=
  "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"

def solanaAssociatedTokenProgramId : String :=
  "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL"

def solanaSystemProgramId : String :=
  "11111111111111111111111111111111"

def solanaRentSysvarId : String :=
  "SysvarRent111111111111111111111111111111111"

def TokenStandard.solanaProgramId : TokenStandard → String
  | .splToken => solanaSplTokenProgramId
  | .splToken2022 => solanaToken2022ProgramId
  | .erc20 => ""

def validateSolanaTokenFeatures (spec : TokenSpec) : Except String Unit := do
  if spec.hasFeature .transferFee && spec.hasFeature .nonTransferable then
    .error "Solana Token-2022 features `transfer_fee` and `non_transferable` cannot be enabled on the same token mint"
  else
    .ok ()

private def param (name type source : String) : SolanaTokenInstructionParam := {
  name := name
  type := type
  source := source
}

private def solanaTokenAccounts (spec : TokenSpec) (standard : TokenStandard) : Array SolanaTokenAccountPlan := #[
  {
    name := "payer",
    role := "fee-payer-and-rent-funder",
    signer := true,
    writable := true
  },
  {
    name := "mint",
    role := "token-mint",
    ownerProgram? := some standard.solanaProgramId,
    signer := true,
    writable := true
  },
  {
    name := "mint_authority",
    role := "mint-authority",
    signer := true
  },
  {
    name := "owner",
    role := "source-token-owner",
    signer := true
  },
  {
    name := "owner_ata",
    role := "associated-token-account",
    ownerProgram? := some standard.solanaProgramId,
    writable := true,
    derivation? := some "associated-token-address(owner, token_program, mint)"
  },
  {
    name := "recipient",
    role := "recipient-wallet"
  },
  {
    name := "recipient_ata",
    role := "associated-token-account",
    ownerProgram? := some standard.solanaProgramId,
    writable := true,
    derivation? := some "associated-token-address(recipient, token_program, mint)"
  },
  {
    name := "delegate",
    role := "approved-token-delegate"
  }
] ++
(if spec.hasFeature .transferFee then #[
  {
    name := "withdraw_withheld_authority",
    role := "transfer-fee-withdraw-withheld-authority",
    signer := true
  },
  {
    name := "fee_receiver",
    role := "transfer-fee-receiver-wallet"
  },
  {
    name := "fee_receiver_ata",
    role := "transfer-fee-receiver-associated-token-account",
    ownerProgram? := some standard.solanaProgramId,
    writable := true,
    derivation? := some "associated-token-address(fee_receiver, token_program, mint)"
  }
] else #[]) ++
#[
  {
    name := "token_program",
    role := standard.id,
    ownerProgram? := some standard.solanaProgramId
  },
  {
    name := "associated_token_program",
    role := "associated-token-program",
    ownerProgram? := some solanaAssociatedTokenProgramId
  },
  {
    name := "system_program",
    role := "system-program",
    ownerProgram? := some solanaSystemProgramId
  },
  {
    name := "rent_sysvar",
    role := "rent-sysvar",
    ownerProgram? := some solanaRentSysvarId
  }
]

private def solanaToken2022Extensions (spec : TokenSpec) : Array SolanaTokenExtensionPlan :=
  #[] ++
  (if spec.hasFeature .transferFee then #[
    {
      feature := TokenFeature.transferFee.id,
      extension := "transfer_fee_config",
      scope := "mint",
      initInstruction := "initialize_transfer_fee_config",
      requiresConfig := true,
      notes := #[
        "Requires transfer-fee config authority and withdraw-withheld authority.",
        "Transfers should use checked token instructions so the mint decimals are explicit."
      ]
    }
  ] else #[]) ++
  (if spec.hasFeature .nonTransferable then #[
    {
      feature := TokenFeature.nonTransferable.id,
      extension := "non_transferable",
      scope := "mint",
      initInstruction := "initialize_non_transferable_mint",
      notes := #[
        "Minted tokens cannot later be moved by Transfer or TransferChecked."
      ]
    }
  ] else #[]) ++
  (if spec.hasFeature .confidentialTransfer then #[
    {
      feature := TokenFeature.confidentialTransfer.id,
      extension := "confidential_transfer_mint",
      scope := "mint-and-token-account",
      initInstruction := "initialize_confidential_transfer_mint",
      requiresConfig := true,
      notes := #[
        "Requires confidential transfer authority and account-side confidential state setup."
      ]
    }
  ] else #[]) ++
  (if spec.hasFeature .transferHook then #[
    {
      feature := TokenFeature.transferHook.id,
      extension := "transfer_hook",
      scope := "mint",
      initInstruction := "initialize_transfer_hook",
      requiresConfig := true,
      notes := #[
        "Requires a transfer-hook program id; ProofForge should generate or reference that program explicitly."
      ]
    }
  ] else #[]) ++
  (if spec.hasFeature .metadataPointer then #[
    {
      feature := TokenFeature.metadataPointer.id,
      extension := "metadata_pointer",
      scope := "mint",
      initInstruction := "initialize_metadata_pointer",
      requiresConfig := true,
      notes := #[
        "Points to a metadata program account for the mint."
      ]
    }
  ] else #[]) ++
  (if spec.hasFeature .defaultAccountState then #[
    {
      feature := TokenFeature.defaultAccountState.id,
      extension := "default_account_state",
      scope := "mint",
      initInstruction := "initialize_default_account_state",
      requiresConfig := true,
      notes := #[
        "Sets the default state (frozen/unfrozen) for new token accounts."
      ]
    }
  ] else #[]) ++
  (if spec.hasFeature .immutableOwner then #[
    {
      feature := TokenFeature.immutableOwner.id,
      extension := "immutable_owner",
      scope := "account",
      initInstruction := "initialize_immutable_owner",
      requiresConfig := false,
      notes := #[
        "Marks token accounts as having an immutable owner; set at account creation."
      ]
    }
  ] else #[])

private def solanaExtensionInstructions (standard : TokenStandard)
    (extensions : Array SolanaTokenExtensionPlan) : Array SolanaTokenInstructionPlan :=
  extensions.mapIdx fun index extension => {
    order := index + 1,
    name := extension.initInstruction,
    operation := "token-2022.extension." ++ extension.feature,
    programId := standard.solanaProgramId,
    accounts := #["mint", "mint_authority", "token_program"],
    params :=
      if extension.requiresConfig then
        #[param "config" "extension-config" "token_spec.features"]
      else
        #[],
    feature? := some extension.feature,
    token2022Only := true
  }

private def solanaBaseInstructions (spec : TokenSpec) (standard : TokenStandard)
    (extensionCount : Nat) : Array SolanaTokenInstructionPlan :=
  let programId := standard.solanaProgramId
  #[
    {
      order := 0,
      name := "create_mint_account",
      operation := "system.create_account",
      programId := solanaSystemProgramId,
      accounts := #["payer", "mint", "system_program"],
      params := #[param "space" "usize" "mint_size(extensions)", param "lamports" "u64" "rent_exemption"]
    },
    {
      order := 1 + extensionCount,
      name := "initialize_mint",
      operation := "spl-token.initialize_mint",
      programId := programId,
      accounts := #["mint", "rent_sysvar", "token_program"],
      params := #[param "decimals" "u8" "token.decimals", param "mintAuthority" "pubkey" "mint_authority"]
    },
    {
      order := 2 + extensionCount,
      name := "create_owner_ata",
      operation := "associated-token.create",
      programId := solanaAssociatedTokenProgramId,
      accounts := #["payer", "owner_ata", "owner", "mint", "system_program", "token_program", "associated_token_program"]
    },
    {
      order := 3 + extensionCount,
      name := "create_recipient_ata",
      operation := "associated-token.create",
      programId := solanaAssociatedTokenProgramId,
      accounts := #["payer", "recipient_ata", "recipient", "mint", "system_program", "token_program", "associated_token_program"]
    },
    {
      order := 4 + extensionCount,
      name := "mint_to_initial_supply",
      operation := "spl-token.mint_to",
      programId := programId,
      accounts := #["mint", "owner_ata", "mint_authority", "token_program"],
      params := #[param "amount" "u64" "token.initialSupply"],
      feature? := some TokenFeature.mintable.id
    },
    {
      order := 5 + extensionCount,
      name := "mint_to",
      operation := "spl-token.mint_to",
      programId := programId,
      accounts := #["mint", "owner_ata", "mint_authority", "token_program"],
      params := #[param "amount" "u64" "instruction.amount"],
      feature? := some TokenFeature.mintable.id
    },
    {
      order := 6 + extensionCount,
      name := "transfer_checked",
      operation := "spl-token.transfer_checked",
      programId := programId,
      accounts := #["owner_ata", "mint", "recipient_ata", "owner", "token_program"],
      params := #[param "amount" "u64" "instruction.amount", param "decimals" "u8" "token.decimals"]
    },
    {
      order := 7 + extensionCount,
      name := "approve_delegate",
      operation := "spl-token.approve",
      programId := programId,
      accounts := #["owner_ata", "delegate", "owner", "token_program"],
      params := #[param "amount" "u64" "instruction.amount"]
    },
    {
      order := 8 + extensionCount,
      name := "burn",
      operation := "spl-token.burn",
      programId := programId,
      accounts := #["owner_ata", "mint", "owner", "token_program"],
      params := #[param "amount" "u64" "instruction.amount"]
    },
    {
      order := 9 + extensionCount,
      name := "revoke_delegate",
      operation := "spl-token.revoke",
      programId := programId,
      accounts := #["owner_ata", "owner", "token_program"]
    },
    {
      order := 10 + extensionCount,
      name := "set_mint_authority",
      operation := "spl-token.set_authority",
      programId := programId,
      accounts := #["mint", "mint_authority", "token_program"],
      params := #[param "authorityType" "enum" "mint_tokens", param "newAuthority" "pubkey|null" "token.authorityPolicy"]
    }
  ].filter fun instruction =>
    (instruction.name != "mint_to_initial_supply" || spec.initialSupply?.isSome) &&
    (instruction.name != "mint_to" || spec.hasFeature .mintable)

private def solanaTransferFeeCollectionInstructions (spec : TokenSpec) (standard : TokenStandard)
    (startOrder : Nat) : Array SolanaTokenInstructionPlan :=
  if spec.hasFeature .transferFee then
    #[
      {
        order := startOrder,
        name := "transfer_checked_with_fee",
        operation := "token-2022.transfer_checked_with_fee",
        programId := standard.solanaProgramId,
        accounts := #["owner_ata", "mint", "recipient_ata", "owner", "token_program"],
        params := #[
          param "amount" "u64" "instruction.amount",
          param "decimals" "u8" "token.decimals",
          param "fee" "u64" "calculated_transfer_fee"
        ],
        feature? := some TokenFeature.transferFee.id,
        token2022Only := true
      },
      {
        order := startOrder + 1,
        name := "withdraw_withheld_tokens_from_accounts",
        operation := "token-2022.withdraw_withheld_tokens_from_accounts",
        programId := standard.solanaProgramId,
        accounts := #["mint", "fee_receiver_ata", "withdraw_withheld_authority", "recipient_ata", "token_program"],
        params := #[param "sources" "token-account[]" "accounts_with_withheld_transfer_fees"],
        feature? := some TokenFeature.transferFee.id,
        token2022Only := true
      },
      {
        order := startOrder + 2,
        name := "harvest_withheld_tokens_to_mint",
        operation := "token-2022.harvest_withheld_tokens_to_mint",
        programId := standard.solanaProgramId,
        accounts := #["mint", "recipient_ata", "token_program"],
        params := #[param "sources" "token-account[]" "accounts_with_withheld_transfer_fees"],
        feature? := some TokenFeature.transferFee.id,
        token2022Only := true
      },
      {
        order := startOrder + 3,
        name := "withdraw_withheld_tokens_from_mint",
        operation := "token-2022.withdraw_withheld_tokens_from_mint",
        programId := standard.solanaProgramId,
        accounts := #["mint", "fee_receiver_ata", "withdraw_withheld_authority", "token_program"],
        feature? := some TokenFeature.transferFee.id,
        token2022Only := true
      }
    ]
  else
    #[]

private def solanaAuthorityChanges (spec : TokenSpec) : Array SolanaTokenAuthorityChangePlan :=
  #[
    {
      name := "mint-authority-policy",
      authorityType := "mint_tokens",
      currentAuthority := "mint_authority",
      newAuthority := if spec.hasFeature .mintable then "configured_mint_authority_or_pda" else "null",
      operation := "spl-token.set_authority",
      reason :=
        if spec.hasFeature .mintable then
          "Mintable tokens keep or hand off mint authority to an explicit wallet/PDA."
        else
          "Non-mintable tokens revoke mint authority after initial supply is minted."
    },
    {
      name := "freeze-authority-policy",
      authorityType := "freeze_account",
      currentAuthority := "mint_authority",
      newAuthority := "null",
      operation := "spl-token.set_authority",
      reason := "Freeze authority is not enabled by default for fungible TokenSpec plans."
    }
  ]

def solanaTokenDeploymentPlan (spec : TokenSpec) : Except String SolanaTokenDeploymentPlan := do
  validateSolanaTokenFeatures spec
  let standard := if spec.needsToken2022 then TokenStandard.splToken2022 else TokenStandard.splToken
  let extensions := if standard == .splToken2022 then solanaToken2022Extensions spec else #[]
  let extensionInstructions := solanaExtensionInstructions standard extensions
  let baseInstructions := solanaBaseInstructions spec standard extensions.size
  let createMintInstructions := baseInstructions.filter fun instruction => instruction.order == 0
  let postExtensionInstructions := baseInstructions.filter fun instruction => instruction.order != 0
  let transferFeeInstructions :=
    solanaTransferFeeCollectionInstructions spec standard (1 + extensions.size + postExtensionInstructions.size)
  .ok {
    standard := standard
    tokenProgramId := standard.solanaProgramId
    associatedTokenProgramId := solanaAssociatedTokenProgramId
    systemProgramId := solanaSystemProgramId
    rentSysvarId := solanaRentSysvarId
    accounts := solanaTokenAccounts spec standard
    instructions := createMintInstructions ++ extensionInstructions ++ postExtensionInstructions ++ transferFeeInstructions
    extensions := extensions
    authorityChanges := solanaAuthorityChanges spec
    references :=
      #[
      { label := "Solana tokens", url := "https://solana.com/docs/tokens" },
      { label := "Create associated token account", url := "https://solana.com/docs/tokens/basics/create-token-account" },
      { label := "Mint tokens", url := "https://solana.com/docs/tokens/basics/mint-tokens" },
      { label := "Transfer tokens", url := "https://solana.com/docs/tokens/basics/transfer-tokens" },
      { label := "Token Extensions / Token-2022", url := "https://solana.com/docs/tokens/extensions" }
      ] ++
      (if spec.hasFeature .transferFee then
        #[{ label := "Token-2022 transfer fees", url := "https://solana.com/docs/tokens/extensions/transfer-fees" }]
      else #[]) ++
      (if spec.hasFeature .nonTransferable then
        #[{ label := "Token-2022 non-transferable tokens", url := "https://solana.com/docs/tokens/extensions/non-transferrable-tokens" }]
      else #[])
  }

def solanaTokenPlan (target : TargetProfile) (spec : TokenSpec) : TokenPlan :=
  let useToken2022 := spec.needsToken2022
  {
    targetId := target.id
    standard := if useToken2022 then .splToken2022 else .splToken
    artifactKind := if useToken2022 then .solanaToken2022Plan else .solanaSplTokenPlan
    capabilities := #[
      .accountExplicit,
      .crosscallCpi,
      .storagePda,
      .eventsEmit,
      .controlConditional,
      .assertions
    ]
    operations := baseSplTokenOperations ++ token2022FeatureOperations spec
    notes := #[
      "Solana lowers a TokenSpec into an SPL Token or Token-2022 mint/account/CPI plan.",
      "Standard Solana tokens use the deployed token program; ProofForge should not generate a per-token SPL contract by default.",
      "Custom token behavior should use Token-2022 extensions, transfer hooks, or a separate wrapper/authority program."
    ]
  }

def planForTarget (target : TargetProfile) (spec : TokenSpec) : Except String TokenPlan :=
  if target.family == .evm then
    .ok (evmErc20Plan target spec)
  else if target.family == .solana then
    validateSolanaTokenFeatures spec *> .ok (solanaTokenPlan target spec)
  else
    .error s!"target `{target.id}` does not have a TokenSpec lowering plan yet"

end ProofForge.Contract.Token
