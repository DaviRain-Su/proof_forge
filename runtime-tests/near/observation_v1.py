#!/usr/bin/env python3
"""Strict NEAR view-observation adapter for engineering differential tests.

The field shape mirrors ``Targets.Near.CallObservationV1`` so a real sandbox
view can be checked against the corresponding passive relation-side fields.
It is deliberately not a NEAR evaluator, Wasm semantics, or formal refinement
checker: the JSON-RPC response and storage snapshots remain external evidence.
"""

from __future__ import annotations

import sys
from dataclasses import dataclass, replace
from typing import Any, Callable, Mapping


class ObservationError(ValueError):
    """The external response cannot satisfy the admitted observation shape."""


@dataclass(frozen=True)
class CallObservationV1:
    """Finite engineering counterpart of the passive Lean observation carrier."""

    export_name: str
    input: bytes
    return_data: bytes | None
    failure_observed: bool
    logs: tuple[bytes, ...]
    promises: tuple[bytes, ...]
    pre_storage: Mapping[bytes, bytes]
    post_storage: Mapping[bytes, bytes]


def _storage_copy(
    storage: Mapping[bytes, bytes], where: str
) -> dict[bytes, bytes]:
    if not isinstance(storage, Mapping):
        raise ObservationError(f"{where} must be a key/value mapping")
    copied: dict[bytes, bytes] = {}
    for key, value in storage.items():
        if type(key) is not bytes or type(value) is not bytes:
            raise ObservationError(f"{where} rows must be bytes-to-bytes")
        copied[key] = value
    return copied


def call_observation_from_view_response_v1(
    export_name: str,
    input_bytes: bytes,
    response: Any,
    pre_storage: Mapping[bytes, bytes],
    post_storage: Mapping[bytes, bytes],
) -> CallObservationV1:
    """Map one successful NEAR ``call_function`` response without guessing.

    A view query has no transaction receipt graph. Receipt-shaped fields are
    rejected rather than silently discarded, and promises are consequently
    the exact empty sequence at this query boundary.
    """
    if type(export_name) is not str or not export_name:
        raise ObservationError("exportName must be a nonempty string")
    if type(input_bytes) is not bytes:
        raise ObservationError("input must be bytes")
    if type(response) is not dict:
        raise ObservationError("view response must be an object")
    if "error" in response:
        raise ObservationError("view response reports failure")
    for field in (
        "receipts",
        "receipt_ids",
        "receipts_outcome",
        "transaction_outcome",
    ):
        if field in response:
            raise ObservationError(
                f"view response unexpectedly contains receipt field {field}"
            )

    result = response.get("result")
    if type(result) is not list:
        raise ObservationError("view response result must be a byte array")
    for index, value in enumerate(result):
        if type(value) is not int or not 0 <= value <= 255:
            raise ObservationError(
                f"view response result[{index}] must be an integer byte"
            )

    raw_logs = response.get("logs")
    if type(raw_logs) is not list:
        raise ObservationError("view response logs must be an array")
    logs: list[bytes] = []
    for index, value in enumerate(raw_logs):
        if type(value) is not str:
            raise ObservationError(f"view response logs[{index}] must be a string")
        try:
            logs.append(value.encode("utf-8"))
        except UnicodeEncodeError as error:
            raise ObservationError(
                f"view response logs[{index}] must be valid UTF-8 text"
            ) from error

    return CallObservationV1(
        export_name=export_name,
        input=input_bytes,
        return_data=bytes(result),
        failure_observed=False,
        logs=tuple(logs),
        promises=(),
        pre_storage=_storage_copy(pre_storage, "preStorage"),
        post_storage=_storage_copy(post_storage, "postStorage"),
    )


def require_nullary_uint64_view_observation_v1(
    observation: CallObservationV1,
    expected_export_name: str,
    expected_value_bytes: bytes,
) -> int:
    """Fail closed on every target-side premise of the Lean view relation."""
    if type(expected_value_bytes) is not bytes or len(expected_value_bytes) != 8:
        raise ObservationError("expected UInt64 value must be exactly 8 bytes")
    if observation.export_name != expected_export_name:
        raise ObservationError("observation exportName does not match selected method")
    if observation.input != b"":
        raise ObservationError("nullary view observation input must be empty")
    if observation.failure_observed:
        raise ObservationError("successful view observation reports failure")
    if observation.return_data is None:
        raise ObservationError("successful view observation has no return data")
    if len(observation.return_data) != 8:
        raise ObservationError("UInt64 view return data must be exactly 8 bytes")
    if observation.return_data != expected_value_bytes:
        raise ObservationError("UInt64 view return data does not match expected value")
    if observation.logs:
        raise ObservationError("UInt64 view observation must have no logs")
    if observation.promises:
        raise ObservationError("UInt64 view observation must have no promises")
    if dict(observation.post_storage) != dict(observation.pre_storage):
        raise ObservationError("UInt64 view observation changed storage")
    return int.from_bytes(observation.return_data, "little", signed=False)


def _expect_rejected(label: str, action: Callable[[], Any], message: str) -> None:
    try:
        action()
    except ObservationError as error:
        if message not in str(error):
            raise AssertionError(
                f"{label}: wrong error {error!s}; expected fragment {message!r}"
            ) from error
        return
    raise AssertionError(f"{label}: malformed observation was accepted")


def _self_test() -> None:
    expected = (7).to_bytes(8, "little")
    storage = {
        b"pf:v1:layout": (1).to_bytes(8, "little"),
        b"pf:v1:state:0": expected,
    }
    response = {"result": list(expected), "logs": []}
    observed = call_observation_from_view_response_v1(
        "status", b"", response, storage, storage
    )
    if require_nullary_uint64_view_observation_v1(
        observed, "status", expected
    ) != 7:
        raise AssertionError("valid UInt64 observation decoded the wrong value")

    response_mutations = (
        ("response-type", [], "must be an object"),
        ("response-error", {**response, "error": {}}, "reports failure"),
        ("result-type", {**response, "result": "bad"}, "must be a byte array"),
        ("result-bool", {**response, "result": [False]}, "integer byte"),
        ("result-range", {**response, "result": [256]}, "integer byte"),
        ("logs-type", {**response, "logs": "bad"}, "must be an array"),
        ("log-row", {**response, "logs": [1]}, "must be a string"),
        (
            "log-invalid-utf8",
            {**response, "logs": ["\ud800"]},
            "must be valid UTF-8 text",
        ),
        (
            "receipt-field",
            {**response, "receipts_outcome": []},
            "unexpectedly contains receipt field",
        ),
    )
    for label, mutation, message in response_mutations:
        _expect_rejected(
            label,
            lambda mutation=mutation: call_observation_from_view_response_v1(
                "status", b"", mutation, storage, storage
            ),
            message,
        )

    observation_mutations = (
        ("wrong-export", replace(observed, export_name="other"), "exportName"),
        ("nonempty-input", replace(observed, input=b"\x00"), "input must be empty"),
        ("failure", replace(observed, failure_observed=True), "reports failure"),
        ("missing-return", replace(observed, return_data=None), "no return data"),
        ("short-return", replace(observed, return_data=b"\x07"), "exactly 8 bytes"),
        (
            "wrong-return",
            replace(observed, return_data=(8).to_bytes(8, "little")),
            "does not match expected value",
        ),
        ("extra-log", replace(observed, logs=(b"unexpected",)), "no logs"),
        ("extra-promise", replace(observed, promises=(b"p0",)), "no promises"),
        (
            "storage-change",
            replace(observed, post_storage={**storage, b"pf:v1:state:0": b"bad"}),
            "changed storage",
        ),
    )
    for label, mutation, message in observation_mutations:
        _expect_rejected(
            label,
            lambda mutation=mutation: require_nullary_uint64_view_observation_v1(
                mutation, "status", expected
            ),
            message,
        )

    _expect_rejected(
        "bad-expected-width",
        lambda: require_nullary_uint64_view_observation_v1(
            observed, "status", b"\x07"
        ),
        "expected UInt64 value must be exactly 8 bytes",
    )
    print("near-observation-v1: self-test ok")


def main(argv: list[str]) -> int:
    if argv == ["self-test"]:
        _self_test()
        return 0
    print("usage: observation_v1.py self-test", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
