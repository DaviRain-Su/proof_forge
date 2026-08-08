let meta = #{
    name: "product-surface-ladder",
    description: "Product surface ladder: doctor/install CLI, local/network cmds, MCP/SDK thin wrappers — sequential shared worktree, optional commit",
    when_to_use: "When building user-facing install/doctor and Agent-ready CLI/MCP on top of Tool Lock + multi-target runtimes. Authority: docs/product/01-toolchain-install-surface.md.",
    phases: [
        #{ title: "Preflight", detail: "repo baseline + Tool Lock inventory" },
        #{ title: "DOC", detail: "product ladder doc + index pointer" },
        #{ title: "I0-DOCTOR", detail: "proof-forge doctor JSON + human" },
        #{ title: "I1-INSTALL", detail: "non-interactive install --targets via toolchain_assets" },
        #{ title: "I1b-CLI-WIRE", detail: "CLI subcommands wired into Exe" },
        #{ title: "I2-LOCAL-CMDS", detail: "local/network wrappers over existing scripts" },
        #{ title: "I3-ALEO-RUNTIME", detail: "Aleo snarkos test_network install honesty" },
        #{ title: "MCP-V0", detail: "minimal MCP server over CLI JSON" },
        #{ title: "SDK-V0", detail: "optional thin SDK (one language)" },
        #{ title: "Close", detail: "docs honesty + remaining backlog" },
    ],
};

let preflight_schema = #{
    "type": "object",
    "required": ["ready", "reason", "head", "tool_lock", "cli_entry", "blockers"],
    "properties": #{
        "ready": #{ "type": "boolean" },
        "reason": #{ "type": "string" },
        "head": #{ "type": "string" },
        "tool_lock": #{ "type": "string" },
        "cli_entry": #{ "type": "string" },
        "blockers": #{ "type": "array", "maxItems": 16, "items": #{ "type": "string" } },
    },
};

let phase_schema = #{
    "type": "object",
    "required": ["implemented", "summary", "head", "files_changed", "tests_run", "blockers", "commit", "worktree_clean_after"],
    "properties": #{
        "implemented": #{ "type": "boolean" },
        "summary": #{ "type": "string" },
        "head": #{ "type": "string" },
        "files_changed": #{ "type": "array", "maxItems": 80, "items": #{ "type": "string" } },
        "tests_run": #{ "type": "array", "maxItems": 40, "items": #{ "type": "string" } },
        "blockers": #{ "type": "array", "maxItems": 16, "items": #{ "type": "string" } },
        "commit": #{ "type": "string" },
        "worktree_clean_after": #{ "type": "boolean" },
    },
};

let close_schema = #{
    "type": "object",
    "required": ["passed", "summary", "head", "phases_done", "remaining", "commands"],
    "properties": #{
        "passed": #{ "type": "boolean" },
        "summary": #{ "type": "string" },
        "head": #{ "type": "string" },
        "phases_done": #{ "type": "array", "maxItems": 16, "items": #{ "type": "string" } },
        "remaining": #{ "type": "array", "maxItems": 32, "items": #{ "type": "string" } },
        "commands": #{ "type": "array", "maxItems": 30, "items": #{
            "type": "object", "required": ["command", "result"],
            "properties": #{
                "command": #{ "type": "string" },
                "result": #{ "type": "string" },
            },
        }},
    },
};

// Args: start_from, stop_after, skip_commit, include_sdk (bool)
let stop_after = if args == () || args.stop_after == () { "I1b-CLI-WIRE" } else { args.stop_after };
let start_from = if args == () || args.start_from == () { "DOC" } else { args.start_from };
let skip_commit = if args == () || args.skip_commit == () { false } else { args.skip_commit };
let include_sdk = if args == () || args.include_sdk == () { false } else { args.include_sdk };

fn phase_rank(name) {
    if name == "DOC" { 0 }
    else if name == "I0-DOCTOR" { 1 }
    else if name == "I1-INSTALL" { 2 }
    else if name == "I1b-CLI-WIRE" { 3 }
    else if name == "I2-LOCAL-CMDS" { 4 }
    else if name == "I3-ALEO-RUNTIME" { 5 }
    else if name == "MCP-V0" { 6 }
    else if name == "SDK-V0" { 7 }
    else if name == "Close" { 8 }
    else { 0 }
}
let start_rank = phase_rank(start_from);
let stop_rank = phase_rank(stop_after);

let common = "";
common += "ProofForge PRODUCT SURFACE ladder (install/doctor/CLI/MCP). Shared worktree. ";
common += "Authority: docs/product/01-toolchain-install-surface.md. ";
common += "Reuse scripts/toolchain_assets.py + toolchains*.lock.json + PROOF_FORGE_TOOL_ROOT. ";
common += "NEVER invent PATH fallback tools; NEVER set deployable=true without product N3 decision. ";
common += "NEVER push. AGENTS.md maturity honesty. Prefer thin CLI wrappers over reimplementing compilers. ";
common += "Target menu = TargetRegistryV1 implemented only; design-only targets are unsupported not installable. ";
common += "Aleo snarkos needs features=test_network (prebuilt GitHub zip usually lacks it). ";
common += "When implemented=true, residual notes go in blockers only if soft; hard blockers => implemented=false. ";
if skip_commit {
    common += "skip_commit=true: implement and test but DO NOT git commit. ";
} else {
    common += "After each phase: git add specific files + commit with complete sentences; never git push. ";
}

fn run_slice(label, title, body, schema, common_txt, cap) {
    let p = common_txt;
    p += "PHASE " + label + ". " + body + " ";
    p += "Return structured fields. Run real commands for tests_run. List files_changed paths. ";
    p += "If work is already done, implemented=true with evidence; do not redo from scratch. ";
    agent(p, #{
        label: label,
        phase: title,
        capability_mode: cap,
        output_schema: schema,
    })
}

fn hard_fail(r) {
    if r == () || !r.success { true }
    else if r.output.implemented == false { true }
    else { false }
}

// Soft residual: implemented=true may still list blockers for deferred notes.
fn soft_ok(r) {
    r != () && r.success && r.output.implemented == true
}

phase("Preflight");
let pre_prompt = common;
pre_prompt += "READ/EXECUTE. git log -3 --oneline; git status --short; ";
pre_prompt += "locate scripts/toolchain_assets.py, toolchains-linux-x86_64.lock.json, ProofForgeV2/CLI/Exe.lean entry; ";
pre_prompt += "summarize existing just toolchains-* recipes. ready=true if worktree usable for product CLI work. ";
pre_prompt += "tool_lock=path or summary; cli_entry=module path for proof-forge-next.";
let pre = agent(pre_prompt, #{
    label: "preflight",
    phase: "Preflight",
    capability_mode: "execute",
    output_schema: preflight_schema,
});
if pre == () || !pre.success || pre.output.ready != true {
    let why = "preflight failed";
    if pre != () && pre.success && pre.output.reason != () { why = pre.output.reason; }
    pause("verification", "Preflight not ready: " + why);
}

let done = [];

// --- DOC ---
if start_rank <= 0 && stop_rank >= 0 {
    phase("DOC");
    let body = "";
    body += "Ensure docs/product/01-toolchain-install-surface.md exists and is accurate for I0-I3/MCP/SDK ladder. ";
    body += "Add pointer in docs/index.md if missing. Run just docs-check. ";
    body += "Do not implement CLI code in this phase.";
    let r = run_slice("DOC", "DOC", body, phase_schema, common, "all");
    if hard_fail(r) {
        let b = "DOC failed";
        if r != () && r.success && r.output.summary != () { b = r.output.summary; }
        pause("verification", "DOC blocked: " + b);
    }
    done.push("DOC");
    log("DOC done");
}

// --- I0-DOCTOR ---
if start_rank <= 1 && stop_rank >= 1 {
    phase("I0-DOCTOR");
    let body = "";
    body += "Implement product doctor surface: inspect PROOF_FORGE_TOOL_ROOT (default cache path by platform). ";
    body += "For each TargetRegistry implemented target, report tool presence vs Tool Lock members used by that target. ";
    body += "Human CODE: message style + --json schema proof-forge.doctor.v1 as in product doc. ";
    body += "Wire as CLI subcommand if feasible this phase, or library+smoke script called by CLI stub. ";
    body += "Missing root => clear diagnostic not crash. Run docs-check + focused smoke.";
    let r = run_slice("I0-DOCTOR", "I0-DOCTOR", body, phase_schema, common, "all");
    if hard_fail(r) {
        let b = "I0-DOCTOR failed";
        if r != () && r.success && r.output.summary != () { b = r.output.summary; }
        pause("verification", "I0-DOCTOR blocked: " + b);
    }
    done.push("I0-DOCTOR");
    log("I0-DOCTOR done");
}

// --- I1-INSTALL ---
if start_rank <= 2 && stop_rank >= 2 {
    phase("I1-INSTALL");
    let body = "";
    body += "Implement non-interactive install: --targets list or --all-core, require --yes. ";
    body += "Delegate download/materialize to scripts/toolchain_assets.py (provision/materialize-external patterns). ";
    body += "Map targets to lock assets (evm->solc, solana->sbpf, aleo->leo, noir->nargo, …). ";
    body += "Idempotent when digests match. No PATH fallback. Optional --with-runtime flag may only document or partially install host-heavy tools. ";
    body += "Smoke: install one small target already partially present or dry-run mode if network blocked — honesty in blockers.";
    let r = run_slice("I1-INSTALL", "I1-INSTALL", body, phase_schema, common, "all");
    if hard_fail(r) {
        let b = "I1-INSTALL failed";
        if r != () && r.success && r.output.summary != () { b = r.output.summary; }
        pause("verification", "I1-INSTALL blocked: " + b);
    }
    done.push("I1-INSTALL");
    log("I1-INSTALL done");
}

// --- I1b-CLI-WIRE ---
if start_rank <= 3 && stop_rank >= 3 {
    phase("I1b-CLI-WIRE");
    let body = "";
    body += "Wire doctor + install into product CLI Exe (ProofForgeV2/CLI/*). ";
    body += "Usage help lists subcommands. Exit codes stable. --json where applicable. ";
    body += "Do not break existing build/check/inspect. Run lake build proof_forge_next + focused CLI tests or smoke.";
    let r = run_slice("I1b-CLI-WIRE", "I1b-CLI-WIRE", body, phase_schema, common, "all");
    if hard_fail(r) {
        let b = "I1b-CLI-WIRE failed";
        if r != () && r.success && r.output.summary != () { b = r.output.summary; }
        pause("verification", "I1b-CLI-WIRE blocked: " + b);
    }
    done.push("I1b-CLI-WIRE");
    log("I1b-CLI-WIRE done");
}

// --- I2-LOCAL-CMDS ---
if start_rank <= 4 && stop_rank >= 4 {
    phase("I2-LOCAL-CMDS");
    let body = "";
    body += "Add CLI local/network (or check-local) that wrap existing scripts without renaming product semantics: ";
    body += "aleo_local_sandbox.sh, aleo_devnet.sh, aleo_network.sh, and document solana-runtime/evm paths. ";
    body += "network MUST require explicit broadcast flag. Prefer spawning scripts with locked tool root env. ";
    body += "Smoke missing-tool path exit 2.";
    let r = run_slice("I2-LOCAL-CMDS", "I2-LOCAL-CMDS", body, phase_schema, common, "all");
    if hard_fail(r) {
        let b = "I2-LOCAL-CMDS failed";
        if r != () && r.success && r.output.summary != () { b = r.output.summary; }
        pause("verification", "I2-LOCAL-CMDS blocked: " + b);
    }
    done.push("I2-LOCAL-CMDS");
    log("I2-LOCAL-CMDS done");
}

// --- I3-ALEO-RUNTIME ---
if start_rank <= 5 && stop_rank >= 5 {
    phase("I3-ALEO-RUNTIME");
    let body = "";
    body += "Aleo runtime install honesty: doctor detects snarkos with test_network feature; ";
    body += "document or semi-auto install path to ~/.cache/proof-forge-v2/aleo-devnet/cargo-install/bin/snarkos; ";
    body += "wire PROOF_FORGE_ALEO_SNARKOS. Do not claim prebuilt GitHub snarkos works for leo devnet. ";
    body += "Optional: install --targets aleo --with-runtime prints exact cargo command if build too heavy for CI.";
    let r = run_slice("I3-ALEO-RUNTIME", "I3-ALEO-RUNTIME", body, phase_schema, common, "all");
    if hard_fail(r) {
        let b = "I3-ALEO-RUNTIME failed";
        if r != () && r.success && r.output.summary != () { b = r.output.summary; }
        pause("verification", "I3-ALEO-RUNTIME blocked: " + b);
    }
    done.push("I3-ALEO-RUNTIME");
    log("I3-ALEO-RUNTIME done");
}

// --- MCP-V0 ---
if start_rank <= 6 && stop_rank >= 6 {
    phase("MCP-V0");
    let body = "";
    body += "Minimal MCP server (stdio) exposing pf_doctor, pf_install, pf_build, pf_list_targets, pf_artifacts. ";
    body += "Each tool shells to product CLI or reuses same Lean/Python helpers; return JSON text. ";
    body += "No default network broadcast tool without explicit boolean. README snippet for Agent wiring. ";
    body += "Keep package small; may live under tools/mcp/ or scripts/mcp/.";
    let r = run_slice("MCP-V0", "MCP-V0", body, phase_schema, common, "all");
    if hard_fail(r) {
        let b = "MCP-V0 failed";
        if r != () && r.success && r.output.summary != () { b = r.output.summary; }
        pause("verification", "MCP-V0 blocked: " + b);
    }
    done.push("MCP-V0");
    log("MCP-V0 done");
}

// --- SDK-V0 (optional) ---
if include_sdk && start_rank <= 7 && stop_rank >= 7 {
    phase("SDK-V0");
    let body = "";
    body += "Thin SDK in ONE language (TypeScript or Python): spawn proof-forge-next, parse doctor/build manifest JSON. ";
    body += "Not a second compiler. Package name proof-forge-sdk or similar under sdk/. Minimal tests.";
    let r = run_slice("SDK-V0", "SDK-V0", body, phase_schema, common, "all");
    if hard_fail(r) {
        let b = "SDK-V0 failed";
        if r != () && r.success && r.output.summary != () { b = r.output.summary; }
        pause("verification", "SDK-V0 blocked: " + b);
    }
    done.push("SDK-V0");
    log("SDK-V0 done");
}

// --- Close ---
if stop_rank >= 8 || stop_after == "Close" {
    phase("Close");
    let body = "";
    body += "Update docs/product/01 and docs/index honesty. Summarize phases_done=" + json_encode(done) + ". ";
    body += "List remaining work (interactive install UI, full multi-chain runtime packs, deployable=true profile). ";
    body += "Run just docs-check. Do not claim formal/hermetic.";
    let close_p = common + body;
    let cr = agent(close_p, #{
        label: "Close",
        phase: "Close",
        capability_mode: "all",
        output_schema: close_schema,
    });
    if cr == () || !cr.success || cr.output.passed != true {
        let b = "Close failed";
        if cr != () && cr.success && cr.output.summary != () { b = cr.output.summary; }
        pause("verification", "Close blocked: " + b);
    }
    done.push("Close");
}

let report = "# product-surface-ladder\n\n";
report += "start_from=" + start_from + " stop_after=" + stop_after + "\n";
report += "include_sdk=" + include_sdk.to_string() + " skip_commit=" + skip_commit.to_string() + "\n";
report += "phases_done=" + json_encode(done) + "\n";
report += "authority=docs/product/01-toolchain-install-surface.md\n";
let path = write_scratch_file("product-surface-ladder-result.md", report);
complete(#{
    summary: "product-surface-ladder finished phases: " + json_encode(done),
    phases_done: done,
    start_from: start_from,
    stop_after: stop_after,
    report_path: path,
});
