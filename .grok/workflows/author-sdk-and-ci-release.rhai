let meta = #{
    name: "author-sdk-and-ci-release",
    description: "RETIRED. REL-AUTHOR-0 / REL-CI-0 already landed. Do not launch.",
    when_to_use: "Never.",
    phases: [#{ title: "Retired", detail: "Refuse and exit" }],
};

phase("Retired");
let report = "# author-sdk-and-ci-release — RETIRED\n\nAuthor SDK package + tag release workflow is in tree.\n";
let path = write_scratch_file("report.md", report);
complete(#{ status: "retired", report_path: path, program_complete: true });
