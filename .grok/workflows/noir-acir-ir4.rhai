let meta = #{
    name: "noir-acir-ir4",
    description: "RETIRED. Noir ACIR IR-4 multi-fixture inventory is done. Do not launch.",
    when_to_use: "Never.",
    phases: [#{ title: "Retired", detail: "Refuse and exit" }],
};

phase("Retired");
let report = "# noir-acir-ir4 — RETIRED\n\nIR-4 done. See `testdata/golden/noir-acir-v1/`.\n";
let path = write_scratch_file("report.md", report);
complete(#{ status: "retired", report_path: path, program_complete: true });
