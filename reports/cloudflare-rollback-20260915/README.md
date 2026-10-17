# User-requested baseline rollback

Date: 2026-09-15. Worker: egg-tray-counter-api.
URL: https://egg-tray-counter-api.rahultech72216.workers.dev

Wrangler deployment history showed the version immediately before the September
14 update was 621a5a9c-f486-455f-9a15-0965ca3a710f, created August 31.
Ran `wrangler rollback 621a5a9c-f486-455f-9a15-0965ca3a710f --yes` with a
user-request rollback message. CLI confirmed that version deployed to 100% traffic.
The previous active version was 0519381f-b99e-4015-8279-cb2c0f99f7f2.

Live health.json returned status ok; ready.json reported projec-mutta/2 ready.
Attempts to POST three existing benchmark photos with only scan_id and image
fields failed at TLS connection establishment: curl connection reset (HTTP 000),
httpx WinError 10054. No successful new inference response was obtained.
Earlier baseline inference evidence is in manual-reference-20260913/.

Local code and APK are unchanged. APK 0.2.2's newer contract is incompatible
with restored health; older 0.2.1 UI ID requirements also remain in its binary.
Do not mistake this server rollback for a compatible APK rebuild or improved
counting accuracy. Preserve the newer source for continued hybrid development.
