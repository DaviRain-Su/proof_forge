import ProofForge.Frontend.Surface

/-! Internal EVM ERC-4626 frontend materialization. Portable arithmetic, storage, CFG,
events, and crosscalls normalize to Canonical Core. EVM ABI selectors and the
IERC20 method mapping are introduced only by this target-owned materializer. -/

namespace ProofForge.Frontend.Materialize.Evm.ERC4626

open ProofForge.Frontend.Surface

private def u64 (value : Nat) : SurfaceExpr := .literal (.u64Lit value)
private def bool (value : Bool) : SurfaceExpr := .literal (.boolLit value)
private def zeroAddress : SurfaceExpr := .literal (.addressLit "0")
private def sender : SurfaceExpr := .contextRead .sender
private def self : SurfaceExpr := .contextRead .contractAddress
private def maxU64 : SurfaceExpr := u64 0xffffffffffffffff
private def uint256Param (name : String) : SurfaceParam :=
  { name, type := .u64, abiWord? := some "uint256" }

private def add (lhs rhs : SurfaceExpr) : SurfaceExpr := .arith .add true lhs rhs
private def sub (lhs rhs : SurfaceExpr) : SurfaceExpr := .arith .sub true lhs rhs
private def mul (lhs rhs : SurfaceExpr) : SurfaceExpr := .arith .mul true lhs rhs
private def div (lhs rhs : SurfaceExpr) : SurfaceExpr := .arith .div true lhs rhs
private def mod (lhs rhs : SurfaceExpr) : SurfaceExpr := .arith .mod false lhs rhs
private def eq (lhs rhs : SurfaceExpr) : SurfaceExpr := .compare .eq lhs rhs
private def ne (lhs rhs : SurfaceExpr) : SurfaceExpr := .compare .ne lhs rhs
private def lt (lhs rhs : SurfaceExpr) : SurfaceExpr := .compare .lt lhs rhs
private def ge (lhs rhs : SurfaceExpr) : SurfaceExpr := .compare .ge lhs rhs
private def positive (value : SurfaceExpr) : SurfaceExpr := ne value (u64 0)

private def allowanceKey (owner spender : SurfaceExpr) : SurfaceExpr :=
  .hashPair (.hash owner) (.hash spender)

private def assetCall (method : String) (args : Array SurfaceExpr) : SurfaceExpr :=
  .crosscall .invoke (.stateRead "asset") (.literal (.stringLit method)) args .u64

private def acquireLock : Array SurfaceStmt := #[
  .bind "lock_held" .bool (.stateRead "locked"),
  .assert (.unary .not (.local "lock_held")) "reentrant call",
  .stateWrite "locked" (bool true)
]

private def releaseLock : SurfaceStmt := .stateWrite "locked" (bool false)

private def convertToSharesIntoScratch (amount : SurfaceExpr) : Array SurfaceStmt := #[
  .stateWrite "convert_scratch" amount,
  .bind "convert_supply" .u64 (.stateRead "total_supply"),
  .branch (positive (.local "convert_supply")) #[
    .bind "convert_assets" .u64 (.stateRead "total_assets"),
    .assert (positive (.local "convert_assets")) "zero totalAssets",
    .stateWrite "convert_scratch"
      (div (mul amount (.local "convert_supply")) (.local "convert_assets"))
  ] #[]
]

private def convertToAssetsIntoScratch (amount : SurfaceExpr) : Array SurfaceStmt := #[
  .stateWrite "convert_scratch" amount,
  .bind "convert_supply" .u64 (.stateRead "total_supply"),
  .branch (positive (.local "convert_supply")) #[
    .bind "convert_assets" .u64 (.stateRead "total_assets"),
    .assert (positive (.local "convert_assets")) "zero totalAssets",
    .stateWrite "convert_scratch"
      (div (mul amount (.local "convert_assets")) (.local "convert_supply"))
  ] #[]
]

private def convertToSharesUpIntoScratch (amount : SurfaceExpr) : Array SurfaceStmt := #[
  .stateWrite "convert_scratch" amount,
  .bind "up_supply" .u64 (.stateRead "total_supply"),
  .branch (positive (.local "up_supply")) #[
    .bind "up_assets" .u64 (.stateRead "total_assets"),
    .assert (positive (.local "up_assets")) "zero totalAssets",
    .bind "up_numerator" .u64 (mul amount (.local "up_supply")),
    .bind "up_quotient" .u64 (div (.local "up_numerator") (.local "up_assets")),
    .stateWrite "convert_scratch" (.local "up_quotient"),
    .branch (positive (mod (.local "up_numerator") (.local "up_assets"))) #[
      .stateWrite "convert_scratch" (add (.local "up_quotient") (u64 1))
    ] #[]
  ] #[]
]

private def convertToAssetsUpIntoScratch (amount : SurfaceExpr) : Array SurfaceStmt := #[
  .stateWrite "convert_scratch" amount,
  .bind "up_supply" .u64 (.stateRead "total_supply"),
  .branch (positive (.local "up_supply")) #[
    .bind "up_assets" .u64 (.stateRead "total_assets"),
    .assert (positive (.local "up_assets")) "zero totalAssets",
    .bind "up_numerator" .u64 (mul amount (.local "up_assets")),
    .bind "up_quotient" .u64 (div (.local "up_numerator") (.local "up_supply")),
    .stateWrite "convert_scratch" (.local "up_quotient"),
    .branch (positive (mod (.local "up_numerator") (.local "up_supply"))) #[
      .stateWrite "convert_scratch" (add (.local "up_quotient") (u64 1))
    ] #[]
  ] #[]
]

private def applyFee (gross : SurfaceExpr) : Array SurfaceStmt := #[
  .stateWrite "fee_scratch" (u64 0),
  .bind "apply_fee_bps" .u64 (.stateRead "fee_bps"),
  .branch (positive (.local "apply_fee_bps")) #[
    .stateWrite "fee_scratch" (div (mul gross (.local "apply_fee_bps")) (u64 10000)),
    .stateWrite "convert_scratch" (sub gross (.stateRead "fee_scratch"))
  ] #[]
]

private def grossFromNetIntoScratch (net : SurfaceExpr) : Array SurfaceStmt := #[
  .stateWrite "convert_scratch" net,
  .bind "gross_bps" .u64 (.stateRead "fee_bps"),
  .branch (positive (.local "gross_bps")) #[
    .assert (lt (.local "gross_bps") (u64 10000)) "feeBps 10000 blocks mint",
    .stateWrite "convert_scratch"
      (div (mul net (u64 10000)) (sub (u64 10000) (.local "gross_bps")))
  ] #[]
]

private def pullAssets (stem : String) (amount : SurfaceExpr) : Array SurfaceStmt := #[
  .bind (stem ++ "_before") .u64 (assetCall "balanceOf" #[.stateRead "vault_self"]),
  .bind (stem ++ "_ok") .u64
    (assetCall "transferFrom" #[sender, .stateRead "vault_self", amount]),
  .assert (eq (.local (stem ++ "_ok")) (u64 1)) "ERC20 operation returned false",
  .bind (stem ++ "_after") .u64 (assetCall "balanceOf" #[.stateRead "vault_self"]),
  .bind (stem ++ "_actual") .u64
    (sub (.local (stem ++ "_after")) (.local (stem ++ "_before"))),
  .assert (positive (.local (stem ++ "_actual"))) "zero actual assets"
]

private def pushAssetsMeasured (stem : String) (recipient amount : SurfaceExpr) : Array SurfaceStmt := #[
  .bind (stem ++ "_vault_before") .u64 (assetCall "balanceOf" #[.stateRead "vault_self"]),
  .bind (stem ++ "_recv_before") .u64 (assetCall "balanceOf" #[recipient]),
  .bind (stem ++ "_push_ok") .u64 (assetCall "transfer" #[recipient, amount]),
  .assert (eq (.local (stem ++ "_push_ok")) (u64 1)) "ERC20 operation returned false",
  .bind (stem ++ "_fee") .u64 (.stateRead "fee_scratch"),
  .branch (positive (.local (stem ++ "_fee"))) #[
    .bind (stem ++ "_fee_recipient") .address (.stateRead "fee_recipient"),
    .assert (ne (.local (stem ++ "_fee_recipient")) zeroAddress) "zero feeRecipient",
    .bind (stem ++ "_fee_ok") .u64
      (assetCall "transfer" #[.local (stem ++ "_fee_recipient"), .local (stem ++ "_fee")]),
    .assert (eq (.local (stem ++ "_fee_ok")) (u64 1)) "ERC20 operation returned false"
  ] #[],
  .bind (stem ++ "_vault_after") .u64 (assetCall "balanceOf" #[.stateRead "vault_self"]),
  .bind (stem ++ "_recv_after") .u64 (assetCall "balanceOf" #[recipient]),
  .bind (stem ++ "_actual_left") .u64
    (sub (.local (stem ++ "_vault_before")) (.local (stem ++ "_vault_after"))),
  .bind (stem ++ "_actual_recv") .u64
    (sub (.local (stem ++ "_recv_after")) (.local (stem ++ "_recv_before"))),
  .assert (positive (.local (stem ++ "_actual_left"))) "zero actual assets left vault"
]

private def mintFeeShares : Array SurfaceStmt := #[
  .bind "mint_fee" .u64 (.stateRead "fee_scratch"),
  .branch (positive (.local "mint_fee")) #[
    .bind "mint_fee_recipient" .address (.stateRead "fee_recipient"),
    .assert (ne (.local "mint_fee_recipient") zeroAddress) "zero feeRecipient",
    .bind "mint_fee_balance" .u64 (.mapRead "share_balances" (.local "mint_fee_recipient")),
    .mapWrite "share_balances" (.local "mint_fee_recipient")
      (add (.local "mint_fee_balance") (.local "mint_fee")),
    .emit "Transfer" #[zeroAddress, .local "mint_fee_recipient", .local "mint_fee"]
  ] #[]
]

private def simpleGetter (name selector stateName : String) (type : SurfaceType)
    (returnAbiWord? : Option String := none) : SurfaceEntrypoint := {
  name, kind := .function, mutability := .view, selector? := some selector,
  params := #[], retType := type, returnAbiWord?,
  body := #[.returnExpr (.stateRead stateName)]
}

private def conversionQuery (name selector param : String) (toShares : Bool) : SurfaceEntrypoint := {
  name, kind := .function, mutability := .view, selector? := some selector,
  params := #[uint256Param param], retType := .u64,
  returnAbiWord? := some "uint256",
  body := #[
    .bind "query_supply" .u64 (.stateRead "total_supply"),
    .branch (positive (.local "query_supply")) #[
      .bind "query_assets" .u64 (.stateRead "total_assets"),
      .assert (positive (.local "query_assets")) "zero totalAssets",
      .returnExpr (if toShares then
        div (mul (.local param) (.local "query_supply")) (.local "query_assets")
      else div (mul (.local param) (.local "query_assets")) (.local "query_supply"))
    ] #[.returnExpr (.local param)]
  ]
}

private def returnNetAfterFee (stem : String) (gross : SurfaceExpr) : Array SurfaceStmt := #[
  .bind (stem ++ "_bps") .u64 (.stateRead "fee_bps"),
  .branch (positive (.local (stem ++ "_bps"))) #[
    .returnExpr (sub gross (div (mul gross (.local (stem ++ "_bps"))) (u64 10000)))
  ] #[.returnExpr gross]
]

private def returnAssetsUp (stem : String) (shares : SurfaceExpr) : Array SurfaceStmt := #[
  .bind (stem ++ "_supply") .u64 (.stateRead "total_supply"),
  .branch (positive (.local (stem ++ "_supply"))) #[
    .bind (stem ++ "_assets") .u64 (.stateRead "total_assets"),
    .assert (positive (.local (stem ++ "_assets"))) "zero totalAssets",
    .bind (stem ++ "_numerator") .u64
      (mul shares (.local (stem ++ "_assets"))),
    .bind (stem ++ "_quotient") .u64
      (div (.local (stem ++ "_numerator")) (.local (stem ++ "_supply"))),
    .branch (positive (mod (.local (stem ++ "_numerator")) (.local (stem ++ "_supply")))) #[
      .returnExpr (add (.local (stem ++ "_quotient")) (u64 1))
    ] #[.returnExpr (.local (stem ++ "_quotient"))]
  ] #[.returnExpr shares]
]

private def returnSharesUp (stem : String) (assets : SurfaceExpr) : Array SurfaceStmt := #[
  .bind (stem ++ "_supply") .u64 (.stateRead "total_supply"),
  .branch (positive (.local (stem ++ "_supply"))) #[
    .bind (stem ++ "_assets") .u64 (.stateRead "total_assets"),
    .assert (positive (.local (stem ++ "_assets"))) "zero totalAssets",
    .bind (stem ++ "_numerator") .u64
      (mul assets (.local (stem ++ "_supply"))),
    .bind (stem ++ "_quotient") .u64
      (div (.local (stem ++ "_numerator")) (.local (stem ++ "_assets"))),
    .branch (positive (mod (.local (stem ++ "_numerator")) (.local (stem ++ "_assets")))) #[
      .returnExpr (add (.local (stem ++ "_quotient")) (u64 1))
    ] #[.returnExpr (.local (stem ++ "_quotient"))]
  ] #[.returnExpr assets]
]

private def withMin (lhs rhs : SurfaceExpr)
    (next : SurfaceExpr → Array SurfaceStmt) : Array SurfaceStmt :=
  #[.branch (lt lhs rhs) (next lhs) (next rhs)]

private def maxDepositFinish (assetCap grossCap : SurfaceExpr) : Array SurfaceStmt := #[
  .bind "max_deposit_supply" .u64 (.stateRead "total_supply"),
  .branch (positive (.local "max_deposit_supply")) #[
    .bind "max_deposit_assets" .u64 (.stateRead "total_assets"),
    .branch (positive (.local "max_deposit_assets"))
      (withMin grossCap (div maxU64 (.local "max_deposit_assets")) fun safeGross => #[
        .bind "max_deposit_reverse" .u64
          (div (mul safeGross (.local "max_deposit_assets")) (.local "max_deposit_supply"))
      ] ++ withMin assetCap (.local "max_deposit_reverse") fun result =>
        #[.returnExpr result])
      #[.returnExpr (u64 0)]
  ] (withMin assetCap grossCap fun result => #[.returnExpr result])
]

private def maxDepositBody : Array SurfaceStmt := #[
  .branch (eq (.local "who") zeroAddress) #[.returnExpr (u64 0)] #[
    .bind "max_deposit_bps" .u64 (.stateRead "fee_bps"),
    .branch (ge (.local "max_deposit_bps") (u64 10000)) #[.returnExpr (u64 0)] #[
      .bind "max_deposit_assets_now" .u64 (.stateRead "total_assets"),
      .bind "max_deposit_supply_now" .u64 (.stateRead "total_supply"),
      .bind "max_deposit_receiver_bal" .u64 (.mapRead "share_balances" (.local "who")),
      .bind "max_deposit_asset_cap" .u64 (sub maxU64 (.local "max_deposit_assets_now")),
      .bind "max_deposit_supply_cap" .u64 (sub maxU64 (.local "max_deposit_supply_now")),
      .bind "max_deposit_receiver_cap" .u64 (sub maxU64 (.local "max_deposit_receiver_bal")),
      .branch (positive (.local "max_deposit_bps"))
        (#[
          .bind "max_deposit_fee_recipient" .address (.stateRead "fee_recipient"),
          .bind "max_deposit_fee_bal" .u64
            (.mapRead "share_balances" (.local "max_deposit_fee_recipient")),
          .bind "max_deposit_fee_cap" .u64 (sub maxU64 (.local "max_deposit_fee_bal")),
          .bind "max_deposit_mul_cap" .u64 (div maxU64 (.local "max_deposit_bps"))
        ] ++ withMin (.local "max_deposit_supply_cap") (.local "max_deposit_receiver_cap") fun cap1 =>
          withMin cap1 (.local "max_deposit_fee_cap") fun cap2 =>
            withMin cap2 (.local "max_deposit_mul_cap") fun grossCap =>
              maxDepositFinish (.local "max_deposit_asset_cap") grossCap)
        (withMin (.local "max_deposit_supply_cap") (.local "max_deposit_receiver_cap") fun grossCap =>
          maxDepositFinish (.local "max_deposit_asset_cap") grossCap)
    ]
  ]
]

private def maxMintFinish (assetCap grossCap bps : SurfaceExpr) : Array SurfaceStmt := #[
  .bind "max_mint_supply" .u64 (.stateRead "total_supply"),
  .branch (positive (.local "max_mint_supply")) #[
    .bind "max_mint_assets" .u64 (.stateRead "total_assets"),
    .branch (positive (.local "max_mint_assets"))
      (withMin assetCap (div maxU64 (.local "max_mint_supply")) fun safeAssets => #[
        .bind "max_mint_from_assets" .u64
          (div (mul safeAssets (.local "max_mint_supply")) (.local "max_mint_assets"))
      ] ++ withMin grossCap (.local "max_mint_from_assets") fun finalGross =>
        #[.branch (positive bps) #[
          .returnExpr (sub finalGross (div (mul finalGross bps) (u64 10000)))
        ] #[.returnExpr finalGross]])
      #[.returnExpr (u64 0)]
  ] (withMin assetCap grossCap fun finalGross => #[
    .branch (positive bps) #[
      .returnExpr (sub finalGross (div (mul finalGross bps) (u64 10000)))
    ] #[.returnExpr finalGross]])
]

private def maxMintBody : Array SurfaceStmt := #[
  .branch (eq (.local "who") zeroAddress) #[.returnExpr (u64 0)] #[
    .bind "max_mint_bps" .u64 (.stateRead "fee_bps"),
    .branch (ge (.local "max_mint_bps") (u64 10000)) #[.returnExpr (u64 0)] #[
      .bind "max_mint_assets_now" .u64 (.stateRead "total_assets"),
      .bind "max_mint_supply_now" .u64 (.stateRead "total_supply"),
      .bind "max_mint_receiver_bal" .u64 (.mapRead "share_balances" (.local "who")),
      .bind "max_mint_asset_cap" .u64 (sub maxU64 (.local "max_mint_assets_now")),
      .bind "max_mint_supply_cap" .u64 (sub maxU64 (.local "max_mint_supply_now")),
      .bind "max_mint_receiver_cap" .u64 (sub maxU64 (.local "max_mint_receiver_bal")),
      .branch (positive (.local "max_mint_bps"))
        (#[
          .bind "max_mint_fee_recipient" .address (.stateRead "fee_recipient"),
          .bind "max_mint_fee_bal" .u64
            (.mapRead "share_balances" (.local "max_mint_fee_recipient")),
          .bind "max_mint_fee_cap" .u64 (sub maxU64 (.local "max_mint_fee_bal")),
          .bind "max_mint_mul_cap" .u64 (div maxU64 (.local "max_mint_bps"))
        ] ++ withMin (.local "max_mint_supply_cap") (.local "max_mint_receiver_cap") fun cap1 =>
          withMin cap1 (.local "max_mint_fee_cap") fun cap2 =>
            withMin cap2 (.local "max_mint_mul_cap") fun grossCap =>
              maxMintFinish (.local "max_mint_asset_cap") grossCap (.local "max_mint_bps"))
        (withMin (.local "max_mint_supply_cap") (.local "max_mint_receiver_cap") fun grossCap =>
          maxMintFinish (.local "max_mint_asset_cap") grossCap (.local "max_mint_bps"))
    ]
  ]
]

private def maxExitBody (redeem : Bool) : Array SurfaceStmt := #[
  .bind "max_exit_bps" .u64 (.stateRead "fee_bps"),
  .branch (ge (.local "max_exit_bps") (u64 10000)) #[.returnExpr (u64 0)] #[
    .bind "max_exit_supply" .u64 (.stateRead "total_supply"),
    .bind "max_exit_assets" .u64 (.stateRead "total_assets"),
    .bind "max_exit_balance" .u64 (.mapRead "share_balances" (.local "holder")),
    .branch (positive (.local "max_exit_supply")) #[
      .branch (positive (.local "max_exit_assets"))
        (withMin (.local "max_exit_balance") (.local "max_exit_supply") fun shareCap =>
          withMin shareCap (div maxU64 (.local "max_exit_assets")) fun safeShares => #[
            .bind "max_exit_gross" .u64
              (div (mul safeShares (.local "max_exit_assets")) (.local "max_exit_supply")),
            .branch (positive (.local "max_exit_bps"))
              (withMin (.local "max_exit_gross") (div maxU64 (.local "max_exit_bps")) fun safeGross =>
                if redeem then #[
                  .returnExpr (div (mul safeGross (.local "max_exit_supply")) (.local "max_exit_assets"))
                ] else #[.returnExpr safeGross])
              #[.returnExpr (if redeem then safeShares else .local "max_exit_gross")]
          ])
        #[.returnExpr (u64 0)]
    ] #[.returnExpr (u64 0)]
  ]
]

private def entrypoints : Array SurfaceEntrypoint := #[
  { name := "init", kind := .function, mutability := .call, selector? := some "4b180da9",
    params := #[{ name := "assetAddr", type := .address }, { name := "selfAddr", type := .address },
      uint256Param "feeBpsVal", { name := "feeRecipientAddr", type := .address }],
    retType := .unit, body := #[
      .bind "was_initialized" .bool (.stateRead "initialized"),
      .assert (.unary .not (.local "was_initialized")) "already initialized",
      .assert (ne (.local "assetAddr") zeroAddress) "zero asset",
      .assert (eq (.local "selfAddr") self) "vaultSelf != contractId",
      .assert (ge (u64 10000) (.local "feeBpsVal")) "feeBps > 10000",
      .branch (positive (.local "feeBpsVal")) #[
        .assert (ne (.local "feeRecipientAddr") zeroAddress) "zero feeRecipient"
      ] #[],
      .stateWrite "initialized" (bool true), .stateWrite "asset" (.local "assetAddr"),
      .stateWrite "vault_self" (.local "selfAddr"), .stateWrite "fee_bps" (.local "feeBpsVal"),
      .stateWrite "fee_recipient" (.local "feeRecipientAddr"),
      .stateWrite "total_assets" (u64 0), .stateWrite "total_supply" (u64 0),
      .stateWrite "fee_scratch" (u64 0), .stateWrite "locked" (bool false) ] },
  simpleGetter "asset" "38d52e0f" "asset" .address,
  simpleGetter "totalAssets" "01e1d114" "total_assets" .u64 (some "uint256"),
  simpleGetter "totalSupply" "18160ddd" "total_supply" .u64 (some "uint256"),
  { name := "balanceOf", kind := .function, mutability := .view, selector? := some "70a08231",
    params := #[{ name := "who", type := .address }], retType := .u64,
    returnAbiWord? := some "uint256",
    body := #[.returnExpr (.mapRead "share_balances" (.local "who"))] },
  conversionQuery "convertToShares" "c6e6f592" "assets" true,
  conversionQuery "convertToAssets" "07a2d13a" "shares" false,
  { name := "maxDeposit", kind := .function, mutability := .view,
    selector? := some "402d267d", params := #[{ name := "who", type := .address }],
    retType := .u64, returnAbiWord? := some "uint256", body := maxDepositBody },
  { name := "maxMint", kind := .function, mutability := .view,
    selector? := some "c63d75b6", params := #[{ name := "who", type := .address }],
    retType := .u64, returnAbiWord? := some "uint256", body := maxMintBody },
  { name := "maxWithdraw", kind := .function, mutability := .view,
    selector? := some "ce96cb77", params := #[{ name := "holder", type := .address }],
    retType := .u64, returnAbiWord? := some "uint256", body := maxExitBody false },
  { name := "maxRedeem", kind := .function, mutability := .view,
    selector? := some "d905777e", params := #[{ name := "holder", type := .address }],
    retType := .u64, returnAbiWord? := some "uint256", body := maxExitBody true },
  simpleGetter "feeBps" "24a9d853" "fee_bps" .u64 (some "uint256"),
  simpleGetter "feeRecipient" "46904840" "fee_recipient" .address,
  { name := "previewDeposit", kind := .function, mutability := .view,
    selector? := some "ef8b30f7", params := #[uint256Param "assets"],
    retType := .u64, returnAbiWord? := some "uint256", body := #[
      .bind "preview_deposit_supply" .u64 (.stateRead "total_supply"),
      .branch (positive (.local "preview_deposit_supply"))
        (#[
          .bind "preview_deposit_assets" .u64 (.stateRead "total_assets"),
          .assert (positive (.local "preview_deposit_assets")) "zero totalAssets",
          .bind "preview_deposit_gross" .u64
            (div (mul (.local "assets") (.local "preview_deposit_supply"))
              (.local "preview_deposit_assets"))
        ] ++ returnNetAfterFee "preview_deposit" (.local "preview_deposit_gross"))
        (returnNetAfterFee "preview_deposit_empty" (.local "assets"))
    ] },
  { name := "previewMint", kind := .function, mutability := .view,
    selector? := some "b3d7f6b9", params := #[uint256Param "shares"],
    retType := .u64, returnAbiWord? := some "uint256", body := #[
      .bind "preview_mint_bps" .u64 (.stateRead "fee_bps"),
      .branch (positive (.local "preview_mint_bps"))
        (#[
          .assert (lt (.local "preview_mint_bps") (u64 10000)) "feeBps 10000 blocks mint",
          .bind "preview_mint_gross" .u64
            (div (mul (.local "shares") (u64 10000))
              (sub (u64 10000) (.local "preview_mint_bps")))
        ] ++ returnAssetsUp "preview_mint" (.local "preview_mint_gross"))
        (returnAssetsUp "preview_mint_zero_fee" (.local "shares"))
    ] },
  { name := "previewWithdraw", kind := .function, mutability := .view,
    selector? := some "0a28a477", params := #[uint256Param "assets"],
    retType := .u64, returnAbiWord? := some "uint256",
    body := returnSharesUp "preview_withdraw" (.local "assets") },
  { name := "previewRedeem", kind := .function, mutability := .view,
    selector? := some "4cdad506", params := #[uint256Param "shares"],
    retType := .u64, returnAbiWord? := some "uint256", body := #[
      .bind "preview_redeem_supply" .u64 (.stateRead "total_supply"),
      .branch (positive (.local "preview_redeem_supply"))
        (#[
          .bind "preview_redeem_assets" .u64 (.stateRead "total_assets"),
          .assert (positive (.local "preview_redeem_assets")) "zero totalAssets",
          .bind "preview_redeem_gross" .u64
            (div (mul (.local "shares") (.local "preview_redeem_assets"))
              (.local "preview_redeem_supply"))
        ] ++ returnNetAfterFee "preview_redeem" (.local "preview_redeem_gross"))
        (returnNetAfterFee "preview_redeem_empty" (.local "shares"))
    ] },
  { name := "deposit", kind := .function, mutability := .call, selector? := some "6e553f65",
    params := #[uint256Param "assets", { name := "receiver", type := .address }],
    retType := .u64, returnAbiWord? := some "uint256", body := acquireLock ++ #[
      .assert (ne (.local "receiver") zeroAddress) "zero receiver",
      .assert (positive (.local "assets")) "zero assets" ] ++
      pullAssets "deposit" (.local "assets") ++
      convertToSharesIntoScratch (.local "deposit_actual") ++ #[
      .bind "deposit_gross" .u64 (.stateRead "convert_scratch"),
      .assert (positive (.local "deposit_gross")) "zero shares" ] ++
      applyFee (.local "deposit_gross") ++ #[
      .bind "deposit_shares" .u64 (.stateRead "convert_scratch"),
      .assert (positive (.local "deposit_shares")) "zero net shares",
      .bind "deposit_ta" .u64 (.stateRead "total_assets"),
      .bind "deposit_ts" .u64 (.stateRead "total_supply"),
      .bind "deposit_bal" .u64 (.mapRead "share_balances" (.local "receiver")),
      .stateWrite "total_assets" (add (.local "deposit_ta") (.local "deposit_actual")),
      .stateWrite "total_supply" (add (.local "deposit_ts") (.local "deposit_gross")),
      .mapWrite "share_balances" (.local "receiver")
        (add (.local "deposit_bal") (.local "deposit_shares")) ] ++ mintFeeShares ++ #[
      .emit "Deposit" #[sender, .local "receiver", .local "deposit_actual", .local "deposit_shares"],
      .emit "Transfer" #[zeroAddress, .local "receiver", .local "deposit_shares"],
      releaseLock, .returnExpr (.local "deposit_shares") ] },
  { name := "mint", kind := .function, mutability := .call, selector? := some "94bf804d",
    params := #[uint256Param "shares", { name := "receiver", type := .address }],
    retType := .u64, returnAbiWord? := some "uint256", body := acquireLock ++ #[
      .assert (ne (.local "receiver") zeroAddress) "zero receiver",
      .assert (positive (.local "shares")) "zero shares" ] ++
      grossFromNetIntoScratch (.local "shares") ++ #[
      .bind "mint_gross" .u64 (.stateRead "convert_scratch"),
      .assert (positive (.local "mint_gross")) "zero gross shares" ] ++
      convertToAssetsUpIntoScratch (.local "mint_gross") ++ #[
      .bind "mint_assets" .u64 (.stateRead "convert_scratch"),
      .assert (positive (.local "mint_assets")) "zero assets" ] ++
      pullAssets "mint" (.local "mint_assets") ++
      convertToSharesIntoScratch (.local "mint_actual") ++ #[
      .bind "mint_available" .u64 (.stateRead "convert_scratch"),
      .assert (ge (.local "mint_available") (.local "mint_gross")) "insufficient actual assets",
      .stateWrite "fee_scratch" (sub (.local "mint_gross") (.local "shares")),
      .bind "mint_ta" .u64 (.stateRead "total_assets"),
      .bind "mint_ts" .u64 (.stateRead "total_supply"),
      .bind "mint_bal" .u64 (.mapRead "share_balances" (.local "receiver")),
      .stateWrite "total_assets" (add (.local "mint_ta") (.local "mint_actual")),
      .stateWrite "total_supply" (add (.local "mint_ts") (.local "mint_gross")),
      .mapWrite "share_balances" (.local "receiver") (add (.local "mint_bal") (.local "shares"))
      ] ++ mintFeeShares ++ #[
      .emit "Deposit" #[sender, .local "receiver", .local "mint_actual", .local "shares"],
      .emit "Transfer" #[zeroAddress, .local "receiver", .local "shares"],
      releaseLock, .returnExpr (.local "mint_actual") ] },
  { name := "withdraw", kind := .function, mutability := .call, selector? := some "b460af94",
    params := #[uint256Param "assets", { name := "receiver", type := .address },
      { name := "holder", type := .address }], retType := .u64,
    returnAbiWord? := some "uint256",
    body := acquireLock ++ #[
      .assert (ne (.local "receiver") zeroAddress) "zero receiver",
      .assert (positive (.local "assets")) "zero assets",
      .assert (eq sender (.local "holder")) "not holder" ] ++
      convertToSharesUpIntoScratch (.local "assets") ++ #[
      .bind "withdraw_shares" .u64 (.stateRead "convert_scratch"),
      .assert (positive (.local "withdraw_shares")) "zero shares",
      .stateWrite "convert_scratch" (.local "assets") ] ++ applyFee (.local "assets") ++ #[
      .bind "withdraw_user_assets" .u64 (.stateRead "convert_scratch"),
      .assert (positive (.local "withdraw_user_assets")) "zero net assets",
      .bind "withdraw_bal" .u64 (.mapRead "share_balances" (.local "holder")),
      .assert (ge (.local "withdraw_bal") (.local "withdraw_shares")) "insufficient shares",
      .mapWrite "share_balances" (.local "holder")
        (sub (.local "withdraw_bal") (.local "withdraw_shares")),
      .bind "withdraw_ts" .u64 (.stateRead "total_supply"),
      .stateWrite "total_supply" (sub (.local "withdraw_ts") (.local "withdraw_shares")) ] ++
      pushAssetsMeasured "withdraw" (.local "receiver") (.local "withdraw_user_assets") ++ #[
      .bind "withdraw_ta" .u64 (.stateRead "total_assets"),
      .assert (ge (.local "withdraw_ta") (.local "withdraw_actual_left")) "actual left > totalAssets",
      .stateWrite "total_assets" (sub (.local "withdraw_ta") (.local "withdraw_actual_left")),
      .emit "Withdraw" #[sender, .local "receiver", .local "holder",
        .local "withdraw_actual_recv", .local "withdraw_shares"],
      .emit "Transfer" #[.local "holder", zeroAddress, .local "withdraw_shares"],
      releaseLock, .returnExpr (.local "withdraw_shares") ] },
  { name := "redeem", kind := .function, mutability := .call, selector? := some "ba087652",
    params := #[uint256Param "shares", { name := "receiver", type := .address },
      { name := "holder", type := .address }], retType := .u64,
    returnAbiWord? := some "uint256",
    body := acquireLock ++ #[
      .assert (ne (.local "receiver") zeroAddress) "zero receiver",
      .assert (positive (.local "shares")) "zero shares",
      .assert (eq sender (.local "holder")) "not holder" ] ++
      convertToAssetsIntoScratch (.local "shares") ++ #[
      .bind "redeem_gross" .u64 (.stateRead "convert_scratch"),
      .assert (positive (.local "redeem_gross")) "zero assets" ] ++
      applyFee (.local "redeem_gross") ++ #[
      .bind "redeem_user_assets" .u64 (.stateRead "convert_scratch"),
      .assert (positive (.local "redeem_user_assets")) "zero net assets",
      .bind "redeem_bal" .u64 (.mapRead "share_balances" (.local "holder")),
      .assert (ge (.local "redeem_bal") (.local "shares")) "insufficient shares",
      .mapWrite "share_balances" (.local "holder") (sub (.local "redeem_bal") (.local "shares")),
      .bind "redeem_ts" .u64 (.stateRead "total_supply"),
      .stateWrite "total_supply" (sub (.local "redeem_ts") (.local "shares")) ] ++
      pushAssetsMeasured "redeem" (.local "receiver") (.local "redeem_user_assets") ++ #[
      .bind "redeem_ta" .u64 (.stateRead "total_assets"),
      .assert (ge (.local "redeem_ta") (.local "redeem_actual_left")) "actual left > totalAssets",
      .stateWrite "total_assets" (sub (.local "redeem_ta") (.local "redeem_actual_left")),
      .emit "Withdraw" #[sender, .local "receiver", .local "holder",
        .local "redeem_actual_recv", .local "shares"],
      .emit "Transfer" #[.local "holder", zeroAddress, .local "shares"],
      releaseLock, .returnExpr (.local "redeem_actual_recv") ] },
  { name := "transfer", kind := .function, mutability := .call, selector? := some "a9059cbb",
    params := #[{ name := "recipient", type := .address }, uint256Param "amount"],
    retType := .bool, body := #[
      .assert (ne (.local "recipient") zeroAddress) "zero recipient",
      .bind "transfer_sender" .address sender,
      .bind "transfer_src" .u64 (.mapRead "share_balances" (.local "transfer_sender")),
      .assert (ge (.local "transfer_src") (.local "amount")) "insufficient balance",
      .bind "transfer_dst" .u64 (.mapRead "share_balances" (.local "recipient")),
      .mapWrite "share_balances" (.local "transfer_sender")
        (sub (.local "transfer_src") (.local "amount")),
      .mapWrite "share_balances" (.local "recipient")
        (add (.local "transfer_dst") (.local "amount")),
      .emit "Transfer" #[.local "transfer_sender", .local "recipient", .local "amount"],
      .returnExpr (bool true) ] },
  { name := "approve", kind := .function, mutability := .call, selector? := some "095ea7b3",
    params := #[{ name := "spender", type := .address }, uint256Param "amount"],
    retType := .bool, body := #[
      .assert (ne (.local "spender") zeroAddress) "zero spender",
      .bind "approve_holder" .address sender,
      .bind "approve_key" .hash (allowanceKey (.local "approve_holder") (.local "spender")),
      .mapWrite "share_allowances" (.local "approve_key") (.local "amount"),
      .emit "Approval" #[.local "approve_holder", .local "spender", .local "amount"],
      .returnExpr (bool true) ] }
]

def contract : SurfaceContract := {
  name := "ERC4626"
  structs := #[]
  state := #[
    { name := "initialized", kind := .scalar .bool },
    { name := "asset", kind := .scalar .address },
    { name := "vault_self", kind := .scalar .address },
    { name := "total_assets", kind := .scalar .u64 },
    { name := "total_supply", kind := .scalar .u64 },
    { name := "convert_scratch", kind := .scalar .u64 },
    { name := "fee_scratch", kind := .scalar .u64 },
    { name := "fee_bps", kind := .scalar .u64 },
    { name := "fee_recipient", kind := .scalar .address },
    { name := "locked", kind := .scalar .bool },
    { name := "share_balances", kind := .map .address .u64 none },
    { name := "share_allowances", kind := .map .hash .u64 none }
  ]
  events := #[
    { name := "Deposit", fields := #[
      { name := "sender", type := .address, indexed := true },
      { name := "owner", type := .address, indexed := true },
      { name := "assets", type := .u64, indexed := false, abiWord? := some "uint256" },
      { name := "shares", type := .u64, indexed := false, abiWord? := some "uint256" }] },
    { name := "Withdraw", fields := #[
      { name := "sender", type := .address, indexed := true },
      { name := "receiver", type := .address, indexed := true },
      { name := "owner", type := .address, indexed := true },
      { name := "assets", type := .u64, indexed := false, abiWord? := some "uint256" },
      { name := "shares", type := .u64, indexed := false, abiWord? := some "uint256" }] },
    { name := "Transfer", fields := #[
      { name := "from", type := .address, indexed := true },
      { name := "to", type := .address, indexed := true },
      { name := "value", type := .u64, indexed := false, abiWord? := some "uint256" }] },
    { name := "Approval", fields := #[
      { name := "owner", type := .address, indexed := true },
      { name := "spender", type := .address, indexed := true },
      { name := "value", type := .u64, indexed := false, abiWord? := some "uint256" }] }
  ]
  errors := #[]
  entrypoints := entrypoints
  constructorParams := #[]
  constructorBindings := #[]
}

end ProofForge.Frontend.Materialize.Evm.ERC4626
