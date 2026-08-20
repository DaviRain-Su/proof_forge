let meta = #{
    name: "next-wave-runner",
    description: "RETIRED. Goal-auto drain is empty (LH-1…28 + Track F + SYS-S4). Do not launch.",
    when_to_use: "Never. Live pointer: .grok/README.md. New bounded slice: proof-forge-engineering-slice.",
    phases: [
        #{ title: "Retired", detail: "Refuse and exit; do not select or implement" },
    ],
};

phase("Retired");
let report = "# next-wave-runner — RETIRED\n\n";
report += "The Goal-auto drain is empty. This workflow used to pick LH-4 and would redo finished work or walk into forbidden C-3.\n\n";
report += "Live pointer: `.grok/README.md`\n";
report += "Daily engineering: `docs/plan/completeness-phased-roadmap.md` + `docs/engineering-backlog.md` §12\n";
report += "Owner waves: `docs/plan/remaining-owner-waves.md`\n";
report += "New bounded slice: `/workflow proof-forge-engineering-slice`\n";
let path = write_scratch_file("report.md", report);
complete(#{ status: "retired", report_path: path, program_complete: true });
