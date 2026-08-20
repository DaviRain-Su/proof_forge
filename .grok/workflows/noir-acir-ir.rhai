let meta = #{
    name: "noir-acir-ir",
    description: "RETIRED. Noir ACIR IR-0…IR-7 is idle. Do not launch.",
    when_to_use: "Never. Residual is prove backend (C-4 / COMP-0-NOIR-PROVE), not this lane.",
    phases: [#{ title: "Retired", detail: "Refuse and exit" }],
};

phase("Retired");
let report = "# noir-acir-ir — RETIRED\n\nIR-0…IR-7 done. Lane idle. See `docs/targets/07-noir-acir-lowering.md`.\nProve/verify is a product decision, not this workflow.\n";
let path = write_scratch_file("report.md", report);
complete(#{ status: "retired", report_path: path, program_complete: true });
