program accumulator.aleo;

mapping pf_state_0:
    key as u8.public;
    value as u64.public;

mapping initialized:
    key as u8.public;
    value as boolean.public;

function initialize:
    input r0 as u64.public;
    async initialize r0 into r1;
    output r1 as accumulator.aleo/initialize.future;

finalize initialize:
    input r0 as u64.public;
    get.or_use initialized[0u8] false into r1;
    not r1 into r2;
    assert.eq r2 true;
    set r0 into pf_state_0[0u8];
    set true into initialized[0u8];

function credit:
    input r0 as u64.public;
    async credit r0 into r1;
    output r1 as accumulator.aleo/credit.future;

finalize credit:
    input r0 as u64.public;
    get.or_use pf_state_0[0u8] 0u64 into r1;
    add r1 r0 into r2;
    set r2 into pf_state_0[0u8];
    get.or_use pf_state_0[0u8] 0u64 into r3;

constructor:
    assert.eq edition 0u16;
