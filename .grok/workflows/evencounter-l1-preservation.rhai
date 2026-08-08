let meta = #{
    name: "evencounter-l1-preservation",
    description: "EvenCounter L1 preservation ladder: verify foundation, instance, and product gates",
    phases: [
        #{ title: "Build-Foundation", detail: "InvariantFoundation + ReferenceMachine micro-paths" },
        #{ title: "Build-Instance", detail: "EvenCounterPreservation packaging" },
        #{ title: "Product-Gate", detail: "inline certifier / product positive when wired" },
    ],
    when_to_use: "Use while advancing ADR-0034 EvenCounter preserving. Pass args.phase = foundation | instance | product | all.",
};

let phase_arg = if args == () { "all" } else if args.phase == () { "all" } else { args.phase };

let gate_schema = #{
    "type": "object",
    "required": ["ok", "summary", "commands"],
    "properties": #{
        "ok": #{ "type": "boolean" },
        "summary": #{ "type": "string" },
        "commands": #{ "type": "array", "maxItems": 8, "items": #{ "type": "string" } },
        "blockers": #{ "type": "array", "maxItems": 8, "items": #{ "type": "string" } },
    },
};

if phase_arg == "foundation" || phase_arg == "all" {
    phase("Build-Foundation");
    let prompt = "Verify ProofForge EvenCounter L1 foundation in repo root. Run ONLY: lake build ProofForgeV2.Semantic.InvariantFoundationV1 then lake build ProofForgeV2.Semantic.ReferenceV1. Single job; do not thrash. Return ok=true only if both exit 0. List exact commands in commands[]; residual blockers in blockers[] (empty if green).";
    let r = agent(prompt, #{
        label: "build-foundation",
        agent_type: "general-purpose",
        capability_mode: "execute",
        output_schema: gate_schema,
    });
    if r == () || r.success == false || r.output.ok != true {
        complete(#{ phase: "Build-Foundation", ok: false, summary: "foundation build gate failed", detail: r });
    }
    log("foundation gate green");
}

if phase_arg == "instance" || phase_arg == "all" {
    phase("Build-Instance");
    let prompt = "Verify EvenCounterPreservation packaging. Run ONLY: lake build ProofForgeV2.ProofInstances.EvenCounterPreservationV1. Return ok=true only if exit 0. List commands in commands[]; blockers in blockers[].";
    let r = agent(prompt, #{
        label: "build-instance",
        agent_type: "general-purpose",
        capability_mode: "execute",
        output_schema: gate_schema,
    });
    if r == () || r.success == false || r.output.ok != true {
        complete(#{ phase: "Build-Instance", ok: false, summary: "instance build gate failed", detail: r });
    }
    log("instance gate green");
}

if phase_arg == "product" || phase_arg == "all" {
    phase("Product-Gate");
    let prompt = "Check EvenCounter product preserving status. Run lake build Tests.Compiler.InlineProofCertifierV1 if present, or report honestly that product GREEN is still RED until PreservationTheoremV1 ordinal 0 is certified. Return ok=true only for real product GREEN; otherwise ok=false with blockers describing remaining work.";
    let r = agent(prompt, #{
        label: "product-gate",
        agent_type: "general-purpose",
        capability_mode: "execute",
        output_schema: gate_schema,
    });
    if r == () || r.success == false {
        complete(#{ phase: "Product-Gate", ok: false, summary: "product gate runner failed", detail: r });
    }
    log("product gate finished");
    complete(#{
        ok: r.output.ok,
        summary: r.output.summary,
        phase: phase_arg,
        product: r.output,
    });
}

complete(#{
    ok: true,
    summary: "EvenCounter L1 verification workflow completed for phase " + phase_arg,
    phase: phase_arg,
});
