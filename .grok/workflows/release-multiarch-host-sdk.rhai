let meta = #{
    name: "release-multiarch-host-sdk",
    description: "RETIRED. Multi-arch engineering-dist matrix already landed. Do not launch.",
    when_to_use: "Never.",
    phases: [#{ title: "Retired", detail: "Refuse and exit" }],
};

phase("Retired");
let report = "# release-multiarch-host-sdk — RETIRED\n\nlinux + darwin-arm64 package jobs are in CI. Do not rerun as pending.\n";
let path = write_scratch_file("report.md", report);
complete(#{ status: "retired", report_path: path, program_complete: true });
