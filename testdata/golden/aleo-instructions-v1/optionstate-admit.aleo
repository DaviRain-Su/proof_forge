program optionstate.aleo;

mapping pf_state_0:
    key as u8.public;
    value as u64.public;

mapping pf_state_1:
    key as u8.public;
    value as u64.public;

mapping initialized:
    key as u8.public;
    value as boolean.public;

function initialize:
    async initialize into r0;
    output r0 as optionstate.aleo/initialize.future;

finalize initialize:
    get.or_use initialized[0u8] false into r0;
    not r0 into r1;
    assert.eq r1 true;
    set 0u64 into pf_state_0[0u8];
    set 0u64 into pf_state_1[0u8];
    set true into initialized[0u8];

function setSome:
    input r0 as u64.public;
    async setSome r0 into r1;
    output r1 as optionstate.aleo/setSome.future;

finalize setSome:
    input r0 as u64.public;
    set 1u64 into pf_state_0[0u8];
    set r0 into pf_state_1[0u8];

function clear:
    async clear into r0;
    output r0 as optionstate.aleo/clear.future;

finalize clear:
    set 0u64 into pf_state_0[0u8];
    set 0u64 into pf_state_1[0u8];

constructor:
    assert.eq edition 0u16;
