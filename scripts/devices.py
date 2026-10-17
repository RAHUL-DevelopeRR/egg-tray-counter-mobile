"""Approve, revoke and list the phones allowed to use the Worker (AUTH_MODE enforce, or observe during the rollout).

Each phone registers itself on first launch as pending and shows its device code
(XXXX-XXXX, the first 8 hex digits of its device id). The administrator approves it
here; a lost phone is revoked here and is refused on its next request.

The admin token is read from the environment variable EGG_ADMIN_TOKEN (the operator's
copy lives in work/secrets/staging-admin-token, git-ignored). It is sent only as the
Authorization header and never printed. Contract: docs/SCAN_JOBS_AND_DEVICES.md.

Anyone can register, and the phone chooses its own device id, so labels, app versions
and even the XXXX-XXXX code are the registrant's words: `list` prints them escaped and
marks a code that more than one device shows, and `approve` refuses a shared code unless
--shared-code-ok is given (then approve the id whose registration time matches the install).
Revocation is final: the Worker refuses to approve a revoked device again.

Usage (repo root, PowerShell):
  $env:EGG_ADMIN_TOKEN = Get-Content work/secrets/staging-admin-token
  python scripts/devices.py list [--status pending]
  python scripts/devices.py show <device_id or XXXX-XXXX>
  python scripts/devices.py approve <device_id> [--shared-code-ok]
  python scripts/devices.py revoke <device_id>
  python scripts/devices.py --url https://... list
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter

STAGING = "https://egg-tray-counter-api-staging.rahultech72216.workers.dev"
TOKEN_VARIABLE = "EGG_ADMIN_TOKEN"


class AdminError(Exception):
    pass


def admin_token() -> str:
    token = os.environ.get(TOKEN_VARIABLE, "").strip()
    if not token:
        raise AdminError(f"{TOKEN_VARIABLE} is not set. Set it to the Worker's ADMIN_TOKEN (see the usage at the top of this script).")
    return token


def call(base: str, method: str, path: str, token: str) -> dict:
    request = urllib.request.Request(
        base.rstrip("/") + path, method=method, data=b"" if method == "POST" else None,
        headers={"Authorization": f"Bearer {token}", "User-Agent": "egg-tray-tools/1.0", "Accept": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        try:
            detail = json.loads(error.read().decode("utf-8")).get("detail", {})
        except (ValueError, AttributeError):
            detail = {}
        code, message = detail.get("code", "unknown"), detail.get("message", "")
        if error.code == 401:
            raise AdminError(f"401 {code}: the admin token was refused. Check that {TOKEN_VARIABLE} matches the Worker's ADMIN_TOKEN "
                             "secret for this URL; while that secret is unset every admin call is refused.") from None
        if error.code == 403:
            raise AdminError(f"403 {code}: {message or 'forbidden'}") from None
        if error.code == 404 and code == "not_found":
            raise AdminError("404: this Worker has no device routes. Is AUTH_MODE enforce or observe deployed at this URL?") from None
        raise AdminError(f"HTTP {error.code} {code}: {message}") from None
    except urllib.error.URLError as error:
        raise AdminError(f"could not reach {base}: {error.reason}") from None


def all_devices(base: str, token: str, status: str | None = None) -> list[dict]:
    devices, cursor = [], None
    while True:
        query = {key: value for key, value in (("status", status), ("cursor", cursor)) if value}
        page = call(base, "GET", "/v1/admin/devices" + (f"?{urllib.parse.urlencode(query)}" if query else ""), token)
        devices.extend(page.get("devices", []))
        cursor = page.get("cursor")
        if not cursor:
            return devices


def find(devices: list[dict], wanted: str) -> dict:
    wanted = wanted.strip().lower()
    matches = [d for d in devices if d["device_id"] == wanted or d.get("display_code", "").lower() == wanted]
    if not matches:
        raise AdminError(f"no device {wanted}")
    if len(matches) > 1:
        raise AdminError(f"{len(matches)} devices share the code {wanted.upper()}; use the full device id")
    return matches[0]


def printable(value: object) -> str:
    """A record field as table text. Fields come from the registrant: control characters, bidi overrides and
    invisible marks are shown escaped (\\n, \\x1b, \\u202e) so they cannot add, hide or reorder rows."""
    text = "" if value is None else str(value)
    return "".join(c if c.isprintable() else c.encode("unicode_escape").decode("ascii") for c in text)


def shared_codes(devices: list[dict]) -> set[str]:
    """Display codes shown by more than one device. The code is the start of the phone-chosen device id, so a
    registrant who saw a phone's WAITING code can register a copy of it."""
    counts = Counter(d.get("display_code") or "" for d in devices)
    return {code for code, n in counts.items() if code and n > 1}


def print_table(devices: list[dict], shared: set[str] | None = None) -> None:
    if not devices:
        print("no devices")
        return
    shared = shared_codes(devices) if shared is None else shared
    print(f"{'code':<10} {'status':<8} {'device_id':<37} {'label':<20} {'app':<12} {'registered':<20} changed")
    for d in sorted(devices, key=lambda d: d.get("created_at") or ""):
        changed = d.get("revoked_at") if d.get("status") == "revoked" else d.get("approved_at")
        mark = "  SHARED CODE" if d.get("display_code") in shared else ""
        print(f"{printable(d.get('display_code')):<10} {printable(d.get('status')):<8} {printable(d.get('device_id')):<37} "
              f"{printable(d.get('label'))[:20]:<20} {printable(d.get('app_version'))[:12]:<12} "
              f"{printable(d.get('created_at'))[:19]:<20} {printable(changed)[:19]:<19}{mark}".rstrip())
    for code in sorted(shared & {d.get("display_code") for d in devices}):
        print(f"warning: more than one device shows the code {printable(code)}. Device ids are chosen by the phone, so "
              "one of them may be a copy: approve only the id whose registration time matches the install.")


def change_status(base: str, token: str, wanted: str, action: str, shared_code_ok: bool = False) -> dict:
    device_id = wanted.strip().lower()
    if action == "approve":
        devices = all_devices(base, token)
        target = next((d for d in devices if d.get("device_id") == device_id), None)
        # Only a pending device changes; the Worker answers for the others (active: no-op, revoked: refused).
        if target and target.get("status") == "pending" and target.get("display_code") in shared_codes(devices) and not shared_code_ok:
            print_table([d for d in devices if d.get("display_code") == target.get("display_code")])
            raise AdminError(f"the code {printable(target.get('display_code'))} is shown by more than one device (above). "
                             "Check the registration time against the install, then rerun with --shared-code-ok.")
    return call(base, "POST", f"/v1/admin/devices/{urllib.parse.quote(device_id, safe='')}/{action}", token)


def main() -> int:
    parser = argparse.ArgumentParser(description="Manage the devices allowed to use the egg-tray Worker.")
    parser.add_argument("--url", default=STAGING, help=f"Worker base URL (default {STAGING})")
    commands = parser.add_subparsers(dest="command", required=True)
    listing = commands.add_parser("list", help="every registered device")
    listing.add_argument("--status", choices=("pending", "active", "revoked"))
    commands.add_parser("show", help="one device as JSON").add_argument("device", help="device id or XXXX-XXXX code")
    approving = commands.add_parser("approve", help="allow a pending device (a revoked device cannot be approved again)")
    approving.add_argument("device", help="full device id")
    approving.add_argument("--shared-code-ok", action="store_true",
                           help="approve although another device shows the same XXXX-XXXX code")
    commands.add_parser("revoke", help="refuse a device from its next request").add_argument("device", help="full device id")
    args = parser.parse_args()
    # Printable non-ASCII labels must not crash a console or pipe that cannot encode them.
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="backslashreplace")
    try:
        token = admin_token()
        if args.command == "list":
            # Shared codes are found across every status, so a copy of an active phone's code shows in a pending listing.
            devices = all_devices(args.url, token)
            print_table([d for d in devices if not args.status or d.get("status") == args.status], shared_codes(devices))
        elif args.command == "show":
            print(json.dumps(find(all_devices(args.url, token), args.device), indent=1))
        else:
            record = change_status(args.url, token, args.device, args.command, getattr(args, "shared_code_ok", False))
            print(f"{printable(record.get('display_code'))} {printable(record.get('device_id'))} is now {printable(record.get('status'))} "
                  f"(label {printable(record.get('label')) or '-'}, registered {printable(record.get('created_at')) or '-'})")
    except AdminError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
