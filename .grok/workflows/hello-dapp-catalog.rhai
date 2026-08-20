let meta = #{
    name: "hello-dapp-catalog",
    description: "RETIRED. Hello dApp playbook + chain catalog already landed. Do not launch.",
    when_to_use: "Never. Authority: docs/product/03-hello-dapp-agent-playbook.md + 04-chain-client-catalog.md.",
    phases: [#{ title: "Retired", detail: "Refuse and exit" }],
};

phase("Retired");
let report = "# hello-dapp-catalog — RETIRED\n\nPlaybook and catalog are in tree.\n";
let path = write_scratch_file("report.md", report);
complete(#{ status: "retired", report_path: path, program_complete: true });
