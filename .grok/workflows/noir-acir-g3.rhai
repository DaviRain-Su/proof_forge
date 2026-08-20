let meta = #{
    name: "noir-acir-g3",
    description: "RETIRED. Noir ACIR G3 / IR-3 / IR-5 / IR-6 pins are done. Do not launch.",
    when_to_use: "Never.",
    phases: [#{ title: "Retired", detail: "Refuse and exit" }],
};

phase("Retired");
let report = "# noir-acir-g3 — RETIRED\n\nIR-3/IR-5/IR-6 done. Lane idle.\n";
let path = write_scratch_file("report.md", report);
complete(#{ status: "retired", report_path: path, program_complete: true });
