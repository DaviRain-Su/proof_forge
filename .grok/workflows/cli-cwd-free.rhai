let meta = #{
    name: "cli-cwd-free",
    description: "RETIRED. REL-CWD-0 package-root resolution already landed. Do not launch.",
    when_to_use: "Never.",
    phases: [#{ title: "Retired", detail: "Refuse and exit" }],
};

phase("Retired");
let report = "# cli-cwd-free — RETIRED\n\nPackageRootV1 / foreign-CWD doctor is in tree.\n";
let path = write_scratch_file("report.md", report);
complete(#{ status: "retired", report_path: path, program_complete: true });
