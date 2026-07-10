object "ERC4626" {
  code {
    switch shr(224, calldataload(0))
    case 0x38d52e0f {
      let _r := f_ERC4626_asset()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x01e1d114 {
      let _r := f_ERC4626_totalAssets()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x18160ddd {
      let _r := f_ERC4626_totalSupply()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x70a08231 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      let _r := f_ERC4626_balanceOf(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xc6e6f592 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_ERC4626_convertToShares(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x07a2d13a {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_ERC4626_convertToAssets(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x402d267d {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      let _r := f_ERC4626_maxDeposit(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xc63d75b6 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      let _r := f_ERC4626_maxMint(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xce96cb77 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      let _r := f_ERC4626_maxWithdraw(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xd905777e {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      let _r := f_ERC4626_maxRedeem(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x24a9d853 {
      let _r := f_ERC4626_feeBps()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x46904840 {
      let _r := f_ERC4626_feeRecipient()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xef8b30f7 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_ERC4626_previewDeposit(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xb3d7f6b9 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_ERC4626_previewMint(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x0a28a477 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_ERC4626_previewWithdraw(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x4cdad506 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_ERC4626_previewRedeem(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x6e553f65 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(36), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      let _r := f_ERC4626_deposit(calldataload(4), calldataload(36))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x94bf804d {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(36), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      let _r := f_ERC4626_mint(calldataload(4), calldataload(36))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xb460af94 {
      if lt(calldatasize(), 100) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(36), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(68), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      let _r := f_ERC4626_withdraw(calldataload(4), calldataload(36), calldataload(68))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xba087652 {
      if lt(calldatasize(), 100) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(36), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(68), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      let _r := f_ERC4626_redeem(calldataload(4), calldataload(36), calldataload(68))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xa9059cbb {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_ERC4626_transfer(calldataload(4), calldataload(36))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x095ea7b3 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_ERC4626_approve(calldataload(4), calldataload(36))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x4b180da9 {
      if lt(calldatasize(), 132) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(68), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(100), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      f_ERC4626_init(calldataload(4), calldataload(36), calldataload(68), calldataload(100))
      return(0, 0)
    }
    default {
      revert(0, 0)
    }
    function f_ERC4626_asset() -> __pf_result {
      __pf_result := and(shr(0, sload(0)), 1461501637330902918203684832716283019655932542975)
    }
    function f_ERC4626_totalAssets() -> __pf_result {
      __pf_result := and(shr(160, sload(1)), 18446744073709551615)
    }
    function f_ERC4626_totalSupply() -> __pf_result {
      __pf_result := and(shr(0, sload(2)), 18446744073709551615)
    }
    function f_ERC4626_balanceOf(who) -> __pf_result {
      __pf_result := sload(__proof_forge_map_slot(6, who))
    }
    function f_ERC4626_convertToShares(assets) -> __pf_result {
      let _pf_convert_shares := assets
      switch gt(and(shr(0, sload(2)), 18446744073709551615), 0)
      case 0 { }
      default {
        if iszero(iszero(eq(and(shr(160, sload(1)), 18446744073709551615), 0))) {
          revert(0, 0)
        }
        _pf_convert_shares := div(__pf_checked_mul(assets, and(shr(0, sload(2)), 18446744073709551615)), and(shr(160, sload(1)), 18446744073709551615))
      }
      if iszero(iszero(lt(18446744073709551615, _pf_convert_shares))) {
        revert(0, 0)
      }
      __pf_result := _pf_convert_shares
    }
    function f_ERC4626_convertToAssets(shares) -> __pf_result {
      let _pf_convert_assets := shares
      switch gt(and(shr(0, sload(2)), 18446744073709551615), 0)
      case 0 { }
      default {
        if iszero(iszero(eq(and(shr(160, sload(1)), 18446744073709551615), 0))) {
          revert(0, 0)
        }
        _pf_convert_assets := div(__pf_checked_mul(shares, and(shr(160, sload(1)), 18446744073709551615)), and(shr(0, sload(2)), 18446744073709551615))
      }
      if iszero(iszero(lt(18446744073709551615, _pf_convert_assets))) {
        revert(0, 0)
      }
      __pf_result := _pf_convert_assets
    }
    function f_ERC4626_maxDeposit(who) -> __pf_result {
      let _pf_max_deposit := 0
      switch iszero(eq(who, 0))
      case 0 { }
      default {
        switch and(lt(and(shr(192, sload(3)), 18446744073709551615), 10000), or(eq(and(shr(192, sload(3)), 18446744073709551615), 0), iszero(eq(and(shr(0, sload(4)), 1461501637330902918203684832716283019655932542975), 0))))
        case 0 { }
        default {
          let _pf_max_deposit_asset_cap := __pf_checked_sub(18446744073709551615, and(shr(160, sload(1)), 18446744073709551615))
          switch gt(and(shr(0, sload(2)), 18446744073709551615), 0)
          case 0 { }
          default {
            switch lt(div(18446744073709551615, and(shr(0, sload(2)), 18446744073709551615)), _pf_max_deposit_asset_cap)
            case 0 { }
            default {
              _pf_max_deposit_asset_cap := div(18446744073709551615, and(shr(0, sload(2)), 18446744073709551615))
            }
          }
          let _pf_max_deposit_gross_cap := __pf_checked_sub(18446744073709551615, and(shr(0, sload(2)), 18446744073709551615))
          switch lt(__pf_checked_sub(18446744073709551615, sload(__proof_forge_map_slot(6, who))), _pf_max_deposit_gross_cap)
          case 0 { }
          default {
            _pf_max_deposit_gross_cap := __pf_checked_sub(18446744073709551615, sload(__proof_forge_map_slot(6, who)))
          }
          switch gt(and(shr(192, sload(3)), 18446744073709551615), 0)
          case 0 { }
          default {
            switch lt(__pf_checked_sub(18446744073709551615, sload(__proof_forge_map_slot(6, and(shr(0, sload(4)), 1461501637330902918203684832716283019655932542975)))), _pf_max_deposit_gross_cap)
            case 0 { }
            default {
              _pf_max_deposit_gross_cap := __pf_checked_sub(18446744073709551615, sload(__proof_forge_map_slot(6, and(shr(0, sload(4)), 1461501637330902918203684832716283019655932542975))))
            }
            switch gt(and(shr(192, sload(3)), 18446744073709551615), 0)
            case 0 { }
            default {
              switch lt(div(18446744073709551615, and(shr(192, sload(3)), 18446744073709551615)), _pf_max_deposit_gross_cap)
              case 0 { }
              default {
                _pf_max_deposit_gross_cap := div(18446744073709551615, and(shr(192, sload(3)), 18446744073709551615))
              }
            }
          }
          _pf_max_deposit := _pf_max_deposit_asset_cap
          switch eq(and(shr(0, sload(2)), 18446744073709551615), 0)
          case 0 { }
          default {
            switch lt(_pf_max_deposit_gross_cap, _pf_max_deposit)
            case 0 { }
            default {
              _pf_max_deposit := _pf_max_deposit_gross_cap
            }
          }
          switch gt(and(shr(0, sload(2)), 18446744073709551615), 0)
          case 0 { }
          default {
            switch eq(and(shr(160, sload(1)), 18446744073709551615), 0)
            case 0 { }
            default {
              _pf_max_deposit := 0
            }
            switch gt(and(shr(160, sload(1)), 18446744073709551615), 0)
            case 0 { }
            default {
              let _pf_max_deposit_gross_at_asset_cap := div(__pf_checked_mul(_pf_max_deposit_asset_cap, and(shr(0, sload(2)), 18446744073709551615)), and(shr(160, sload(1)), 18446744073709551615))
              switch gt(_pf_max_deposit_gross_at_asset_cap, _pf_max_deposit_gross_cap)
              case 0 { }
              default {
                let _pf_max_deposit_reverse_gross_cap := _pf_max_deposit_gross_cap
                switch gt(and(shr(160, sload(1)), 18446744073709551615), 0)
                case 0 { }
                default {
                  switch lt(div(18446744073709551615, and(shr(160, sload(1)), 18446744073709551615)), _pf_max_deposit_reverse_gross_cap)
                  case 0 { }
                  default {
                    _pf_max_deposit_reverse_gross_cap := div(18446744073709551615, and(shr(160, sload(1)), 18446744073709551615))
                  }
                }
                _pf_max_deposit := div(__pf_checked_mul(_pf_max_deposit_reverse_gross_cap, and(shr(160, sload(1)), 18446744073709551615)), and(shr(0, sload(2)), 18446744073709551615))
              }
              let _pf_max_deposit_gross_final := div(__pf_checked_mul(_pf_max_deposit, and(shr(0, sload(2)), 18446744073709551615)), and(shr(160, sload(1)), 18446744073709551615))
              switch eq(_pf_max_deposit_gross_final, 0)
              case 0 { }
              default {
                _pf_max_deposit := 0
              }
            }
          }
        }
      }
      __pf_result := _pf_max_deposit
    }
    function f_ERC4626_maxMint(who) -> __pf_result {
      let _pf_max_mint := 0
      switch iszero(eq(who, 0))
      case 0 { }
      default {
        switch and(lt(and(shr(192, sload(3)), 18446744073709551615), 10000), or(eq(and(shr(192, sload(3)), 18446744073709551615), 0), iszero(eq(and(shr(0, sload(4)), 1461501637330902918203684832716283019655932542975), 0))))
        case 0 { }
        default {
          let _pf_max_mint_gross_cap := __pf_checked_sub(18446744073709551615, and(shr(0, sload(2)), 18446744073709551615))
          switch gt(and(shr(192, sload(3)), 18446744073709551615), 0)
          case 0 { }
          default {
            switch lt(__pf_checked_sub(18446744073709551615, sload(__proof_forge_map_slot(6, and(shr(0, sload(4)), 1461501637330902918203684832716283019655932542975)))), _pf_max_mint_gross_cap)
            case 0 { }
            default {
              _pf_max_mint_gross_cap := __pf_checked_sub(18446744073709551615, sload(__proof_forge_map_slot(6, and(shr(0, sload(4)), 1461501637330902918203684832716283019655932542975))))
            }
          }
          let _pf_max_mint_asset_cap := __pf_checked_sub(18446744073709551615, and(shr(160, sload(1)), 18446744073709551615))
          switch eq(and(shr(0, sload(2)), 18446744073709551615), 0)
          case 0 { }
          default {
            switch lt(_pf_max_mint_asset_cap, _pf_max_mint_gross_cap)
            case 0 { }
            default {
              _pf_max_mint_gross_cap := _pf_max_mint_asset_cap
            }
          }
          switch gt(and(shr(0, sload(2)), 18446744073709551615), 0)
          case 0 { }
          default {
            switch eq(and(shr(160, sload(1)), 18446744073709551615), 0)
            case 0 { }
            default {
              _pf_max_mint_gross_cap := 0
            }
            switch gt(and(shr(160, sload(1)), 18446744073709551615), 0)
            case 0 { }
            default {
              switch gt(and(shr(0, sload(2)), 18446744073709551615), 0)
              case 0 { }
              default {
                switch lt(div(18446744073709551615, and(shr(0, sload(2)), 18446744073709551615)), _pf_max_mint_asset_cap)
                case 0 { }
                default {
                  _pf_max_mint_asset_cap := div(18446744073709551615, and(shr(0, sload(2)), 18446744073709551615))
                }
              }
              let _pf_max_mint_gross_from_asset_cap := div(__pf_checked_mul(_pf_max_mint_asset_cap, and(shr(0, sload(2)), 18446744073709551615)), and(shr(160, sload(1)), 18446744073709551615))
              switch lt(_pf_max_mint_gross_from_asset_cap, _pf_max_mint_gross_cap)
              case 0 { }
              default {
                _pf_max_mint_gross_cap := _pf_max_mint_gross_from_asset_cap
              }
            }
          }
          switch eq(and(shr(192, sload(3)), 18446744073709551615), 0)
          case 0 { }
          default {
            _pf_max_mint := _pf_max_mint_gross_cap
          }
          switch gt(and(shr(192, sload(3)), 18446744073709551615), 0)
          case 0 { }
          default {
            switch gt(and(shr(192, sload(3)), 18446744073709551615), 0)
            case 0 { }
            default {
              switch lt(div(18446744073709551615, and(shr(192, sload(3)), 18446744073709551615)), _pf_max_mint_gross_cap)
              case 0 { }
              default {
                _pf_max_mint_gross_cap := div(18446744073709551615, and(shr(192, sload(3)), 18446744073709551615))
              }
            }
            let _pf_max_mint_net_cap := _pf_max_mint_gross_cap
            switch gt(and(shr(192, sload(3)), 18446744073709551615), 0)
            case 0 { }
            default {
              _pf_max_mint_net_cap := __pf_checked_sub(_pf_max_mint_gross_cap, div(__pf_checked_mul(_pf_max_mint_gross_cap, and(shr(192, sload(3)), 18446744073709551615)), 10000))
            }
            if iszero(iszero(lt(18446744073709551615, _pf_max_mint_net_cap))) {
              revert(0, 0)
            }
            _pf_max_mint := _pf_max_mint_net_cap
            switch gt(10000, 0)
            case 0 { }
            default {
              switch lt(div(18446744073709551615, 10000), _pf_max_mint)
              case 0 { }
              default {
                _pf_max_mint := div(18446744073709551615, 10000)
              }
            }
            let _pf_max_mint_gross_needed := _pf_max_mint
            switch gt(and(shr(192, sload(3)), 18446744073709551615), 0)
            case 0 { }
            default {
              if iszero(iszero(eq(and(shr(192, sload(3)), 18446744073709551615), 10000))) {
                revert(0, 0)
              }
              _pf_max_mint_gross_needed := div(__pf_checked_mul(_pf_max_mint, 10000), __pf_checked_sub(10000, and(shr(192, sload(3)), 18446744073709551615)))
            }
            if iszero(iszero(lt(18446744073709551615, _pf_max_mint_gross_needed))) {
              revert(0, 0)
            }
            switch gt(_pf_max_mint_gross_needed, _pf_max_mint_gross_cap)
            case 0 { }
            default {
              _pf_max_mint := 0
            }
          }
          switch lt(__pf_checked_sub(18446744073709551615, sload(__proof_forge_map_slot(6, who))), _pf_max_mint)
          case 0 { }
          default {
            _pf_max_mint := __pf_checked_sub(18446744073709551615, sload(__proof_forge_map_slot(6, who)))
          }
        }
      }
      __pf_result := _pf_max_mint
    }
    function f_ERC4626_maxWithdraw(holder) -> __pf_result {
      let _pf_max_withdraw := 0
      switch and(lt(and(shr(192, sload(3)), 18446744073709551615), 10000), or(eq(and(shr(192, sload(3)), 18446744073709551615), 0), iszero(eq(and(shr(0, sload(4)), 1461501637330902918203684832716283019655932542975), 0))))
      case 0 { }
      default {
        let _pf_max_withdraw_shares := sload(__proof_forge_map_slot(6, holder))
        switch lt(and(shr(0, sload(2)), 18446744073709551615), _pf_max_withdraw_shares)
        case 0 { }
        default {
          _pf_max_withdraw_shares := and(shr(0, sload(2)), 18446744073709551615)
        }
        switch gt(and(shr(0, sload(2)), 18446744073709551615), 0)
        case 0 { }
        default {
          switch gt(and(shr(160, sload(1)), 18446744073709551615), 0)
          case 0 { }
          default {
            switch gt(and(shr(160, sload(1)), 18446744073709551615), 0)
            case 0 { }
            default {
              switch lt(div(18446744073709551615, and(shr(160, sload(1)), 18446744073709551615)), _pf_max_withdraw_shares)
              case 0 { }
              default {
                _pf_max_withdraw_shares := div(18446744073709551615, and(shr(160, sload(1)), 18446744073709551615))
              }
            }
            let _pf_max_withdraw_gross_assets := div(__pf_checked_mul(_pf_max_withdraw_shares, and(shr(160, sload(1)), 18446744073709551615)), and(shr(0, sload(2)), 18446744073709551615))
            switch gt(and(shr(0, sload(2)), 18446744073709551615), 0)
            case 0 { }
            default {
              switch lt(div(18446744073709551615, and(shr(0, sload(2)), 18446744073709551615)), _pf_max_withdraw_gross_assets)
              case 0 { }
              default {
                _pf_max_withdraw_gross_assets := div(18446744073709551615, and(shr(0, sload(2)), 18446744073709551615))
              }
            }
            switch gt(and(shr(192, sload(3)), 18446744073709551615), 0)
            case 0 { }
            default {
              switch gt(and(shr(192, sload(3)), 18446744073709551615), 0)
              case 0 { }
              default {
                switch lt(div(18446744073709551615, and(shr(192, sload(3)), 18446744073709551615)), _pf_max_withdraw_gross_assets)
                case 0 { }
                default {
                  _pf_max_withdraw_gross_assets := div(18446744073709551615, and(shr(192, sload(3)), 18446744073709551615))
                }
              }
            }
            let _pf_max_withdraw_net_assets := _pf_max_withdraw_gross_assets
            switch gt(and(shr(192, sload(3)), 18446744073709551615), 0)
            case 0 { }
            default {
              _pf_max_withdraw_net_assets := __pf_checked_sub(_pf_max_withdraw_gross_assets, div(__pf_checked_mul(_pf_max_withdraw_gross_assets, and(shr(192, sload(3)), 18446744073709551615)), 10000))
            }
            if iszero(iszero(lt(18446744073709551615, _pf_max_withdraw_net_assets))) {
              revert(0, 0)
            }
            switch gt(_pf_max_withdraw_net_assets, 0)
            case 0 { }
            default {
              _pf_max_withdraw := _pf_max_withdraw_gross_assets
            }
          }
        }
      }
      __pf_result := _pf_max_withdraw
    }
    function f_ERC4626_maxRedeem(holder) -> __pf_result {
      let _pf_max_redeem := 0
      switch and(lt(and(shr(192, sload(3)), 18446744073709551615), 10000), or(eq(and(shr(192, sload(3)), 18446744073709551615), 0), iszero(eq(and(shr(0, sload(4)), 1461501637330902918203684832716283019655932542975), 0))))
      case 0 { }
      default {
        let _pf_max_redeem_shares := sload(__proof_forge_map_slot(6, holder))
        switch lt(and(shr(0, sload(2)), 18446744073709551615), _pf_max_redeem_shares)
        case 0 { }
        default {
          _pf_max_redeem_shares := and(shr(0, sload(2)), 18446744073709551615)
        }
        switch gt(and(shr(0, sload(2)), 18446744073709551615), 0)
        case 0 { }
        default {
          switch gt(and(shr(160, sload(1)), 18446744073709551615), 0)
          case 0 { }
          default {
            switch gt(and(shr(160, sload(1)), 18446744073709551615), 0)
            case 0 { }
            default {
              switch lt(div(18446744073709551615, and(shr(160, sload(1)), 18446744073709551615)), _pf_max_redeem_shares)
              case 0 { }
              default {
                _pf_max_redeem_shares := div(18446744073709551615, and(shr(160, sload(1)), 18446744073709551615))
              }
            }
            let _pf_max_redeem_gross_assets := div(__pf_checked_mul(_pf_max_redeem_shares, and(shr(160, sload(1)), 18446744073709551615)), and(shr(0, sload(2)), 18446744073709551615))
            switch gt(and(shr(192, sload(3)), 18446744073709551615), 0)
            case 0 { }
            default {
              let _pf_max_redeem_gross_fee_cap := div(18446744073709551615, and(shr(192, sload(3)), 18446744073709551615))
              switch gt(_pf_max_redeem_gross_assets, _pf_max_redeem_gross_fee_cap)
              case 0 { }
              default {
                switch gt(and(shr(0, sload(2)), 18446744073709551615), 0)
                case 0 { }
                default {
                  switch lt(div(18446744073709551615, and(shr(0, sload(2)), 18446744073709551615)), _pf_max_redeem_gross_fee_cap)
                  case 0 { }
                  default {
                    _pf_max_redeem_gross_fee_cap := div(18446744073709551615, and(shr(0, sload(2)), 18446744073709551615))
                  }
                }
                _pf_max_redeem_shares := div(__pf_checked_mul(_pf_max_redeem_gross_fee_cap, and(shr(0, sload(2)), 18446744073709551615)), and(shr(160, sload(1)), 18446744073709551615))
                _pf_max_redeem_gross_assets := div(__pf_checked_mul(_pf_max_redeem_shares, and(shr(160, sload(1)), 18446744073709551615)), and(shr(0, sload(2)), 18446744073709551615))
              }
            }
            let _pf_max_redeem_net_assets := _pf_max_redeem_gross_assets
            switch gt(and(shr(192, sload(3)), 18446744073709551615), 0)
            case 0 { }
            default {
              _pf_max_redeem_net_assets := __pf_checked_sub(_pf_max_redeem_gross_assets, div(__pf_checked_mul(_pf_max_redeem_gross_assets, and(shr(192, sload(3)), 18446744073709551615)), 10000))
            }
            if iszero(iszero(lt(18446744073709551615, _pf_max_redeem_net_assets))) {
              revert(0, 0)
            }
            switch gt(_pf_max_redeem_net_assets, 0)
            case 0 { }
            default {
              _pf_max_redeem := _pf_max_redeem_shares
            }
          }
        }
      }
      __pf_result := _pf_max_redeem
    }
    function f_ERC4626_feeBps() -> __pf_result {
      __pf_result := and(shr(192, sload(3)), 18446744073709551615)
    }
    function f_ERC4626_feeRecipient() -> __pf_result {
      __pf_result := and(shr(0, sload(4)), 1461501637330902918203684832716283019655932542975)
    }
    function f_ERC4626_previewDeposit(assets) -> __pf_result {
      let _pf_preview_deposit := assets
      switch gt(and(shr(0, sload(2)), 18446744073709551615), 0)
      case 0 { }
      default {
        if iszero(iszero(eq(and(shr(160, sload(1)), 18446744073709551615), 0))) {
          revert(0, 0)
        }
        _pf_preview_deposit := div(__pf_checked_mul(assets, and(shr(0, sload(2)), 18446744073709551615)), and(shr(160, sload(1)), 18446744073709551615))
      }
      if iszero(iszero(lt(18446744073709551615, _pf_preview_deposit))) {
        revert(0, 0)
      }
      let _pf_preview_deposit_net := _pf_preview_deposit
      switch gt(and(shr(192, sload(3)), 18446744073709551615), 0)
      case 0 { }
      default {
        _pf_preview_deposit_net := __pf_checked_sub(_pf_preview_deposit, div(__pf_checked_mul(_pf_preview_deposit, and(shr(192, sload(3)), 18446744073709551615)), 10000))
      }
      if iszero(iszero(lt(18446744073709551615, _pf_preview_deposit_net))) {
        revert(0, 0)
      }
      __pf_result := _pf_preview_deposit_net
    }
    function f_ERC4626_previewMint(shares) -> __pf_result {
      let _pf_preview_mint_gross := shares
      switch gt(and(shr(192, sload(3)), 18446744073709551615), 0)
      case 0 { }
      default {
        if iszero(iszero(eq(and(shr(192, sload(3)), 18446744073709551615), 10000))) {
          revert(0, 0)
        }
        _pf_preview_mint_gross := div(__pf_checked_mul(shares, 10000), __pf_checked_sub(10000, and(shr(192, sload(3)), 18446744073709551615)))
      }
      if iszero(iszero(lt(18446744073709551615, _pf_preview_mint_gross))) {
        revert(0, 0)
      }
      let _pf_preview_mint_assets := _pf_preview_mint_gross
      switch gt(and(shr(0, sload(2)), 18446744073709551615), 0)
      case 0 { }
      default {
        if iszero(iszero(eq(and(shr(160, sload(1)), 18446744073709551615), 0))) {
          revert(0, 0)
        }
        let _pf_preview_mint_assets_numerator := __pf_checked_mul(_pf_preview_mint_gross, and(shr(160, sload(1)), 18446744073709551615))
        let _pf_preview_mint_assets_quotient := div(_pf_preview_mint_assets_numerator, and(shr(0, sload(2)), 18446744073709551615))
        if iszero(iszero(lt(18446744073709551615, _pf_preview_mint_assets_quotient))) {
          revert(0, 0)
        }
        _pf_preview_mint_assets := _pf_preview_mint_assets_quotient
        switch gt(mod(_pf_preview_mint_assets_numerator, and(shr(0, sload(2)), 18446744073709551615)), 0)
        case 0 { }
        default {
          if iszero(iszero(eq(_pf_preview_mint_assets_quotient, 18446744073709551615))) {
            revert(0, 0)
          }
          _pf_preview_mint_assets := __pf_checked_add(_pf_preview_mint_assets_quotient, 1)
        }
      }
      __pf_result := _pf_preview_mint_assets
    }
    function f_ERC4626_previewWithdraw(assets) -> __pf_result {
      let _pf_preview_withdraw := assets
      switch gt(and(shr(0, sload(2)), 18446744073709551615), 0)
      case 0 { }
      default {
        if iszero(iszero(eq(and(shr(160, sload(1)), 18446744073709551615), 0))) {
          revert(0, 0)
        }
        let _pf_preview_withdraw_numerator := __pf_checked_mul(assets, and(shr(0, sload(2)), 18446744073709551615))
        let _pf_preview_withdraw_quotient := div(_pf_preview_withdraw_numerator, and(shr(160, sload(1)), 18446744073709551615))
        if iszero(iszero(lt(18446744073709551615, _pf_preview_withdraw_quotient))) {
          revert(0, 0)
        }
        _pf_preview_withdraw := _pf_preview_withdraw_quotient
        switch gt(mod(_pf_preview_withdraw_numerator, and(shr(160, sload(1)), 18446744073709551615)), 0)
        case 0 { }
        default {
          if iszero(iszero(eq(_pf_preview_withdraw_quotient, 18446744073709551615))) {
            revert(0, 0)
          }
          _pf_preview_withdraw := __pf_checked_add(_pf_preview_withdraw_quotient, 1)
        }
      }
      __pf_result := _pf_preview_withdraw
    }
    function f_ERC4626_previewRedeem(shares) -> __pf_result {
      let _pf_preview_redeem := shares
      switch gt(and(shr(0, sload(2)), 18446744073709551615), 0)
      case 0 { }
      default {
        if iszero(iszero(eq(and(shr(160, sload(1)), 18446744073709551615), 0))) {
          revert(0, 0)
        }
        _pf_preview_redeem := div(__pf_checked_mul(shares, and(shr(160, sload(1)), 18446744073709551615)), and(shr(0, sload(2)), 18446744073709551615))
      }
      if iszero(iszero(lt(18446744073709551615, _pf_preview_redeem))) {
        revert(0, 0)
      }
      let _pf_preview_redeem_net := _pf_preview_redeem
      switch gt(and(shr(192, sload(3)), 18446744073709551615), 0)
      case 0 { }
      default {
        _pf_preview_redeem_net := __pf_checked_sub(_pf_preview_redeem, div(__pf_checked_mul(_pf_preview_redeem, and(shr(192, sload(3)), 18446744073709551615)), 10000))
      }
      if iszero(iszero(lt(18446744073709551615, _pf_preview_redeem_net))) {
        revert(0, 0)
      }
      __pf_result := _pf_preview_redeem_net
    }
    function f_ERC4626_deposit(assets, receiver) -> __pf_result {
      if iszero(eq(and(shr(160, sload(4)), 18446744073709551615), 0)) {
        revert(0, 0)
      }
      sstore(4, or(and(sload(4), not(shl(160, 18446744073709551615))), shl(160, and(1, 18446744073709551615))))
      if iszero(iszero(eq(receiver, 0))) {
        revert(0, 0)
      }
      if iszero(iszero(eq(assets, 0))) {
        revert(0, 0)
      }
      sstore(2, or(and(sload(2), not(shl(192, 18446744073709551615))), shl(192, and(__proof_forge_crosscall_1(and(shr(0, sload(0)), 1461501637330902918203684832716283019655932542975), 1889567281, and(shr(0, sload(1)), 1461501637330902918203684832716283019655932542975)), 18446744073709551615))))
      let _pf_pull := __proof_forge_crosscall_3(and(shr(0, sload(0)), 1461501637330902918203684832716283019655932542975), 599290589, caller(), and(shr(0, sload(1)), 1461501637330902918203684832716283019655932542975), assets)
      if iszero(eq(_pf_pull, 1)) {
        revert(0, 0)
      }
      let _pf_bal_after := __proof_forge_crosscall_1(and(shr(0, sload(0)), 1461501637330902918203684832716283019655932542975), 1889567281, and(shr(0, sload(1)), 1461501637330902918203684832716283019655932542975))
      {
        let __pf_packed_value := __pf_checked_width(__pf_checked_sub(__pf_checked_width(_pf_bal_after, 18446744073709551615), __pf_checked_width(and(shr(192, sload(2)), 18446744073709551615), 18446744073709551615)), 18446744073709551615)
        if gt(__pf_packed_value, 18446744073709551615) {
          revert(0, 0)
        }
        sstore(3, or(and(sload(3), not(shl(0, 18446744073709551615))), shl(0, and(__pf_packed_value, 18446744073709551615))))
      }
      if iszero(iszero(eq(and(shr(0, sload(3)), 18446744073709551615), 0))) {
        revert(0, 0)
      }
      let actual := and(shr(0, sload(3)), 18446744073709551615)
      sstore(2, or(and(sload(2), not(shl(64, 18446744073709551615))), shl(64, and(actual, 18446744073709551615))))
      switch gt(and(shr(0, sload(2)), 18446744073709551615), 0)
      case 0 { }
      default {
        if iszero(iszero(eq(and(shr(160, sload(1)), 18446744073709551615), 0))) {
          revert(0, 0)
        }
        {
          let __pf_packed_value := div(__pf_checked_width(__pf_checked_mul(__pf_checked_width(actual, 18446744073709551615), __pf_checked_width(and(shr(0, sload(2)), 18446744073709551615), 18446744073709551615)), 18446744073709551615), and(shr(160, sload(1)), 18446744073709551615))
          if gt(__pf_packed_value, 18446744073709551615) {
            revert(0, 0)
          }
          sstore(2, or(and(sload(2), not(shl(64, 18446744073709551615))), shl(64, and(__pf_packed_value, 18446744073709551615))))
        }
      }
      let gross := and(shr(64, sload(2)), 18446744073709551615)
      if iszero(iszero(eq(gross, 0))) {
        revert(0, 0)
      }
      sstore(2, or(and(sload(2), not(shl(128, 18446744073709551615))), shl(128, and(0, 18446744073709551615))))
      switch gt(and(shr(192, sload(3)), 18446744073709551615), 0)
      case 0 { }
      default {
        {
          let __pf_packed_value := div(__pf_checked_width(__pf_checked_mul(__pf_checked_width(and(shr(64, sload(2)), 18446744073709551615), 18446744073709551615), __pf_checked_width(and(shr(192, sload(3)), 18446744073709551615), 18446744073709551615)), 18446744073709551615), 10000)
          if gt(__pf_packed_value, 18446744073709551615) {
            revert(0, 0)
          }
          sstore(2, or(and(sload(2), not(shl(128, 18446744073709551615))), shl(128, and(__pf_packed_value, 18446744073709551615))))
        }
        {
          let __pf_packed_value := __pf_checked_width(__pf_checked_sub(__pf_checked_width(and(shr(64, sload(2)), 18446744073709551615), 18446744073709551615), __pf_checked_width(and(shr(128, sload(2)), 18446744073709551615), 18446744073709551615)), 18446744073709551615)
          if gt(__pf_packed_value, 18446744073709551615) {
            revert(0, 0)
          }
          sstore(2, or(and(sload(2), not(shl(64, 18446744073709551615))), shl(64, and(__pf_packed_value, 18446744073709551615))))
        }
      }
      let shares := and(shr(64, sload(2)), 18446744073709551615)
      if iszero(iszero(eq(shares, 0))) {
        revert(0, 0)
      }
      let ta := and(shr(160, sload(1)), 18446744073709551615)
      {
        let __pf_packed_value := __pf_checked_width(__pf_checked_add(__pf_checked_width(ta, 18446744073709551615), __pf_checked_width(actual, 18446744073709551615)), 18446744073709551615)
        if gt(__pf_packed_value, 18446744073709551615) {
          revert(0, 0)
        }
        sstore(1, or(and(sload(1), not(shl(160, 18446744073709551615))), shl(160, and(__pf_packed_value, 18446744073709551615))))
      }
      let ts := and(shr(0, sload(2)), 18446744073709551615)
      {
        let __pf_packed_value := __pf_checked_width(__pf_checked_add(__pf_checked_width(ts, 18446744073709551615), __pf_checked_width(gross, 18446744073709551615)), 18446744073709551615)
        if gt(__pf_packed_value, 18446744073709551615) {
          revert(0, 0)
        }
        sstore(2, or(and(sload(2), not(shl(0, 18446744073709551615))), shl(0, and(__pf_packed_value, 18446744073709551615))))
      }
      let bal := sload(__proof_forge_map_slot(6, receiver))
      __proof_forge_map_write(6, receiver, __pf_checked_add(bal, shares))
      switch gt(and(shr(128, sload(2)), 18446744073709551615), 0)
      case 0 { }
      default {
        if iszero(iszero(eq(and(shr(0, sload(4)), 1461501637330902918203684832716283019655932542975), 0))) {
          revert(0, 0)
        }
        __proof_forge_map_write(6, and(shr(0, sload(4)), 1461501637330902918203684832716283019655932542975), __pf_checked_add(sload(__proof_forge_map_slot(6, and(shr(0, sload(4)), 1461501637330902918203684832716283019655932542975))), and(shr(128, sload(2)), 18446744073709551615)))
        {
          mstore(0, 38196372293521921433607444633801509737016894376733792893611070291108288410934)
          mstore(32, 18544826791913921923306290567797672742125270981606496584444378688767337168896)
          let __pf_event_topic0 := keccak256(0, 33)
          let __pf_event_indexed_topic0 := 0
          let __pf_event_indexed_topic1 := and(shr(0, sload(4)), 1461501637330902918203684832716283019655932542975)
          mstore(0, and(shr(128, sload(2)), 18446744073709551615))
          log3(0, 32, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1)
        }
      }
      {
        mstore(0, 30936501257503946518338176186595900852291947956669005746078969649791291962924)
        mstore(32, 53106884550783362696603933435631747706376370536716806060893931267679118688256)
        let __pf_event_topic0 := keccak256(0, 40)
        let __pf_event_indexed_topic0 := caller()
        let __pf_event_indexed_topic1 := receiver
        mstore(0, actual)
        mstore(32, shares)
        log3(0, 64, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1)
      }
      {
        mstore(0, 38196372293521921433607444633801509737016894376733792893611070291108288410934)
        mstore(32, 18544826791913921923306290567797672742125270981606496584444378688767337168896)
        let __pf_event_topic0 := keccak256(0, 33)
        let __pf_event_indexed_topic0 := 0
        let __pf_event_indexed_topic1 := receiver
        mstore(0, shares)
        log3(0, 32, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1)
      }
      sstore(4, or(and(sload(4), not(shl(160, 18446744073709551615))), shl(160, and(0, 18446744073709551615))))
      __pf_result := shares
    }
    function f_ERC4626_mint(shares, receiver) -> __pf_result {
      if iszero(eq(and(shr(160, sload(4)), 18446744073709551615), 0)) {
        revert(0, 0)
      }
      sstore(4, or(and(sload(4), not(shl(160, 18446744073709551615))), shl(160, and(1, 18446744073709551615))))
      if iszero(iszero(eq(receiver, 0))) {
        revert(0, 0)
      }
      if iszero(iszero(eq(shares, 0))) {
        revert(0, 0)
      }
      sstore(2, or(and(sload(2), not(shl(64, 18446744073709551615))), shl(64, and(shares, 18446744073709551615))))
      switch gt(and(shr(192, sload(3)), 18446744073709551615), 0)
      case 0 { }
      default {
        if iszero(iszero(eq(and(shr(192, sload(3)), 18446744073709551615), 10000))) {
          revert(0, 0)
        }
        {
          let __pf_packed_value := div(__pf_checked_width(__pf_checked_mul(__pf_checked_width(and(shr(64, sload(2)), 18446744073709551615), 18446744073709551615), __pf_checked_width(10000, 18446744073709551615)), 18446744073709551615), __pf_checked_width(__pf_checked_sub(__pf_checked_width(10000, 18446744073709551615), __pf_checked_width(and(shr(192, sload(3)), 18446744073709551615), 18446744073709551615)), 18446744073709551615))
          if gt(__pf_packed_value, 18446744073709551615) {
            revert(0, 0)
          }
          sstore(2, or(and(sload(2), not(shl(64, 18446744073709551615))), shl(64, and(__pf_packed_value, 18446744073709551615))))
        }
      }
      let grossWanted := and(shr(64, sload(2)), 18446744073709551615)
      if iszero(iszero(eq(grossWanted, 0))) {
        revert(0, 0)
      }
      sstore(2, or(and(sload(2), not(shl(64, 18446744073709551615))), shl(64, and(grossWanted, 18446744073709551615))))
      switch gt(and(shr(0, sload(2)), 18446744073709551615), 0)
      case 0 { }
      default {
        if iszero(iszero(eq(and(shr(160, sload(1)), 18446744073709551615), 0))) {
          revert(0, 0)
        }
        let _pf_assets_up_numerator := __pf_checked_mul(grossWanted, and(shr(160, sload(1)), 18446744073709551615))
        let _pf_assets_up_quotient := div(_pf_assets_up_numerator, and(shr(0, sload(2)), 18446744073709551615))
        if iszero(iszero(lt(18446744073709551615, _pf_assets_up_quotient))) {
          revert(0, 0)
        }
        sstore(2, or(and(sload(2), not(shl(64, 18446744073709551615))), shl(64, and(_pf_assets_up_quotient, 18446744073709551615))))
        switch gt(mod(_pf_assets_up_numerator, and(shr(0, sload(2)), 18446744073709551615)), 0)
        case 0 { }
        default {
          if iszero(iszero(eq(_pf_assets_up_quotient, 18446744073709551615))) {
            revert(0, 0)
          }
          {
            let __pf_packed_value := __pf_checked_width(__pf_checked_add(__pf_checked_width(_pf_assets_up_quotient, 18446744073709551615), __pf_checked_width(1, 18446744073709551615)), 18446744073709551615)
            if gt(__pf_packed_value, 18446744073709551615) {
              revert(0, 0)
            }
            sstore(2, or(and(sload(2), not(shl(64, 18446744073709551615))), shl(64, and(__pf_packed_value, 18446744073709551615))))
          }
        }
      }
      let assetsWanted := and(shr(64, sload(2)), 18446744073709551615)
      if iszero(iszero(eq(assetsWanted, 0))) {
        revert(0, 0)
      }
      sstore(2, or(and(sload(2), not(shl(192, 18446744073709551615))), shl(192, and(__proof_forge_crosscall_1(and(shr(0, sload(0)), 1461501637330902918203684832716283019655932542975), 1889567281, and(shr(0, sload(1)), 1461501637330902918203684832716283019655932542975)), 18446744073709551615))))
      let _pf_pull := __proof_forge_crosscall_3(and(shr(0, sload(0)), 1461501637330902918203684832716283019655932542975), 599290589, caller(), and(shr(0, sload(1)), 1461501637330902918203684832716283019655932542975), assetsWanted)
      if iszero(eq(_pf_pull, 1)) {
        revert(0, 0)
      }
      let _pf_bal_after := __proof_forge_crosscall_1(and(shr(0, sload(0)), 1461501637330902918203684832716283019655932542975), 1889567281, and(shr(0, sload(1)), 1461501637330902918203684832716283019655932542975))
      {
        let __pf_packed_value := __pf_checked_width(__pf_checked_sub(__pf_checked_width(_pf_bal_after, 18446744073709551615), __pf_checked_width(and(shr(192, sload(2)), 18446744073709551615), 18446744073709551615)), 18446744073709551615)
        if gt(__pf_packed_value, 18446744073709551615) {
          revert(0, 0)
        }
        sstore(3, or(and(sload(3), not(shl(0, 18446744073709551615))), shl(0, and(__pf_packed_value, 18446744073709551615))))
      }
      if iszero(iszero(eq(and(shr(0, sload(3)), 18446744073709551615), 0))) {
        revert(0, 0)
      }
      let actual := and(shr(0, sload(3)), 18446744073709551615)
      sstore(2, or(and(sload(2), not(shl(64, 18446744073709551615))), shl(64, and(actual, 18446744073709551615))))
      switch gt(and(shr(0, sload(2)), 18446744073709551615), 0)
      case 0 { }
      default {
        if iszero(iszero(eq(and(shr(160, sload(1)), 18446744073709551615), 0))) {
          revert(0, 0)
        }
        {
          let __pf_packed_value := div(__pf_checked_width(__pf_checked_mul(__pf_checked_width(actual, 18446744073709551615), __pf_checked_width(and(shr(0, sload(2)), 18446744073709551615), 18446744073709551615)), 18446744073709551615), and(shr(160, sload(1)), 18446744073709551615))
          if gt(__pf_packed_value, 18446744073709551615) {
            revert(0, 0)
          }
          sstore(2, or(and(sload(2), not(shl(64, 18446744073709551615))), shl(64, and(__pf_packed_value, 18446744073709551615))))
        }
      }
      let grossAvailable := and(shr(64, sload(2)), 18446744073709551615)
      if iszero(iszero(lt(grossAvailable, grossWanted))) {
        revert(0, 0)
      }
      {
        let __pf_packed_value := __pf_checked_width(__pf_checked_sub(__pf_checked_width(grossWanted, 18446744073709551615), __pf_checked_width(shares, 18446744073709551615)), 18446744073709551615)
        if gt(__pf_packed_value, 18446744073709551615) {
          revert(0, 0)
        }
        sstore(2, or(and(sload(2), not(shl(128, 18446744073709551615))), shl(128, and(__pf_packed_value, 18446744073709551615))))
      }
      let userShares := shares
      let ta := and(shr(160, sload(1)), 18446744073709551615)
      {
        let __pf_packed_value := __pf_checked_width(__pf_checked_add(__pf_checked_width(ta, 18446744073709551615), __pf_checked_width(actual, 18446744073709551615)), 18446744073709551615)
        if gt(__pf_packed_value, 18446744073709551615) {
          revert(0, 0)
        }
        sstore(1, or(and(sload(1), not(shl(160, 18446744073709551615))), shl(160, and(__pf_packed_value, 18446744073709551615))))
      }
      let ts := and(shr(0, sload(2)), 18446744073709551615)
      {
        let __pf_packed_value := __pf_checked_width(__pf_checked_add(__pf_checked_width(ts, 18446744073709551615), __pf_checked_width(grossWanted, 18446744073709551615)), 18446744073709551615)
        if gt(__pf_packed_value, 18446744073709551615) {
          revert(0, 0)
        }
        sstore(2, or(and(sload(2), not(shl(0, 18446744073709551615))), shl(0, and(__pf_packed_value, 18446744073709551615))))
      }
      let bal := sload(__proof_forge_map_slot(6, receiver))
      __proof_forge_map_write(6, receiver, __pf_checked_add(bal, userShares))
      switch gt(and(shr(128, sload(2)), 18446744073709551615), 0)
      case 0 { }
      default {
        if iszero(iszero(eq(and(shr(0, sload(4)), 1461501637330902918203684832716283019655932542975), 0))) {
          revert(0, 0)
        }
        __proof_forge_map_write(6, and(shr(0, sload(4)), 1461501637330902918203684832716283019655932542975), __pf_checked_add(sload(__proof_forge_map_slot(6, and(shr(0, sload(4)), 1461501637330902918203684832716283019655932542975))), and(shr(128, sload(2)), 18446744073709551615)))
        {
          mstore(0, 38196372293521921433607444633801509737016894376733792893611070291108288410934)
          mstore(32, 18544826791913921923306290567797672742125270981606496584444378688767337168896)
          let __pf_event_topic0 := keccak256(0, 33)
          let __pf_event_indexed_topic0 := 0
          let __pf_event_indexed_topic1 := and(shr(0, sload(4)), 1461501637330902918203684832716283019655932542975)
          mstore(0, and(shr(128, sload(2)), 18446744073709551615))
          log3(0, 32, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1)
        }
      }
      {
        mstore(0, 30936501257503946518338176186595900852291947956669005746078969649791291962924)
        mstore(32, 53106884550783362696603933435631747706376370536716806060893931267679118688256)
        let __pf_event_topic0 := keccak256(0, 40)
        let __pf_event_indexed_topic0 := caller()
        let __pf_event_indexed_topic1 := receiver
        mstore(0, actual)
        mstore(32, userShares)
        log3(0, 64, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1)
      }
      {
        mstore(0, 38196372293521921433607444633801509737016894376733792893611070291108288410934)
        mstore(32, 18544826791913921923306290567797672742125270981606496584444378688767337168896)
        let __pf_event_topic0 := keccak256(0, 33)
        let __pf_event_indexed_topic0 := 0
        let __pf_event_indexed_topic1 := receiver
        mstore(0, userShares)
        log3(0, 32, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1)
      }
      sstore(4, or(and(sload(4), not(shl(160, 18446744073709551615))), shl(160, and(0, 18446744073709551615))))
      __pf_result := actual
    }
    function f_ERC4626_withdraw(assets, receiver, holder) -> __pf_result {
      if iszero(eq(and(shr(160, sload(4)), 18446744073709551615), 0)) {
        revert(0, 0)
      }
      sstore(4, or(and(sload(4), not(shl(160, 18446744073709551615))), shl(160, and(1, 18446744073709551615))))
      if iszero(iszero(eq(receiver, 0))) {
        revert(0, 0)
      }
      if iszero(iszero(eq(assets, 0))) {
        revert(0, 0)
      }
      if iszero(eq(caller(), holder)) {
        revert(0, 0)
      }
      sstore(2, or(and(sload(2), not(shl(64, 18446744073709551615))), shl(64, and(assets, 18446744073709551615))))
      switch gt(and(shr(0, sload(2)), 18446744073709551615), 0)
      case 0 { }
      default {
        if iszero(iszero(eq(and(shr(160, sload(1)), 18446744073709551615), 0))) {
          revert(0, 0)
        }
        let _pf_shares_up_numerator := __pf_checked_mul(assets, and(shr(0, sload(2)), 18446744073709551615))
        let _pf_shares_up_quotient := div(_pf_shares_up_numerator, and(shr(160, sload(1)), 18446744073709551615))
        if iszero(iszero(lt(18446744073709551615, _pf_shares_up_quotient))) {
          revert(0, 0)
        }
        sstore(2, or(and(sload(2), not(shl(64, 18446744073709551615))), shl(64, and(_pf_shares_up_quotient, 18446744073709551615))))
        switch gt(mod(_pf_shares_up_numerator, and(shr(160, sload(1)), 18446744073709551615)), 0)
        case 0 { }
        default {
          if iszero(iszero(eq(_pf_shares_up_quotient, 18446744073709551615))) {
            revert(0, 0)
          }
          {
            let __pf_packed_value := __pf_checked_width(__pf_checked_add(__pf_checked_width(_pf_shares_up_quotient, 18446744073709551615), __pf_checked_width(1, 18446744073709551615)), 18446744073709551615)
            if gt(__pf_packed_value, 18446744073709551615) {
              revert(0, 0)
            }
            sstore(2, or(and(sload(2), not(shl(64, 18446744073709551615))), shl(64, and(__pf_packed_value, 18446744073709551615))))
          }
        }
      }
      let shares := and(shr(64, sload(2)), 18446744073709551615)
      if iszero(iszero(eq(shares, 0))) {
        revert(0, 0)
      }
      sstore(2, or(and(sload(2), not(shl(64, 18446744073709551615))), shl(64, and(assets, 18446744073709551615))))
      sstore(2, or(and(sload(2), not(shl(128, 18446744073709551615))), shl(128, and(0, 18446744073709551615))))
      switch gt(and(shr(192, sload(3)), 18446744073709551615), 0)
      case 0 { }
      default {
        {
          let __pf_packed_value := div(__pf_checked_width(__pf_checked_mul(__pf_checked_width(and(shr(64, sload(2)), 18446744073709551615), 18446744073709551615), __pf_checked_width(and(shr(192, sload(3)), 18446744073709551615), 18446744073709551615)), 18446744073709551615), 10000)
          if gt(__pf_packed_value, 18446744073709551615) {
            revert(0, 0)
          }
          sstore(2, or(and(sload(2), not(shl(128, 18446744073709551615))), shl(128, and(__pf_packed_value, 18446744073709551615))))
        }
        {
          let __pf_packed_value := __pf_checked_width(__pf_checked_sub(__pf_checked_width(and(shr(64, sload(2)), 18446744073709551615), 18446744073709551615), __pf_checked_width(and(shr(128, sload(2)), 18446744073709551615), 18446744073709551615)), 18446744073709551615)
          if gt(__pf_packed_value, 18446744073709551615) {
            revert(0, 0)
          }
          sstore(2, or(and(sload(2), not(shl(64, 18446744073709551615))), shl(64, and(__pf_packed_value, 18446744073709551615))))
        }
      }
      let userAssets := and(shr(64, sload(2)), 18446744073709551615)
      if iszero(iszero(eq(userAssets, 0))) {
        revert(0, 0)
      }
      let ownerBal := sload(__proof_forge_map_slot(6, holder))
      if iszero(iszero(lt(ownerBal, shares))) {
        revert(0, 0)
      }
      __proof_forge_map_write(6, holder, __pf_checked_sub(ownerBal, shares))
      let ts := and(shr(0, sload(2)), 18446744073709551615)
      {
        let __pf_packed_value := __pf_checked_width(__pf_checked_sub(__pf_checked_width(ts, 18446744073709551615), __pf_checked_width(shares, 18446744073709551615)), 18446744073709551615)
        if gt(__pf_packed_value, 18446744073709551615) {
          revert(0, 0)
        }
        sstore(2, or(and(sload(2), not(shl(0, 18446744073709551615))), shl(0, and(__pf_packed_value, 18446744073709551615))))
      }
      sstore(2, or(and(sload(2), not(shl(192, 18446744073709551615))), shl(192, and(__proof_forge_crosscall_1(and(shr(0, sload(0)), 1461501637330902918203684832716283019655932542975), 1889567281, and(shr(0, sload(1)), 1461501637330902918203684832716283019655932542975)), 18446744073709551615))))
      sstore(3, or(and(sload(3), not(shl(64, 18446744073709551615))), shl(64, and(__proof_forge_crosscall_1(and(shr(0, sload(0)), 1461501637330902918203684832716283019655932542975), 1889567281, receiver), 18446744073709551615))))
      let _pf_push_recv := __proof_forge_crosscall_2(and(shr(0, sload(0)), 1461501637330902918203684832716283019655932542975), 2835717307, receiver, userAssets)
      if iszero(eq(_pf_push_recv, 1)) {
        revert(0, 0)
      }
      let _pf_recv_after := __proof_forge_crosscall_1(and(shr(0, sload(0)), 1461501637330902918203684832716283019655932542975), 1889567281, receiver)
      {
        let __pf_packed_value := __pf_checked_width(__pf_checked_sub(__pf_checked_width(_pf_recv_after, 18446744073709551615), __pf_checked_width(and(shr(64, sload(3)), 18446744073709551615), 18446744073709551615)), 18446744073709551615)
        if gt(__pf_packed_value, 18446744073709551615) {
          revert(0, 0)
        }
        sstore(3, or(and(sload(3), not(shl(128, 18446744073709551615))), shl(128, and(__pf_packed_value, 18446744073709551615))))
      }
      switch gt(and(shr(128, sload(2)), 18446744073709551615), 0)
      case 0 { }
      default {
        if iszero(iszero(eq(and(shr(0, sload(4)), 1461501637330902918203684832716283019655932542975), 0))) {
          revert(0, 0)
        }
        let _pf_exit_fee_push := __proof_forge_crosscall_2(and(shr(0, sload(0)), 1461501637330902918203684832716283019655932542975), 2835717307, and(shr(0, sload(4)), 1461501637330902918203684832716283019655932542975), and(shr(128, sload(2)), 18446744073709551615))
        if iszero(eq(_pf_exit_fee_push, 1)) {
          revert(0, 0)
        }
      }
      let _pf_bal_after_push := __proof_forge_crosscall_1(and(shr(0, sload(0)), 1461501637330902918203684832716283019655932542975), 1889567281, and(shr(0, sload(1)), 1461501637330902918203684832716283019655932542975))
      {
        let __pf_packed_value := __pf_checked_width(__pf_checked_sub(__pf_checked_width(and(shr(192, sload(2)), 18446744073709551615), 18446744073709551615), __pf_checked_width(_pf_bal_after_push, 18446744073709551615)), 18446744073709551615)
        if gt(__pf_packed_value, 18446744073709551615) {
          revert(0, 0)
        }
        sstore(3, or(and(sload(3), not(shl(0, 18446744073709551615))), shl(0, and(__pf_packed_value, 18446744073709551615))))
      }
      if iszero(iszero(eq(and(shr(0, sload(3)), 18446744073709551615), 0))) {
        revert(0, 0)
      }
      let actualLeft := and(shr(0, sload(3)), 18446744073709551615)
      let actualRecv := and(shr(128, sload(3)), 18446744073709551615)
      if iszero(iszero(lt(and(shr(160, sload(1)), 18446744073709551615), actualLeft))) {
        revert(0, 0)
      }
      let ta := and(shr(160, sload(1)), 18446744073709551615)
      {
        let __pf_packed_value := __pf_checked_width(__pf_checked_sub(__pf_checked_width(ta, 18446744073709551615), __pf_checked_width(actualLeft, 18446744073709551615)), 18446744073709551615)
        if gt(__pf_packed_value, 18446744073709551615) {
          revert(0, 0)
        }
        sstore(1, or(and(sload(1), not(shl(160, 18446744073709551615))), shl(160, and(__pf_packed_value, 18446744073709551615))))
      }
      {
        mstore(0, 39537540185534869899846227387854673775518960501829436153214943126112117814131)
        mstore(32, 20109214105440218599044677769547869317362912160027960781770907878064520167424)
        let __pf_event_topic0 := keccak256(0, 49)
        let __pf_event_indexed_topic0 := caller()
        let __pf_event_indexed_topic1 := receiver
        let __pf_event_indexed_topic2 := holder
        mstore(0, actualRecv)
        mstore(32, shares)
        log4(0, 64, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1, __pf_event_indexed_topic2)
      }
      {
        mstore(0, 38196372293521921433607444633801509737016894376733792893611070291108288410934)
        mstore(32, 18544826791913921923306290567797672742125270981606496584444378688767337168896)
        let __pf_event_topic0 := keccak256(0, 33)
        let __pf_event_indexed_topic0 := holder
        let __pf_event_indexed_topic1 := 0
        mstore(0, shares)
        log3(0, 32, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1)
      }
      sstore(4, or(and(sload(4), not(shl(160, 18446744073709551615))), shl(160, and(0, 18446744073709551615))))
      __pf_result := shares
    }
    function f_ERC4626_redeem(shares, receiver, holder) -> __pf_result {
      if iszero(eq(and(shr(160, sload(4)), 18446744073709551615), 0)) {
        revert(0, 0)
      }
      sstore(4, or(and(sload(4), not(shl(160, 18446744073709551615))), shl(160, and(1, 18446744073709551615))))
      if iszero(iszero(eq(receiver, 0))) {
        revert(0, 0)
      }
      if iszero(iszero(eq(shares, 0))) {
        revert(0, 0)
      }
      if iszero(eq(caller(), holder)) {
        revert(0, 0)
      }
      sstore(2, or(and(sload(2), not(shl(64, 18446744073709551615))), shl(64, and(shares, 18446744073709551615))))
      switch gt(and(shr(0, sload(2)), 18446744073709551615), 0)
      case 0 { }
      default {
        if iszero(iszero(eq(and(shr(160, sload(1)), 18446744073709551615), 0))) {
          revert(0, 0)
        }
        {
          let __pf_packed_value := div(__pf_checked_width(__pf_checked_mul(__pf_checked_width(shares, 18446744073709551615), __pf_checked_width(and(shr(160, sload(1)), 18446744073709551615), 18446744073709551615)), 18446744073709551615), and(shr(0, sload(2)), 18446744073709551615))
          if gt(__pf_packed_value, 18446744073709551615) {
            revert(0, 0)
          }
          sstore(2, or(and(sload(2), not(shl(64, 18446744073709551615))), shl(64, and(__pf_packed_value, 18446744073709551615))))
        }
      }
      let grossAssets := and(shr(64, sload(2)), 18446744073709551615)
      if iszero(iszero(eq(grossAssets, 0))) {
        revert(0, 0)
      }
      sstore(2, or(and(sload(2), not(shl(64, 18446744073709551615))), shl(64, and(grossAssets, 18446744073709551615))))
      sstore(2, or(and(sload(2), not(shl(128, 18446744073709551615))), shl(128, and(0, 18446744073709551615))))
      switch gt(and(shr(192, sload(3)), 18446744073709551615), 0)
      case 0 { }
      default {
        {
          let __pf_packed_value := div(__pf_checked_width(__pf_checked_mul(__pf_checked_width(and(shr(64, sload(2)), 18446744073709551615), 18446744073709551615), __pf_checked_width(and(shr(192, sload(3)), 18446744073709551615), 18446744073709551615)), 18446744073709551615), 10000)
          if gt(__pf_packed_value, 18446744073709551615) {
            revert(0, 0)
          }
          sstore(2, or(and(sload(2), not(shl(128, 18446744073709551615))), shl(128, and(__pf_packed_value, 18446744073709551615))))
        }
        {
          let __pf_packed_value := __pf_checked_width(__pf_checked_sub(__pf_checked_width(and(shr(64, sload(2)), 18446744073709551615), 18446744073709551615), __pf_checked_width(and(shr(128, sload(2)), 18446744073709551615), 18446744073709551615)), 18446744073709551615)
          if gt(__pf_packed_value, 18446744073709551615) {
            revert(0, 0)
          }
          sstore(2, or(and(sload(2), not(shl(64, 18446744073709551615))), shl(64, and(__pf_packed_value, 18446744073709551615))))
        }
      }
      let userAssets := and(shr(64, sload(2)), 18446744073709551615)
      if iszero(iszero(eq(userAssets, 0))) {
        revert(0, 0)
      }
      let ownerBal := sload(__proof_forge_map_slot(6, holder))
      if iszero(iszero(lt(ownerBal, shares))) {
        revert(0, 0)
      }
      __proof_forge_map_write(6, holder, __pf_checked_sub(ownerBal, shares))
      let ts := and(shr(0, sload(2)), 18446744073709551615)
      {
        let __pf_packed_value := __pf_checked_width(__pf_checked_sub(__pf_checked_width(ts, 18446744073709551615), __pf_checked_width(shares, 18446744073709551615)), 18446744073709551615)
        if gt(__pf_packed_value, 18446744073709551615) {
          revert(0, 0)
        }
        sstore(2, or(and(sload(2), not(shl(0, 18446744073709551615))), shl(0, and(__pf_packed_value, 18446744073709551615))))
      }
      sstore(2, or(and(sload(2), not(shl(192, 18446744073709551615))), shl(192, and(__proof_forge_crosscall_1(and(shr(0, sload(0)), 1461501637330902918203684832716283019655932542975), 1889567281, and(shr(0, sload(1)), 1461501637330902918203684832716283019655932542975)), 18446744073709551615))))
      sstore(3, or(and(sload(3), not(shl(64, 18446744073709551615))), shl(64, and(__proof_forge_crosscall_1(and(shr(0, sload(0)), 1461501637330902918203684832716283019655932542975), 1889567281, receiver), 18446744073709551615))))
      let _pf_push_recv := __proof_forge_crosscall_2(and(shr(0, sload(0)), 1461501637330902918203684832716283019655932542975), 2835717307, receiver, userAssets)
      if iszero(eq(_pf_push_recv, 1)) {
        revert(0, 0)
      }
      let _pf_recv_after := __proof_forge_crosscall_1(and(shr(0, sload(0)), 1461501637330902918203684832716283019655932542975), 1889567281, receiver)
      {
        let __pf_packed_value := __pf_checked_width(__pf_checked_sub(__pf_checked_width(_pf_recv_after, 18446744073709551615), __pf_checked_width(and(shr(64, sload(3)), 18446744073709551615), 18446744073709551615)), 18446744073709551615)
        if gt(__pf_packed_value, 18446744073709551615) {
          revert(0, 0)
        }
        sstore(3, or(and(sload(3), not(shl(128, 18446744073709551615))), shl(128, and(__pf_packed_value, 18446744073709551615))))
      }
      switch gt(and(shr(128, sload(2)), 18446744073709551615), 0)
      case 0 { }
      default {
        if iszero(iszero(eq(and(shr(0, sload(4)), 1461501637330902918203684832716283019655932542975), 0))) {
          revert(0, 0)
        }
        let _pf_exit_fee_push := __proof_forge_crosscall_2(and(shr(0, sload(0)), 1461501637330902918203684832716283019655932542975), 2835717307, and(shr(0, sload(4)), 1461501637330902918203684832716283019655932542975), and(shr(128, sload(2)), 18446744073709551615))
        if iszero(eq(_pf_exit_fee_push, 1)) {
          revert(0, 0)
        }
      }
      let _pf_bal_after_push := __proof_forge_crosscall_1(and(shr(0, sload(0)), 1461501637330902918203684832716283019655932542975), 1889567281, and(shr(0, sload(1)), 1461501637330902918203684832716283019655932542975))
      {
        let __pf_packed_value := __pf_checked_width(__pf_checked_sub(__pf_checked_width(and(shr(192, sload(2)), 18446744073709551615), 18446744073709551615), __pf_checked_width(_pf_bal_after_push, 18446744073709551615)), 18446744073709551615)
        if gt(__pf_packed_value, 18446744073709551615) {
          revert(0, 0)
        }
        sstore(3, or(and(sload(3), not(shl(0, 18446744073709551615))), shl(0, and(__pf_packed_value, 18446744073709551615))))
      }
      if iszero(iszero(eq(and(shr(0, sload(3)), 18446744073709551615), 0))) {
        revert(0, 0)
      }
      let actualLeft := and(shr(0, sload(3)), 18446744073709551615)
      let actualRecv := and(shr(128, sload(3)), 18446744073709551615)
      if iszero(iszero(lt(and(shr(160, sload(1)), 18446744073709551615), actualLeft))) {
        revert(0, 0)
      }
      let ta := and(shr(160, sload(1)), 18446744073709551615)
      {
        let __pf_packed_value := __pf_checked_width(__pf_checked_sub(__pf_checked_width(ta, 18446744073709551615), __pf_checked_width(actualLeft, 18446744073709551615)), 18446744073709551615)
        if gt(__pf_packed_value, 18446744073709551615) {
          revert(0, 0)
        }
        sstore(1, or(and(sload(1), not(shl(160, 18446744073709551615))), shl(160, and(__pf_packed_value, 18446744073709551615))))
      }
      {
        mstore(0, 39537540185534869899846227387854673775518960501829436153214943126112117814131)
        mstore(32, 20109214105440218599044677769547869317362912160027960781770907878064520167424)
        let __pf_event_topic0 := keccak256(0, 49)
        let __pf_event_indexed_topic0 := caller()
        let __pf_event_indexed_topic1 := receiver
        let __pf_event_indexed_topic2 := holder
        mstore(0, actualRecv)
        mstore(32, shares)
        log4(0, 64, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1, __pf_event_indexed_topic2)
      }
      sstore(4, or(and(sload(4), not(shl(160, 18446744073709551615))), shl(160, and(0, 18446744073709551615))))
      __pf_result := actualRecv
    }
    function f_ERC4626_transfer(recipient, amount) -> __pf_result {
      if iszero(iszero(eq(recipient, 0))) {
        revert(0, 0)
      }
      let sender := caller()
      let srcBal := sload(__proof_forge_map_slot(6, sender))
      if iszero(iszero(lt(srcBal, amount))) {
        revert(0, 0)
      }
      __proof_forge_map_write(6, sender, __pf_checked_sub(srcBal, amount))
      let dstBal := sload(__proof_forge_map_slot(6, recipient))
      __proof_forge_map_write(6, recipient, __pf_checked_add(dstBal, amount))
      {
        mstore(0, 38196372293521921433607444633801509737016894376733792893611070291108288410934)
        mstore(32, 18544826791913921923306290567797672742125270981606496584444378688767337168896)
        let __pf_event_topic0 := keccak256(0, 33)
        let __pf_event_indexed_topic0 := sender
        let __pf_event_indexed_topic1 := recipient
        mstore(0, amount)
        log3(0, 32, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1)
      }
      __pf_result := 1
    }
    function f_ERC4626_approve(spender, amount) -> __pf_result {
      let holder := caller()
      if iszero(iszero(eq(spender, 0))) {
        revert(0, 0)
      }
      {
        let __pf_storage_slot := __proof_forge_map_slot(__proof_forge_map_slot(7, holder), spender)
        let __pf_storage_presence_slot := __proof_forge_map_presence_slot(__proof_forge_map_slot(7, holder), spender)
        sstore(__pf_storage_slot, amount)
        sstore(__pf_storage_presence_slot, 1)
      }
      {
        mstore(0, 29598998109930618199054758324288223757593108964568133265786181954376800810294)
        mstore(32, 18544826791913921923306290567797672742125270981606496584444378688767337168896)
        let __pf_event_topic0 := keccak256(0, 33)
        let __pf_event_indexed_topic0 := holder
        let __pf_event_indexed_topic1 := spender
        mstore(0, amount)
        log3(0, 32, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1)
      }
      __pf_result := 1
    }
    function f_ERC4626_init(assetAddr, selfAddr, feeBpsVal, feeRecipientAddr) {
      if iszero(eq(and(shr(0, sload(5)), 18446744073709551615), 0)) {
        revert(0, 0)
      }
      sstore(5, or(and(sload(5), not(shl(0, 18446744073709551615))), shl(0, and(1, 18446744073709551615))))
      if iszero(iszero(eq(assetAddr, 0))) {
        revert(0, 0)
      }
      if iszero(eq(selfAddr, address())) {
        revert(0, 0)
      }
      if iszero(iszero(lt(10000, feeBpsVal))) {
        revert(0, 0)
      }
      switch gt(feeBpsVal, 0)
      case 0 { }
      default {
        if iszero(iszero(eq(feeRecipientAddr, 0))) {
          revert(0, 0)
        }
      }
      sstore(0, or(and(sload(0), not(shl(0, 1461501637330902918203684832716283019655932542975))), shl(0, and(assetAddr, 1461501637330902918203684832716283019655932542975))))
      sstore(1, or(and(sload(1), not(shl(0, 1461501637330902918203684832716283019655932542975))), shl(0, and(selfAddr, 1461501637330902918203684832716283019655932542975))))
      sstore(3, or(and(sload(3), not(shl(192, 18446744073709551615))), shl(192, and(feeBpsVal, 18446744073709551615))))
      sstore(4, or(and(sload(4), not(shl(0, 1461501637330902918203684832716283019655932542975))), shl(0, and(feeRecipientAddr, 1461501637330902918203684832716283019655932542975))))
      sstore(1, or(and(sload(1), not(shl(160, 18446744073709551615))), shl(160, and(0, 18446744073709551615))))
      sstore(2, or(and(sload(2), not(shl(0, 18446744073709551615))), shl(0, and(0, 18446744073709551615))))
      sstore(2, or(and(sload(2), not(shl(128, 18446744073709551615))), shl(128, and(0, 18446744073709551615))))
    }
    function __proof_forge_map_slot(slot, key) -> result {
      mstore(0, key)
      mstore(32, slot)
      result := keccak256(0, 64)
    }
    function __proof_forge_map_presence_slot(slot, key) -> result {
      mstore(0, slot)
      mstore(32, 1969478005224772198022937154314036040895674356107534287685)
      let _presence_slot := keccak256(0, 64)
      mstore(0, key)
      mstore(32, _presence_slot)
      result := keccak256(0, 64)
    }
    function __proof_forge_map_write(slot, key, value) {
      let _slot := __proof_forge_map_slot(slot, key)
      sstore(_slot, value)
      sstore(__proof_forge_map_presence_slot(slot, key), 1)
    }
    function __pf_checked_width(value, maxValue) -> result {
      if gt(value, maxValue) {
        revert(0, 0)
      }
      result := value
    }
    function __pf_checked_add(a, b) -> r {
      if gt(a, sub(115792089237316195423570985008687907853269984665640564039457584007913129639935, b)) {
        revert(0, 0)
      }
      r := add(a, b)
    }
    function __pf_checked_sub(a, b) -> r {
      if gt(b, a) {
        revert(0, 0)
      }
      r := sub(a, b)
    }
    function __pf_checked_mul(a, b) -> r {
      if or(iszero(a), iszero(b)) {
        r := 0
        leave
      }
      if gt(a, div(115792089237316195423570985008687907853269984665640564039457584007913129639935, b)) {
        revert(0, 0)
      }
      r := mul(a, b)
    }
    function __proof_forge_crosscall_1(target, selector, arg0) -> result {
      mstore(0, shl(224, selector))
      mstore(4, arg0)
      let _success := call(gas(), target, 0, 0, 36, 0, 32)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 32) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 32)
      result := mload(0)
    }
    function __proof_forge_crosscall_3(target, selector, arg0, arg1, arg2) -> result {
      mstore(0, shl(224, selector))
      mstore(4, arg0)
      mstore(36, arg1)
      mstore(68, arg2)
      let _success := call(gas(), target, 0, 0, 100, 0, 32)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 32) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 32)
      result := mload(0)
    }
    function __proof_forge_crosscall_2(target, selector, arg0, arg1) -> result {
      mstore(0, shl(224, selector))
      mstore(4, arg0)
      mstore(36, arg1)
      let _success := call(gas(), target, 0, 0, 68, 0, 32)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 32) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 32)
      result := mload(0)
    }
  }
}
