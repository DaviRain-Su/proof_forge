(* ProofForge-owned structured provider overlay for WasmCert-Coq 2.2.1 at
   revision 9ab0f87f03fff5507749efc273ec662fe27e6d14. This file is compiled
   inside that exact upstream source tree; it is not a second Wasm semantics. *)
open Big_int_Z

module String_map = Map.Make (String)

let provider_revision = "9ab0f87f03fff5507749efc273ec662fe27e6d14"
let request_schema = "proof-forge.near.wasmcert-request.v1"
let result_schema = "proof-forge.near.wasmcert-result.v1"
let invocation_schema = "proof-forge.near.wasmcert-invocation.v1"
let trace_schema = "proof-forge.near.wasmcert-host-trace.v1"
let observation_schema = "proof-forge.near.wasmcert-observation.v1"
let host_profile = "proof-forge.near.wasmcert-host.v1"
let observation_policy = "proof-forge.near.strict-call-observation.v1"
let max_fuel = 10_000_000
let max_input_bytes = 65_536
let max_request_wire_bytes = 1_048_576
let max_artifact_wire_bytes = 33_554_432
let max_wasm_bytes = 33_554_432
let max_storage_rows = 256
let max_storage_key_bytes = 1_024
let max_storage_value_bytes = 1_048_576
let max_payload_bytes = 8_388_608
let max_trace_events = 100_000
let max_event_payload_bytes = 1_048_576
let max_logs = 256
let max_context_promise_results = 64
let max_output_data_receivers = 64
let max_initial_memory_pages = 256

let fail fmt = Printf.ksprintf (fun message -> raise (Invalid_argument message)) fmt

let read_file path =
  let channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr channel)
    (fun () -> really_input_string channel (in_channel_length channel))

let read_regular_file ~context ~max_bytes path =
  let stat = Unix.LargeFile.lstat path in
  if stat.Unix.LargeFile.st_kind <> Unix.S_REG then
    fail "%s must be a regular file" context;
  if Int64.compare stat.Unix.LargeFile.st_size (Int64.of_int max_bytes) > 0 then
    fail "%s exceeds the %d-byte limit" context max_bytes;
  read_file path

let write_file path contents =
  let descriptor = Unix.openfile path
      [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_EXCL ] 0o600 in
  let channel = Unix.out_channel_of_descr descriptor in
  Fun.protect
    ~finally:(fun () -> close_out_noerr channel)
    (fun () -> output_string channel contents)

let sha256_string value = Digestif.SHA256.(to_hex (digest_string value))
let sha256_file path = sha256_string (read_file path)
let digest_wire hex = "sha256:" ^ hex

let lowercase_hex_digit value =
  if value < 10 then Char.chr (Char.code '0' + value)
  else Char.chr (Char.code 'a' + value - 10)

let hex_of_string value =
  let result = Bytes.create (String.length value * 2) in
  String.iteri
    (fun index character ->
      let byte = Char.code character in
      Bytes.set result (index * 2) (lowercase_hex_digit (byte lsr 4));
      Bytes.set result (index * 2 + 1) (lowercase_hex_digit (byte land 0x0f)))
    value;
  Bytes.unsafe_to_string result

let nibble_of_lowercase_hex = function
  | '0' .. '9' as character -> Char.code character - Char.code '0'
  | 'a' .. 'f' as character -> 10 + Char.code character - Char.code 'a'
  | _ -> fail "expected lowercase hexadecimal bytes"

let string_of_hex ~context ~max_bytes value =
  if String.length value mod 2 <> 0 then fail "%s has an incomplete byte pair" context;
  let length = String.length value / 2 in
  if length > max_bytes then fail "%s exceeds its %d-byte limit" context max_bytes;
  String.init length (fun index ->
      let high = nibble_of_lowercase_hex value.[index * 2] in
      let low = nibble_of_lowercase_hex value.[index * 2 + 1] in
      Char.chr ((high lsl 4) lor low))

let z_of_int = big_int_of_int
let z_compare = compare_big_int
let z_zero = zero_big_int
let z_one = unit_big_int
let z_u64_modulus = shift_left_big_int unit_big_int 64
let z_u64_max = pred_big_int z_u64_modulus

let uint64_hex value =
  if z_compare value z_zero < 0 || z_compare value z_u64_max > 0 then
    fail "value is outside the unsigned i64 range";
  let result = Bytes.create 8 in
  for index = 0 to 7 do
    let shifted = shift_right_big_int value (index * 8) in
    Bytes.set result index (Char.chr (int_of_big_int (and_big_int shifted (big_int_of_int 255))))
  done;
  hex_of_string (Bytes.unsafe_to_string result)

let z_of_u64_hex ~context value =
  let bytes = string_of_hex ~context ~max_bytes:8 value in
  if String.length bytes <> 8 then fail "%s must encode exactly eight bytes" context;
  let result = ref z_zero in
  String.iteri
    (fun index character ->
      result := add_big_int !result (shift_left_big_int (big_int_of_int (Char.code character)) (index * 8)))
    bytes;
  !result

let expect_assoc context = function
  | `Assoc fields -> fields
  | _ -> fail "%s must be an object" context

let expect_list context = function
  | `List values -> values
  | _ -> fail "%s must be an array" context

let expect_string context = function
  | `String value -> value
  | _ -> fail "%s must be a string" context

let expect_bool context = function
  | `Bool value -> value
  | _ -> fail "%s must be a boolean" context

let expect_int context = function
  | `Int value -> value
  | `Intlit value ->
      (try int_of_string value with Failure _ -> fail "%s is outside the supported integer range" context)
  | _ -> fail "%s must be an integer" context

let expect_exact_fields context names fields =
  let actual = List.map fst fields in
  if actual <> names then
    fail "%s has unknown, missing, duplicate, or noncanonical fields" context

let field context name fields =
  match List.assoc_opt name fields with
  | Some value -> value
  | None -> fail "%s is missing field %s" context name

let parse_canonical_json context contents =
  let json =
    try Yojson.Safe.from_string contents
    with Yojson.Json_error message -> fail "%s is not JSON: %s" context message
  in
  if Yojson.Safe.to_string json <> contents then
    fail "%s is not canonical compact JSON" context;
  json

let is_lower_hex value =
  String.for_all (function '0' .. '9' | 'a' .. 'f' -> true | _ -> false) value

let validate_digest context value =
  if String.length value <> 71 || String.sub value 0 7 <> "sha256:" ||
     not (is_lower_hex (String.sub value 7 64))
  then fail "%s must be sha256 followed by 64 lowercase hexadecimal characters" context

let validate_project_relative_path context value =
  if value = "" || not (Filename.is_relative value) || String.contains value '\000' then
    fail "%s must be a nonempty project-relative path" context;
  let segments = String.split_on_char '/' value in
  if List.exists (fun segment -> segment = "" || segment = "." || segment = "..") segments then
    fail "%s must not contain empty, dot, or parent segments" context

let is_near_account_id value =
  let length = String.length value in
  length >= 2 && length <= 64 && value.[0] <> '.' && value.[length - 1] <> '.' &&
  String.for_all
    (function
      | 'a' .. 'z' | '0' .. '9' | '_' | '-' | '.' -> true
      | _ -> false)
    value

let expect_near_account_id context value =
  let account_id = expect_string context value in
  if not (is_near_account_id account_id) then
    fail "%s is not a strict NEAR account id" context;
  account_id

let expect_exact_hex context bytes value =
  let decoded = string_of_hex ~context ~max_bytes:bytes (expect_string context value) in
  if String.length decoded <> bytes then
    fail "%s must encode exactly %d bytes" context bytes;
  decoded

let parse_promise_result index value =
  let context = Printf.sprintf "promiseResults[%d]" index in
  let fields = expect_assoc context value in
  expect_exact_fields context [ "dataHex"; "status" ] fields;
  let data = string_of_hex ~context:(context ^ ".dataHex") ~max_bytes:max_event_payload_bytes
      (expect_string (context ^ ".dataHex") (field context "dataHex" fields)) in
  let status = expect_string (context ^ ".status") (field context "status" fields) in
  if status <> "not-ready" && status <> "successful" && status <> "failed" then
    fail "%s has an unsupported status" context;
  if status <> "successful" && data <> "" then
    fail "%s must carry empty data unless successful" context;
  data

type request = {
  fuel : int;
  input_wasm_path : string;
  input_wasm_sha256 : string;
  invocation_path : string;
  invocation_sha256 : string;
}

let parse_request contents =
  let fields = expect_assoc "WasmCert request" (parse_canonical_json "WasmCert request" contents) in
  expect_exact_fields "WasmCert request"
    [ "fuel"; "inputWasmPath"; "inputWasmSha256"; "invocationPath";
      "invocationSha256"; "providerRevision"; "schema" ] fields;
  let fuel = expect_int "fuel" (field "WasmCert request" "fuel" fields) in
  if fuel < 1 || fuel > max_fuel then fail "fuel must be in 1..%d" max_fuel;
  let input_wasm_path = expect_string "inputWasmPath" (field "WasmCert request" "inputWasmPath" fields) in
  let invocation_path = expect_string "invocationPath" (field "WasmCert request" "invocationPath" fields) in
  validate_project_relative_path "inputWasmPath" input_wasm_path;
  validate_project_relative_path "invocationPath" invocation_path;
  if input_wasm_path = invocation_path then fail "input and invocation paths must differ";
  let input_wasm_sha256 = expect_string "inputWasmSha256" (field "WasmCert request" "inputWasmSha256" fields) in
  let invocation_sha256 = expect_string "invocationSha256" (field "WasmCert request" "invocationSha256" fields) in
  validate_digest "inputWasmSha256" input_wasm_sha256;
  validate_digest "invocationSha256" invocation_sha256;
  if expect_string "providerRevision" (field "WasmCert request" "providerRevision" fields) <> provider_revision then
    fail "provider revision does not match";
  if expect_string "schema" (field "WasmCert request" "schema" fields) <> request_schema then
    fail "request schema does not match";
  { fuel; input_wasm_path; input_wasm_sha256; invocation_path; invocation_sha256 }

type invocation = {
  export_name : string;
  input : string;
  attached_deposit : string;
  is_view : bool;
  pre_storage : string String_map.t;
}

let parse_storage_row index json =
  let context = Printf.sprintf "preStorage[%d]" index in
  let fields = expect_assoc context json in
  expect_exact_fields context [ "keyHex"; "valueHex" ] fields;
  let key = string_of_hex ~context:(context ^ ".keyHex") ~max_bytes:max_storage_key_bytes
      (expect_string (context ^ ".keyHex") (field context "keyHex" fields)) in
  let value = string_of_hex ~context:(context ^ ".valueHex") ~max_bytes:max_storage_value_bytes
      (expect_string (context ^ ".valueHex") (field context "valueHex" fields)) in
  if key = "" then fail "%s key must not be empty" context;
  (key, value)

let parse_invocation contents =
  let fields = expect_assoc "WasmCert invocation" (parse_canonical_json "WasmCert invocation" contents) in
  expect_exact_fields "WasmCert invocation"
    [ "context"; "exportName"; "hostProfile"; "inputHex";
      "observationPolicy"; "preStorage"; "schema" ] fields;
  if expect_string "invocation schema" (field "WasmCert invocation" "schema" fields) <> invocation_schema then
    fail "invocation schema does not match";
  if expect_string "hostProfile" (field "WasmCert invocation" "hostProfile" fields) <> host_profile then
    fail "invocation host profile does not match";
  if expect_string "observationPolicy" (field "WasmCert invocation" "observationPolicy" fields) <> observation_policy then
    fail "invocation observation policy does not match";
  let export_name = expect_string "exportName" (field "WasmCert invocation" "exportName" fields) in
  if export_name = "" then fail "exportName must not be empty";
  let input = string_of_hex ~context:"inputHex" ~max_bytes:max_input_bytes
      (expect_string "inputHex" (field "WasmCert invocation" "inputHex" fields)) in
  let context_fields = expect_assoc "WasmCert context" (field "WasmCert invocation" "context" fields) in
  expect_exact_fields "WasmCert context"
    [ "accountBalanceHex"; "accountLockedBalanceHex"; "attachedDepositHex";
      "blockHeightHex"; "blockTimestampNanosHex"; "currentAccountId";
      "epochHeightHex"; "isView"; "outputDataReceivers";
      "predecessorAccountId"; "prepaidGasHex"; "promiseResults";
      "randomSeedHex"; "signerAccountId"; "signerAccountPkHex";
      "storageUsageHex" ] context_fields;
  let attached_deposit = string_of_hex ~context:"attachedDepositHex" ~max_bytes:16
      (expect_string "attachedDepositHex" (field "WasmCert context" "attachedDepositHex" context_fields)) in
  if String.length attached_deposit <> 16 then fail "attachedDepositHex must encode 16 bytes";
  let is_view = expect_bool "isView" (field "WasmCert context" "isView" context_fields) in
  if is_view && attached_deposit <> String.make 16 '\000' then
    fail "view invocation must have zero attached deposit";
  List.iter (fun name ->
      ignore (z_of_u64_hex ~context:name
        (expect_string name (field "WasmCert context" name context_fields))))
    [ "blockHeightHex"; "blockTimestampNanosHex"; "epochHeightHex";
      "prepaidGasHex"; "storageUsageHex" ];
  List.iter (fun (name, bytes) ->
      ignore (expect_exact_hex name bytes (field "WasmCert context" name context_fields)))
    [ ("accountBalanceHex", 16); ("accountLockedBalanceHex", 16);
      ("randomSeedHex", 32) ];
  let signer_pk = string_of_hex ~context:"signerAccountPkHex" ~max_bytes:65
      (expect_string "signerAccountPkHex"
        (field "WasmCert context" "signerAccountPkHex" context_fields)) in
  if String.length signer_pk <> 33 && String.length signer_pk <> 65 then
    fail "signerAccountPkHex must encode exactly 33 or 65 bytes";
  List.iter (fun name ->
      ignore (expect_near_account_id name (field "WasmCert context" name context_fields)))
    [ "currentAccountId"; "signerAccountId"; "predecessorAccountId" ];
  let receivers = expect_list "outputDataReceivers"
      (field "WasmCert context" "outputDataReceivers" context_fields) in
  if List.length receivers > max_output_data_receivers then
    fail "outputDataReceivers exceeds the strict profile limit";
  List.iteri (fun index receiver ->
      ignore (expect_near_account_id
        (Printf.sprintf "outputDataReceivers[%d]" index) receiver)) receivers;
  let promise_results = expect_list "promiseResults"
      (field "WasmCert context" "promiseResults" context_fields) in
  if List.length promise_results > max_context_promise_results then
    fail "promiseResults exceeds the strict profile limit";
  let promise_bytes = List.mapi parse_promise_result promise_results
      |> List.fold_left (fun total payload -> total + String.length payload) 0 in
  if promise_bytes > max_payload_bytes then
    fail "promiseResults exceeds the aggregate payload limit";
  let rows = expect_list "preStorage" (field "WasmCert invocation" "preStorage" fields) in
  if List.length rows > max_storage_rows then fail "preStorage has too many rows";
  let parsed_rows = List.mapi parse_storage_row rows in
  let rec check_sorted previous aggregate map = function
    | [] -> map
    | (key, value) :: rest ->
        (match previous with
         | Some prior when String.compare prior key >= 0 -> fail "preStorage keys must be unique and byte-sorted"
         | _ -> ());
        let aggregate = aggregate + String.length key + String.length value in
        if aggregate > max_payload_bytes then fail "preStorage exceeds aggregate payload limit";
        check_sorted (Some key) aggregate (String_map.add key value map) rest
  in
  let pre_storage = check_sorted None 0 String_map.empty parsed_rows in
  { export_name; input; attached_deposit; is_view; pre_storage }

type host_function =
  | Input
  | Register_len
  | Read_register
  | Storage_read
  | Storage_write
  | Value_return
  | Attached_deposit
  | Log_utf8
  | Panic_utf8

type trace_event = {
  import_name : string;
  arguments : big_int list;
  result : big_int option;
  payloads : string list;
}

type host_state = {
  input : string;
  attached_deposit : string;
  is_view : bool;
  storage : string String_map.t;
  registers : string String_map.t;
  return_data : string option;
  logs_rev : string list;
  trace_rev : trace_event list;
  trace_count : int;
  trace_payload_bytes : int;
  host_trapped : bool;
}

let latest_host_state : host_state option ref = ref None

let host_name = function
  | Input -> "env.input"
  | Register_len -> "env.register_len"
  | Read_register -> "env.read_register"
  | Storage_read -> "env.storage_read"
  | Storage_write -> "env.storage_write"
  | Value_return -> "env.value_return"
  | Attached_deposit -> "env.attached_deposit"
  | Log_utf8 -> "env.log_utf8"
  | Panic_utf8 -> "env.panic_utf8"

let i64_type = Extract.T_num Extract.T_i64
let function_type parameters results = Extract.Tf (parameters, results)

let host_type = function
  | Input | Attached_deposit -> function_type [ i64_type ] []
  | Register_len -> function_type [ i64_type ] [ i64_type ]
  | Read_register | Value_return | Log_utf8 | Panic_utf8 ->
      function_type [ i64_type; i64_type ] []
  | Storage_read -> function_type [ i64_type; i64_type; i64_type ] [ i64_type ]
  | Storage_write ->
      function_type [ i64_type; i64_type; i64_type; i64_type; i64_type ] [ i64_type ]

let host_functions =
  [ Input; Register_len; Read_register; Storage_read; Storage_write;
    Value_return; Attached_deposit; Log_utf8; Panic_utf8 ]

let z_of_i64_value = function
  | Extract.VAL_num (Extract.VAL_int64 value) ->
      Some (Extract.Wasm_int.coq_Z_of_uint Extract.i64m value)
  | _ -> None

let i64_value value = Extract.Utility.vali64_of_Z value

let byte_list_of_string value =
  List.init (String.length value) (fun index -> Extract.compcert_byte_of_byte value.[index])

let string_of_byte_list value =
  let buffer = Buffer.create (List.length value) in
  List.iter (fun byte -> Buffer.add_char buffer (Extract.byte_of_compcert_byte byte)) value;
  Buffer.contents buffer

let replace_only_memory store memory =
  match store.Extract.s_mems with
  | [ _ ] -> { store with Extract.s_mems = [ memory ] }
  | _ -> fail "strict NEAR host requires exactly one module memory"

let read_memory store pointer length =
  match store.Extract.s_mems with
  | [ memory ] ->
      (match Extract.read_bytes Extract.memory_instance memory pointer length with
       | Some bytes -> Some (string_of_byte_list bytes)
       | None -> None)
  | _ -> None

let write_memory store pointer payload =
  match store.Extract.s_mems with
  | [ memory ] ->
      (match Extract.write_bytes_meminst Extract.memory_instance memory pointer (byte_list_of_string payload) with
       | Some memory' -> Some (replace_only_memory store memory')
       | None -> None)
  | _ -> None

let register_key value = string_of_big_int value

let add_trace state import_name arguments result payloads =
  let payload_bytes = List.fold_left (fun total payload -> total + String.length payload) 0 payloads in
  if state.trace_count >= max_trace_events ||
     state.trace_payload_bytes + payload_bytes > max_payload_bytes ||
     List.exists (fun payload -> String.length payload > max_event_payload_bytes) payloads
  then None
  else
    Some { state with
      trace_rev = { import_name; arguments; result; payloads } :: state.trace_rev;
      trace_count = state.trace_count + 1;
      trace_payload_bytes = state.trace_payload_bytes + payload_bytes;
    }

let remember state = latest_host_state := Some state; state

let host_trap state store =
  let state = remember { state with host_trapped = true } in
  (state, Some (store, Extract.Result_trap))

let host_return state store values =
  let state = remember state in
  (state, Some (store, Extract.Result_values values))

module Near_host : Extract.Parametric_host with
  type host_function = host_function and type host_state_type = host_state = struct
  type nonrec host_function = host_function
  let host_function_eq_dec left right = left = right
  let hfc = Obj.magic host_function_eq_dec
  type nonrec host_state_type = host_state

  let host_apply_pure state store actual_type host_function values =
    let arguments = List.map z_of_i64_value values in
    if actual_type <> host_type host_function || List.exists Option.is_none arguments then
      host_trap state store
    else
      let arguments = List.map Option.get arguments in
      let trace result payloads state = add_trace state (host_name host_function) arguments result payloads in
      match host_function, arguments with
      | Input, [ register_id ] ->
          let state = { state with registers = String_map.add (register_key register_id) state.input state.registers } in
          (match trace None [ state.input ] state with
           | Some state -> host_return state store []
           | None -> host_trap state store)
      | Register_len, [ register_id ] ->
          let result =
            match String_map.find_opt (register_key register_id) state.registers with
            | Some payload -> big_int_of_int (String.length payload)
            | None -> z_u64_max
          in
          (match trace (Some result) [] state with
           | Some state -> host_return state store [ i64_value result ]
           | None -> host_trap state store)
      | Read_register, [ register_id; pointer ] ->
          (match String_map.find_opt (register_key register_id) state.registers with
           | None -> host_trap state store
           | Some payload ->
               (match write_memory store pointer payload with
                | None -> host_trap state store
                | Some store ->
                    (match trace None [ payload ] state with
                     | Some state -> host_return state store []
                     | None -> host_trap state store)))
      | Storage_read, [ key_length; key_pointer; register_id ] ->
          (match read_memory store key_pointer key_length with
           | None -> host_trap state store
           | Some key ->
               (match String_map.find_opt key state.storage with
                | None ->
                    (match trace (Some z_zero) [ key ] state with
                     | Some state -> host_return state store [ i64_value z_zero ]
                     | None -> host_trap state store)
                | Some value ->
                    let state = { state with registers = String_map.add (register_key register_id) value state.registers } in
                    (match trace (Some z_one) [ key; value ] state with
                     | Some state -> host_return state store [ i64_value z_one ]
                     | None -> host_trap state store)))
      | Storage_write, [ key_length; key_pointer; value_length; value_pointer; register_id ] ->
          (match read_memory store key_pointer key_length, read_memory store value_pointer value_length with
           | Some key, Some value when not state.is_view && key <> "" &&
               String.length key <= max_storage_key_bytes && String.length value <= max_storage_value_bytes ->
               let previous = String_map.find_opt key state.storage in
               let registers =
                 match previous with
                 | Some old -> String_map.add (register_key register_id) old state.registers
                 | None -> state.registers
               in
               let storage = String_map.add key value state.storage in
               let aggregate = String_map.fold
                   (fun key value total -> total + String.length key + String.length value) storage 0 in
               if String_map.cardinal storage > max_storage_rows || aggregate > max_payload_bytes then
                 host_trap state store
               else
                 let state = { state with registers; storage } in
                 let result, payloads = match previous with
                   | Some old -> (z_one, [ key; value; old ])
                   | None -> (z_zero, [ key; value ])
                 in
                 (match trace (Some result) payloads state with
                  | Some state -> host_return state store [ i64_value result ]
                  | None -> host_trap state store)
           | _ -> host_trap state store)
      | Value_return, [ length; pointer ] ->
          (match read_memory store pointer length with
           | Some payload when state.return_data = None && String.length payload <= max_event_payload_bytes ->
               let state = { state with return_data = Some payload } in
               (match trace None [ payload ] state with
                | Some state -> host_return state store []
                | None -> host_trap state store)
           | _ -> host_trap state store)
      | Attached_deposit, [ pointer ] ->
          (match write_memory store pointer state.attached_deposit with
           | None -> host_trap state store
           | Some store ->
               (match trace None [ state.attached_deposit ] state with
                | Some state -> host_return state store []
                | None -> host_trap state store))
      | Log_utf8, [ length; pointer ] ->
          (match read_memory store pointer length with
           | Some payload when List.length state.logs_rev < max_logs && String.length payload <= max_event_payload_bytes ->
               let state = { state with logs_rev = payload :: state.logs_rev } in
               (match trace None [ payload ] state with
                | Some state -> host_return state store []
                | None -> host_trap state store)
           | _ -> host_trap state store)
      | Panic_utf8, [ length; pointer ] ->
          (match read_memory store pointer length with
           | Some payload ->
               (match trace None [ payload ] state with
                | Some state -> host_trap state store
                | None -> host_trap state store)
           | None -> host_trap state store)
      | _ -> host_trap state store
end

module Interpreter = Extract.Extraction_instance (Near_host)

let initial_host_state (invocation : invocation) : host_state = {
  input = invocation.input;
  attached_deposit = invocation.attached_deposit;
  is_view = invocation.is_view;
  storage = invocation.pre_storage;
  registers = String_map.empty;
  return_data = None;
  logs_rev = [];
  trace_rev = [];
  trace_count = 0;
  trace_payload_bytes = 0;
  host_trapped = false;
}

let initial_store =
  let functions = List.map
      (fun host_function ->
        Extract.FC_func_host (host_type host_function, Obj.magic host_function))
      host_functions
  in
  { Extract.s_funcs = functions; s_tables = []; s_mems = []; s_globals = [];
    s_elems = []; s_datas = [] }

let extern_for_host host_function =
  let rec find index = function
    | [] -> fail "internal host function index failure"
    | candidate :: _ when candidate = host_function -> Extract.EV_func (z_of_int index)
    | _ :: rest -> find (index + 1) rest
  in
  find 0 host_functions

let function_type_at module_ index =
  if not (is_int_big_int index) then None
  else List.nth_opt module_.Extract.mod_types (int_of_big_int index)

let import_externs module_ =
  let seen = Hashtbl.create 16 in
  List.map
    (fun import ->
      let module_name = Interpreter.string_of_name import.Extract.imp_module in
      let import_name = Interpreter.string_of_name import.Extract.imp_name in
      if module_name <> "env" then fail "unsupported import module %s" module_name;
      if Hashtbl.mem seen import_name then fail "duplicate import env.%s" import_name;
      Hashtbl.add seen import_name ();
      let host_function =
        match List.find_opt (fun candidate -> String.equal (host_name candidate) ("env." ^ import_name)) host_functions with
        | Some value -> value
        | None -> fail "unsupported import env.%s" import_name
      in
      let actual_type = match import.Extract.imp_desc with
        | Extract.MID_func index -> function_type_at module_ index
        | _ -> None
      in
      if actual_type <> Some (host_type host_function) then
        fail "host import env.%s has the wrong function type" import_name;
      extern_for_host host_function)
    module_.Extract.mod_imports

let value_type_uses_simd = function Extract.T_vec _ -> true | _ -> false

let function_type_uses_simd (Extract.Tf (parameters, results)) =
  List.exists value_type_uses_simd parameters || List.exists value_type_uses_simd results

let block_type_uses_simd = function
  | Extract.BT_valtype (Some value_type) -> value_type_uses_simd value_type
  | _ -> false

let rec instruction_uses_simd = function
  | Extract.BI_const_vec _ | BI_vunop _ | BI_vbinop _ | BI_vternop _
  | BI_vtestop _ | BI_vshiftop _ | BI_splat_vec _ | BI_extract_vec _
  | BI_replace_vec _ | BI_load_vec _ | BI_load_vec_lane _ | BI_store_vec _
  | BI_store_vec_lane _ -> true
  | BI_select (Some value_types) -> List.exists value_type_uses_simd value_types
  | BI_block (block_type, body) | BI_loop (block_type, body) ->
      block_type_uses_simd block_type || List.exists instruction_uses_simd body
  | BI_if (block_type, yes_body, no_body) ->
      block_type_uses_simd block_type ||
      List.exists instruction_uses_simd yes_body || List.exists instruction_uses_simd no_body
  | _ -> false

let rec instruction_grows_memory = function
  | Extract.BI_memory_grow -> true
  | BI_block (_, body) | BI_loop (_, body) ->
      List.exists instruction_grows_memory body
  | BI_if (_, yes_body, no_body) ->
      List.exists instruction_grows_memory yes_body ||
      List.exists instruction_grows_memory no_body
  | _ -> false

let module_uses_simd module_ =
  List.exists function_type_uses_simd module_.Extract.mod_types ||
  List.exists (fun global -> value_type_uses_simd global.Extract.modglob_type.tg_t)
    module_.Extract.mod_globals ||
  List.exists (fun fn ->
      List.exists value_type_uses_simd fn.Extract.modfunc_locals ||
      List.exists instruction_uses_simd fn.Extract.modfunc_body) module_.Extract.mod_funcs

let validate_strict_module_shape module_ =
  (match module_.Extract.mod_mems with
   | [ memory ] when z_compare memory.Extract.lim_min z_zero > 0 &&
       z_compare memory.Extract.lim_min (z_of_int max_initial_memory_pages) <= 0 -> ()
   | [ _ ] ->
       fail "strict NEAR profile initial memory is outside the 1..%d page limit"
         max_initial_memory_pages
   | _ -> fail "strict NEAR profile requires exactly one defined memory");
  if module_.Extract.mod_tables <> [] || module_.Extract.mod_globals <> [] ||
     module_.Extract.mod_elems <> [] || module_.Extract.mod_start <> None
  then fail "tables, globals, elements, and start functions are outside the strict NEAR profile";
  if List.exists
      (fun fn -> List.exists instruction_grows_memory fn.Extract.modfunc_body)
      module_.Extract.mod_funcs
  then fail "memory.grow is outside the bounded strict NEAR profile";
  let memory_exports = List.filter_map
      (fun export -> match export.Extract.modexp_desc with
        | Extract.MED_mem address ->
            Some (Interpreter.string_of_name export.Extract.modexp_name, address)
        | _ -> None)
      module_.Extract.mod_exports in
  if memory_exports <> [ ("memory", z_zero) ] then
    fail "strict NEAR profile requires one memory export named memory at address zero"

let invoke_export store external_value =
  match external_value with
  | Extract.EV_func address when is_int_big_int address ->
      (match List.nth_opt store.Extract.s_funcs (int_of_big_int address) with
       | Some (Extract.FC_func_native (Extract.Tf ([], []), _, _)) ->
           Interpreter.invoke_extern store external_value []
       | _ -> None)
  | _ -> None

type run_terminal =
  | Run_value of Extract.store_record * Extract.frame * Extract.value0 list * host_state * int
  | Run_trap of Extract.store_record * Extract.frame * host_state * int
  | Run_exhausted of host_state * int
  | Run_error of host_state * int

let run_bounded ~fuel ~used state wasm_config =
  let rec loop used state config depth =
    if used >= fuel then Run_exhausted (state, used)
    else
      match Interpreter.run_one_step (Obj.magic state) config depth with
      | Extract.RSC_normal (next_state, next_config, next_depth) ->
          let next_state : host_state = Obj.magic next_state in
          latest_host_state := Some next_state;
          loop (used + 1) next_state next_config next_depth
      | RSC_value (store, frame, values) ->
          let state = Option.value !latest_host_state ~default:state in
          Run_value (store, frame, values, state, used + 1)
      | RSC_trap (store, frame) ->
          let state = Option.value !latest_host_state ~default:state in
          Run_trap (store, frame, state, used + 1)
      | RSC_invalid | RSC_error ->
          let state = Option.value !latest_host_state ~default:state in
          Run_error (state, used + 1)
  in
  loop used state (Interpreter.interp_cfg_of_wasm wasm_config) z_zero

let json_string value = `String value

let storage_json storage =
  `List (String_map.bindings storage |> List.map (fun (key, value) ->
      `Assoc [ ("keyHex", json_string (hex_of_string key));
               ("valueHex", json_string (hex_of_string value)) ]))

let trace_json invocation_digest events =
  let event_json index event =
    `Assoc [
      ("argumentsHex", `List (List.map (fun value -> json_string (uint64_hex value)) event.arguments));
      ("import", json_string event.import_name);
      ("index", `Int index);
      ("payloadsHex", `List (List.map (fun value -> json_string (hex_of_string value)) event.payloads));
      ("resultHex", match event.result with None -> `Null | Some value -> json_string (uint64_hex value));
    ]
  in
  Yojson.Safe.to_string (`Assoc [
    ("events", `List (List.mapi event_json events));
    ("hostProfile", json_string host_profile);
    ("invocationSha256", json_string invocation_digest);
    ("schema", json_string trace_schema);
  ])

let observation_json invocation_digest (invocation : invocation) (state : host_state)
    ~returned ~host_trap =
  let storage = if returned then state.storage else invocation.pre_storage in
  Yojson.Safe.to_string (`Assoc [
    ("hostProfile", json_string host_profile);
    ("invocationSha256", json_string invocation_digest);
    ("logsHex", `List (List.rev_map (fun value -> json_string (hex_of_string value)) state.logs_rev));
    ("postStorage", storage_json storage);
    ("promisesHex", `List []);
    ("returnDataHex", if returned then
       (match state.return_data with None -> `Null | Some value -> json_string (hex_of_string value))
     else `Null);
    ("schema", json_string observation_schema);
    ("status", json_string (if returned then "returned" else "trapped"));
    ("trapKind", if returned then `Null else json_string (if host_trap then "host" else "wasm"));
  ])

let result_json ~request_path ~result_path request ~executable_digest
    ~parser_status ~checker_status ~instantiation_status ~execution_status
    ~trace_digest ~observation_digest ~simd_used =
  Yojson.Safe.to_string (`Assoc [
    ("argv", `List (List.map json_string
      [ "check-execute"; "--request"; request_path; "--result"; result_path ]));
    ("checkerStatus", json_string checker_status);
    ("executableSha256", json_string executable_digest);
    ("executionStatus", json_string execution_status);
    ("hostProfile", json_string host_profile);
    ("hostTraceSha256", json_string trace_digest);
    ("inputWasmSha256", json_string request.input_wasm_sha256);
    ("instantiationStatus", json_string instantiation_status);
    ("invocationSha256", json_string request.invocation_sha256);
    ("observationSha256", json_string observation_digest);
    ("parserStatus", json_string parser_status);
    ("providerRevision", json_string provider_revision);
    ("schema", json_string result_schema);
    ("simdUsed", `Bool simd_used);
  ])

let trace_path result_path = result_path ^ ".host-trace.pf-jcs.json"
let observation_path result_path = result_path ^ ".observation.pf-jcs.json"

let emit_artifacts ~request_path ~result_path request (invocation : invocation)
    executable_digest (state : host_state)
    ~parser_status ~checker_status ~instantiation_status ~execution_status
    ~returned ~host_trap ~simd_used =
  let trace = trace_json request.invocation_sha256 (List.rev state.trace_rev) in
  let observation = observation_json request.invocation_sha256 invocation state ~returned ~host_trap in
  write_file (trace_path result_path) trace;
  write_file (observation_path result_path) observation;
  let result = result_json ~request_path ~result_path request ~executable_digest
      ~parser_status ~checker_status ~instantiation_status ~execution_status
      ~trace_digest:(digest_wire (sha256_string trace))
      ~observation_digest:(digest_wire (sha256_string observation)) ~simd_used in
  write_file result_path result

let check_execute request_path result_path =
  validate_project_relative_path "request path" request_path;
  validate_project_relative_path "result path" result_path;
  let request = parse_request
      (read_regular_file ~context:"request" ~max_bytes:max_request_wire_bytes request_path) in
  let output_paths = [ result_path; trace_path result_path; observation_path result_path ] in
  if List.exists (fun output ->
      output = request_path || output = request.input_wasm_path || output = request.invocation_path)
      output_paths || List.sort_uniq String.compare output_paths <> List.sort String.compare output_paths
  then fail "provider output paths must be distinct from every input and each other";
  List.iter (fun output ->
      try
        ignore (Unix.LargeFile.lstat output);
        fail "provider output path already exists: %s" output
      with Unix.Unix_error (Unix.ENOENT, _, _) -> ()) output_paths;
  let wasm = read_regular_file ~context:"input Wasm" ~max_bytes:max_wasm_bytes
      request.input_wasm_path in
  let invocation_raw = read_regular_file ~context:"invocation"
      ~max_bytes:max_artifact_wire_bytes request.invocation_path in
  if digest_wire (sha256_string wasm) <> request.input_wasm_sha256 then
    fail "input Wasm digest does not match request";
  if digest_wire (sha256_string invocation_raw) <> request.invocation_sha256 then
    fail "invocation digest does not match request";
  let invocation = parse_invocation invocation_raw in
  let executable_digest = digest_wire (sha256_file Sys.executable_name) in
  let state = initial_host_state invocation |> remember in
  match Interpreter.run_parse_module_str wasm with
  | None ->
      emit_artifacts ~request_path ~result_path request invocation executable_digest state
        ~parser_status:"rejected" ~checker_status:"rejected"
        ~instantiation_status:"rejected" ~execution_status:"provider-error"
        ~returned:false ~host_trap:true ~simd_used:false;
      fail "Wasm binary parser rejected the module"
  | Some module_ ->
      let simd_used = module_uses_simd module_ in
      (match Extract.module_type_checker module_ with
       | None, _ ->
           emit_artifacts ~request_path ~result_path request invocation executable_digest state
             ~parser_status:"parsed-unverified" ~checker_status:"rejected"
             ~instantiation_status:"rejected" ~execution_status:"provider-error"
             ~returned:false ~host_trap:true ~simd_used:false;
           fail "proved module checker rejected the module"
       | Some _, _ -> ());
      if simd_used then begin
        emit_artifacts ~request_path ~result_path request invocation executable_digest state
          ~parser_status:"parsed-unverified" ~checker_status:"accepted-proved-sound"
          ~instantiation_status:"rejected" ~execution_status:"provider-error"
          ~returned:false ~host_trap:true ~simd_used:true;
        fail "SIMD is outside the strict provider profile"
      end;
      let imports =
        try
          validate_strict_module_shape module_;
          import_externs module_
        with Invalid_argument message ->
          emit_artifacts ~request_path ~result_path request invocation executable_digest state
            ~parser_status:"parsed-unverified" ~checker_status:"accepted-proved-sound"
            ~instantiation_status:"rejected" ~execution_status:"provider-error"
            ~returned:false ~host_trap:true ~simd_used:false;
          fail "%s" message
      in
      match Interpreter.interp_instantiate_wrapper (Obj.magic state) initial_store module_ imports with
      | None, message ->
          emit_artifacts ~request_path ~result_path request invocation executable_digest state
            ~parser_status:"parsed-unverified" ~checker_status:"accepted-proved-sound"
            ~instantiation_status:"rejected" ~execution_status:"provider-error"
            ~returned:false ~host_trap:true ~simd_used:false;
          fail "proved instantiator rejected the module: %s" message
      | Some wasm_config, _ ->
          latest_host_state := Some state;
          (match run_bounded ~fuel:request.fuel ~used:0 state wasm_config with
           | Run_value (store, frame, _, state, used) ->
               let export =
                 Interpreter.get_exports frame
                 |> List.find_opt (fun (name, _) -> name = invocation.export_name)
               in
               let instructions = match export with
                 | Some (_, external_value) -> invoke_export store external_value
                 | None -> None
               in
               (match instructions with
                | None ->
                    emit_artifacts ~request_path ~result_path request invocation executable_digest state
                      ~parser_status:"parsed-unverified" ~checker_status:"accepted-proved-sound"
                      ~instantiation_status:"accepted-proved-sound" ~execution_status:"provider-error"
                      ~returned:false ~host_trap:true ~simd_used:false;
                    fail "requested export is missing or has an unsupported signature"
                | Some instructions ->
                    latest_host_state := Some state;
                    let invocation_config = (store, (frame, instructions)) in
                    (match run_bounded ~fuel:request.fuel ~used state invocation_config with
                     | Run_value (_, _, _, state, _) ->
                         emit_artifacts ~request_path ~result_path request invocation executable_digest state
                           ~parser_status:"parsed-unverified" ~checker_status:"accepted-proved-sound"
                           ~instantiation_status:"accepted-proved-sound" ~execution_status:"returned"
                           ~returned:true ~host_trap:false ~simd_used:false
                     | Run_trap (_, _, state, _) ->
                         emit_artifacts ~request_path ~result_path request invocation executable_digest state
                           ~parser_status:"parsed-unverified" ~checker_status:"accepted-proved-sound"
                           ~instantiation_status:"accepted-proved-sound" ~execution_status:"trapped"
                           ~returned:false ~host_trap:state.host_trapped ~simd_used:false
                     | Run_exhausted (state, _) ->
                         emit_artifacts ~request_path ~result_path request invocation executable_digest state
                           ~parser_status:"parsed-unverified" ~checker_status:"accepted-proved-sound"
                           ~instantiation_status:"accepted-proved-sound" ~execution_status:"exhausted"
                           ~returned:false ~host_trap:true ~simd_used:false;
                         fail "interpreter fuel exhausted"
                     | Run_error (state, _) ->
                         emit_artifacts ~request_path ~result_path request invocation executable_digest state
                           ~parser_status:"parsed-unverified" ~checker_status:"accepted-proved-sound"
                           ~instantiation_status:"accepted-proved-sound" ~execution_status:"provider-error"
                           ~returned:false ~host_trap:true ~simd_used:false;
                         fail "interpreter returned an invalid or ill-typed configuration"))
           | Run_trap (_, _, state, _) ->
               emit_artifacts ~request_path ~result_path request invocation executable_digest state
                 ~parser_status:"parsed-unverified" ~checker_status:"accepted-proved-sound"
                 ~instantiation_status:"rejected" ~execution_status:"provider-error"
                 ~returned:false ~host_trap:state.host_trapped ~simd_used:false;
               fail "module instantiation trapped"
           | Run_exhausted (state, _) ->
               emit_artifacts ~request_path ~result_path request invocation executable_digest state
                 ~parser_status:"parsed-unverified" ~checker_status:"accepted-proved-sound"
                 ~instantiation_status:"rejected" ~execution_status:"exhausted"
                 ~returned:false ~host_trap:true ~simd_used:false;
               fail "module instantiation exhausted fuel"
           | Run_error (state, _) ->
               emit_artifacts ~request_path ~result_path request invocation executable_digest state
                 ~parser_status:"parsed-unverified" ~checker_status:"accepted-proved-sound"
                 ~instantiation_status:"rejected" ~execution_status:"provider-error"
                 ~returned:false ~host_trap:true ~simd_used:false;
               fail "module instantiation returned an invalid configuration")

let usage () =
  Printf.eprintf "usage: %s [--version | check-execute --request PATH --result PATH]\n" Sys.argv.(0);
  64

let main () =
  match Array.to_list Sys.argv with
  | [ _; "--version" ] ->
      print_endline ("proof-forge-wasmcert-provider-v1 1.0.0 " ^ provider_revision);
      0
  | [ _; "check-execute"; "--request"; request_path; "--result"; result_path ] ->
      (try check_execute request_path result_path; 0
       with
       | Invalid_argument message -> Printf.eprintf "proof-forge-wasmcert-provider-v1: %s\n" message; 2
       | Sys_error message -> Printf.eprintf "proof-forge-wasmcert-provider-v1: %s\n" message; 2
       | Unix.Unix_error (error, operation, _) ->
           Printf.eprintf "proof-forge-wasmcert-provider-v1: %s: %s\n"
             operation (Unix.error_message error);
           2)
  | _ -> usage ()

let () = exit (main ())
