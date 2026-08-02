;; Negative: more than one memory section.
;; Assemble with: wat2wasm --enable-multi-memory multi_memory.wat
;; cosmwasm-check 3.0.9 rejects multi-memory at deserialization.
(module
  (memory 1)
  (memory 1)
  (func $allocate (export "allocate") (param i32) (result i32)
    local.get 0)
  (func $deallocate (export "deallocate") (param i32)
    nop)
  (func $interface_version_8 (export "interface_version_8")
    nop)
)
