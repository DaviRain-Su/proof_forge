let meta = #{
    name: "product-surface-ladder",
    description: "RETIRED. I0–I3 + MCP-V0 + SDK-V0 already landed. Do not relaunch the ladder.",
    when_to_use: "Never. Authority is docs/product/01-toolchain-install-surface.md.",
    phases: [#{ title: "Retired", detail: "Refuse and exit" }],
};

phase("Retired");
let report = "# product-surface-ladder — RETIRED\n\nI0 doctor / I1 install / I2 local / MCP-V0 / SDK-V0 are in tree.\nDo not rerun the ladder as if those phases were pending.\nAuthority: `docs/product/01-toolchain-install-surface.md`.\n";
let path = write_scratch_file("report.md", report);
complete(#{ status: "retired", report_path: path, program_complete: true });
