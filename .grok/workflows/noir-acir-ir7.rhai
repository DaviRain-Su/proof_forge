let meta = #{
    name: "noir-acir-ir7",
    description: "RETIRED. Noir ACIR IR-7 prove honesty (PARTIAL/MISSING) is done. Do not launch.",
    when_to_use: "Never. Do not invent a barretenberg/CRS pin from this workflow.",
    phases: [#{ title: "Retired", detail: "Refuse and exit" }],
};

phase("Retired");
let report = "# noir-acir-ir7 — RETIRED\n\nIR-7 honesty pin exists (`just noir-runtime` → PF-TOOLCHAIN-MISSING).\nOpening prove/verify requires COMP-0-NOIR-PROVE / a PRD revision.\n";
let path = write_scratch_file("report.md", report);
complete(#{ status: "retired", report_path: path, program_complete: true });
