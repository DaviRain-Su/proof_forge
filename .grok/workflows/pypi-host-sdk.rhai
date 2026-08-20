let meta = #{
    name: "pypi-host-sdk",
    description: "RETIRED. REL-HOST-1 PyPI wiring already landed. Do not launch.",
    when_to_use: "Never. Trusted Publisher one-time human setup is not this workflow.",
    phases: [#{ title: "Retired", detail: "Refuse and exit" }],
};

phase("Retired");
let report = "# pypi-host-sdk — RETIRED\n\nOIDC publish job is wired. Remaining Trusted Publisher setup is human, not a drain.\n";
let path = write_scratch_file("report.md", report);
complete(#{ status: "retired", report_path: path, program_complete: true });
