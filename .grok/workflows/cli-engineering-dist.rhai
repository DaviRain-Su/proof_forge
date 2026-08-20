let meta = #{
    name: "cli-engineering-dist",
    description: "RETIRED. REL-CLI-0/1 engineering CLI tarball already landed. Do not launch.",
    when_to_use: "Never. Authority: docs/product/05-distribution-and-packages.md.",
    phases: [#{ title: "Retired", detail: "Refuse and exit" }],
};

phase("Retired");
let report = "# cli-engineering-dist — RETIRED\n\nREL-CLI-0/1 is in tree. Do not rerun as a pending slice.\n";
let path = write_scratch_file("report.md", report);
complete(#{ status: "retired", report_path: path, program_complete: true });
