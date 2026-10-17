"""scripts/devices.py on fake listings: untrusted fields are escaped, shared codes are marked, approve refuses a
shared code unless asked. No network: the Worker calls are replaced; every token here is an obvious fake.

Run from the repository root:
  python -m pytest -p no:faulthandler -p no:cacheprovider scripts/tests/test_devices.py
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import devices as dv  # noqa: E402

PHONE = "abcd1234-1111-4111-8111-111111111111"
COPY = "abcd1234-2222-4222-8222-222222222222"
OTHER = "0f0f0f0f-3333-4333-8333-333333333333"
# Written with chr() so this file stays plain ASCII: newline, carriage return, ESC, RIGHT-TO-LEFT OVERRIDE, zero-width space.
FORGED_LABEL = "x" + chr(10) + "ABCD-1234  active" + chr(13) + chr(0x1B) + "[2K" + chr(0x202E) + "enohp" + chr(0x200B)


def record(device_id: str, status: str = "pending", label: str | None = "Redmi Note 13", created_at: str = "2026-10-15T09:00:00.000Z"):
    return {"device_id": device_id, "display_code": f"{device_id[:4]}-{device_id[4:8]}".upper(), "status": status, "label": label,
            "app_version": "0.4.12+23", "created_at": created_at, "approved_at": None, "revoked_at": None}


class FakeWorker:
    """Answers dv.call like the enforced Worker's admin routes, from an in-memory device list."""

    def __init__(self, devices: list[dict]):
        self.devices = devices
        self.calls: list[tuple[str, str]] = []

    def __call__(self, base: str, method: str, path: str, token: str) -> dict:
        assert token == "fake-admin-token"
        self.calls.append((method, path))
        if method == "GET" and path.startswith("/v1/admin/devices"):
            return {"devices": self.devices, "cursor": None}
        if method == "POST" and path.endswith("/approve"):
            device_id = path.split("/")[-2]
            target = next(d for d in self.devices if d["device_id"] == device_id)
            target["status"] = "active"
            return target
        raise AssertionError(f"unexpected call {method} {path}")


def run(monkeypatch, capsys, worker: FakeWorker, *argv: str):
    monkeypatch.setenv(dv.TOKEN_VARIABLE, "fake-admin-token")
    monkeypatch.setattr(dv, "call", worker)
    monkeypatch.setattr(sys, "argv", ["devices.py", *argv])
    code = dv.main()
    out = capsys.readouterr()
    return code, out.out, out.err


def test_printable_escapes_everything_a_terminal_would_act_on():
    shown = dv.printable(FORGED_LABEL)
    assert shown == "x\\nABCD-1234  active\\r\\x1b[2K\\u202eenohp\\u200b"
    assert shown.isprintable() and shown.isascii()
    assert dv.printable(None) == ""
    assert dv.printable("Redmi Note 13") == "Redmi Note 13"


def test_list_keeps_one_line_per_device_and_marks_a_shared_code(monkeypatch, capsys):
    worker = FakeWorker([record(PHONE, created_at="2026-10-15T09:00:00.000Z"),
                         record(COPY, label=FORGED_LABEL, created_at="2026-10-15T09:05:00.000Z"), record(OTHER)])
    code, out, _ = run(monkeypatch, capsys, worker, "list")
    assert code == 0
    lines = out.splitlines()
    rows = [line for line in lines if line.startswith(("ABCD-1234", "0F0F-0F0F"))]
    assert len(rows) == 3                                     # the forged label adds no row
    assert all(chr(0x1B) not in line and chr(0x202E) not in line for line in lines)
    assert sum("SHARED CODE" in row for row in rows) == 2
    assert "SHARED CODE" not in next(row for row in rows if row.startswith("0F0F-0F0F"))
    assert any(line.startswith("warning: more than one device shows the code ABCD-1234") for line in lines)


def test_pending_listing_marks_a_copy_of_an_active_phone_code(monkeypatch, capsys):
    worker = FakeWorker([record(PHONE, status="active"), record(COPY)])
    code, out, _ = run(monkeypatch, capsys, worker, "list", "--status", "pending")
    assert code == 0
    rows = [line for line in out.splitlines() if line.startswith("ABCD-1234")]
    assert len(rows) == 1 and COPY in rows[0] and "SHARED CODE" in rows[0]


def test_approve_refuses_a_shared_code_unless_asked(monkeypatch, capsys):
    worker = FakeWorker([record(PHONE), record(COPY, created_at="2026-10-15T09:05:00.000Z")])
    code, out, err = run(monkeypatch, capsys, worker, "approve", COPY)
    assert code == 1
    assert "--shared-code-ok" in err
    assert PHONE in out and COPY in out                        # both candidates are shown for the decision
    assert not any(method == "POST" for method, _ in worker.calls)
    code, out, _ = run(monkeypatch, capsys, worker, "approve", PHONE, "--shared-code-ok")
    assert code == 0
    assert worker.calls[-1] == ("POST", f"/v1/admin/devices/{PHONE}/approve")
    assert "ABCD-1234 " + PHONE + " is now active" in out


def test_approve_echoes_label_and_registration_time_escaped(monkeypatch, capsys):
    worker = FakeWorker([record(PHONE, label=FORGED_LABEL), record(OTHER)])
    code, out, _ = run(monkeypatch, capsys, worker, "approve", PHONE.upper())
    assert code == 0
    assert out.count("\n") == 1
    assert "is now active (label x\\nABCD-1234  active" in out
    assert "registered 2026-10-15T09:00:00.000Z)" in out


def test_approve_of_a_revoked_device_is_left_to_the_worker_refusal(monkeypatch, capsys):
    posted = []

    def refuse(base, method, path, token):
        if method == "GET":
            return {"devices": [record(PHONE, status="revoked"), record(COPY)], "cursor": None}
        posted.append(path)
        raise dv.AdminError("HTTP 409 device_revoked: Device ABCD-1234 was revoked and cannot be approved again")

    code, _, err = run(monkeypatch, capsys, refuse, "approve", PHONE)
    assert code == 1
    assert posted == [f"/v1/admin/devices/{PHONE}/approve"]
    assert "device_revoked" in err and "--shared-code-ok" not in err


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-q"]))
