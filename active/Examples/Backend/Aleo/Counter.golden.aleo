program counter.aleo;

mapping count:
    key as u64.public;
    value as u64.public;

function initialize:
    async initialize into r0;
    output r0 as counter.aleo/initialize.future;

finalize initialize:
    set 0u64 into count[0u64];

function increment:
    async increment into r0;
    output r0 as counter.aleo/increment.future;

finalize increment:
    get.or_use count[0u64] 0u64 into r0;
    add r0 1u64 into r1;
    set r1 into count[0u64];

function get:
    async get into r0;
    output r0 as counter.aleo/get.future;

finalize get:
    get.or_use count[0u64] 0u64 into r0;

constructor:
    assert.eq edition 0u16;
