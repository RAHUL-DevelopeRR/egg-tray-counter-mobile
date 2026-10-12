# "Backend offline" and "scan could not be processed", 2026-10-12

Reported by the operator on the Redmi (Jio LTE, IPv6-only with NAT64). Measured from the laptop
(Wi-Fi, public IP 115.244.249.170, Cloudflare colo CJB) and from the phone over adb.

## What fails

| target | path | result |
|---|---|---|
| staging Worker `/health` | laptop, default | 12 ok / 8 failed of 20 (curl HTTP 000: connection closed during the TLS handshake, step 2/3) |
| production Worker `/health` | laptop, default | 2 ok / 8 failed of 10 |
| staging Worker | laptop, IPv4 only | 8 ok / 4 failed of 12 |
| staging Worker | laptop, IPv6 only | 0 ok / 12 failed |
| production Worker | laptop, IPv4 / IPv6 | 7/3 and 0/10 |
| welcome.developers.workers.dev | laptop, IPv4 / IPv6 | 10/0 and 0/10 |
| www.cloudflare.com, developers.cloudflare.com | laptop, IPv4 / IPv6 | 8/0 and 0/8, 0/6 |
| www.google.com | laptop, default | 10/0 |
| staging Worker host | phone, ping6 x10 | 40% and 66% packet loss (two runs), 254-308 ms |
| 2001:4860:4860::8888 (Google) | phone, ping6 x10 | 0% loss, 36-200 ms |
| app home screen, 6 cold launches | phone | SERVER REACHABLE 6/6 (one health GET usually survives 40% loss) |

The Worker itself is healthy whenever a connection completes (both `/health` and `/ready` answer
in milliseconds), the Worker log shows no errors, and the app's own log has no crash. The fault is
the network path between this operator's connections and the Cloudflare addresses that serve the
`*.workers.dev` hostnames: IPv6 is dead from the laptop's Wi-Fi for every Cloudflare host, and
IPv4 to the two Workers drops about a third of TLS handshakes while other Cloudflare sites and
another workers.dev host do not. From the phone's Jio IPv6 path the Worker host loses 40-66% of
packets while Google loses none. A three-photo upload (about 1.5 MB at 1920 px) on a 40%-loss link
easily exceeded the app's 45 s send timeout, and one dropped handshake on the pre-upload health
check failed the whole scan before any photo was sent.

## What changed in the app (0.4.9)

- Health check: three tries 0.8 s / 2 s apart before showing "SERVER NOT REACHED - TAP TO RETRY";
  the status card is tappable.
- Pre-upload server check: three tries. Upload: four tries with 0.8 / 2 / 5 s pauses; connection
  resets, handshake failures and timeouts are retried, HTTP answers are not.
- Timeouts: send 150 s, receive 90 s (were 45 s / 45 s).
- Error text in the operator's words (connection dropped / upload too slow / server did not answer)
  with the instruction to move to better signal or Wi-Fi and tap RETRY SAME SCAN.
- Uploads capped at 1600 px on the long side, JPEG quality 92: 138-290 KB per photo instead of
  437-669 KB. Measured on staging: identical per-stack counts at 1280 and 1600 px for photos 01,
  02 (both sides) and 19 (`upload-size.json`).

## What would remove the fault

Serve the API on a custom domain on the owner's own Cloudflare zone instead of `*.workers.dev`
(a Workers custom domain). The measurements above show the drops are specific to the workers.dev
addresses on these two Indian connections, not to Cloudflare in general. This needs a domain in
the Cloudflare account; not done here.
