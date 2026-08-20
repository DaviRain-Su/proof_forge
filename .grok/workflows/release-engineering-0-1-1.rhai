let meta = #{
    name: "release-engineering-0-1-1",
    description: "RETIRED. VERSION is already 0.1.1. Do not bump/tag from this workflow.",
    when_to_use: "Never. A future version bump needs a new explicit owner request.",
    phases: [#{ title: "Retired", detail: "Refuse and exit" }],
};

phase("Retired");
let report = "# release-engineering-0-1-1 — RETIRED\n\n`VERSION` is 0.1.1. This workflow must not push or retag.\nA later bump is a new owner request, not a relaunch.\n";
let path = write_scratch_file("report.md", report);
complete(#{ status: "retired", report_path: path, program_complete: true });
