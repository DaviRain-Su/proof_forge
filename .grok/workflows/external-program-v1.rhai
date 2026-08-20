let meta = #{
    name: "external-program-v1",
    description: "RETIRED. External ProgramV1 template + --root path already landed. Do not launch.",
    when_to_use: "Never. Authority: docs/product/02-external-program-v1.md.",
    phases: [#{ title: "Retired", detail: "Refuse and exit" }],
};

phase("Retired");
let report = "# external-program-v1 — RETIRED\n\nTemplate / --root / SDK-MCP path is in tree.\nSee `docs/product/02-external-program-v1.md`.\n";
let path = write_scratch_file("report.md", report);
complete(#{ status: "retired", report_path: path, program_complete: true });
