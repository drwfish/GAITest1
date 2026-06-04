# SSH into a DGX Spark over Tailscale from Termius (phone)

Troubleshooting runbook for: *"My Spark on Tailscale isn't logging in on Termius on my phone."*

This covers an **NVIDIA DGX Spark** reached over a **Tailscale** tailnet from the
**Termius** mobile SSH app. Work top to bottom — the checks are ordered by how
often they're the real cause.

---

## Remote-only recovery (no local console, you're off-site)

You don't need to touch the Spark to get back in. Everything here runs from a
**phone browser**.

### Win #1 — Tailscale SSH Console (browser shell, no key, no Termius)

If the Spark was brought up with Tailscale SSH (`tailscale up --ssh`, which the
official NVIDIA Spark Tailscale playbook does), you can open a shell straight
from the admin console:

1. On the phone browser go to <https://login.tailscale.com/admin/machines> and
   sign in (you must be Owner/Admin of the tailnet — you are, it's your Spark).
2. Find the Spark. If it shows **green/online**, tap the **⋯** menu → **SSH to
   machine** (a.k.a. "Connect"). Your browser becomes a tailnet node via
   WebAssembly and drops you into a shell — auth is your tailnet identity, so
   **no SSH key and no password are involved**. Termius being broken is
   irrelevant here.
3. You're now logged in. From this shell you can repair whatever was blocking
   Termius (add your Termius public key to `authorized_keys`, restart `ssh`,
   etc. — see §5/§6 below).

If "SSH to machine" is greyed out / missing, the node either isn't online or
doesn't have Tailscale SSH enabled — fall through to the next wins.

### Win #2 — Fix it from the admin console UI (no shell needed)

Even with zero shell access, from the phone browser you can:

- **Disable key expiry** (⋯ → *Disable key expiry*) — fixes/prevents the 90‑day
  expiry lockout, the single most common "it logged in before, now it won't".
- **Check online state** — if the Spark shows **Expired** or **Offline**, no SSH
  path will work until it re‑authenticates; that points you at the real problem.
- **Edit ACLs / DNS** — enable MagicDNS, or add the SSH policy rule that Win #1
  needs.

### Win #3 — NVIDIA Sync / web dashboard over the tailnet

NVIDIA Sync gives remote access that comes up as a system service *before*
login. If it's set up, reach the Spark's web console at its tailnet IP from the
phone browser as another way in.

### If the node is Expired/Offline

A truly expired node needs `tailscale up` re-auth, which normally needs a shell —
the catch‑22. Remote outs: NVIDIA Sync (Win #3) if it's running, or an auth-key
re-add if you pre‑provisioned one. If none exist, this is the one case that
needs someone to touch the box. Disabling key expiry now (Win #2) prevents it
from ever recurring.

---

## 0. Two‑minute triage

On the **Spark** (use the local console, keyboard+monitor, or NVIDIA Sync if SSH
is down) run:

```bash
tailscale status        # Spark should be logged in and show peers
systemctl is-active ssh # should print: active
whoami                  # note the exact username you log in as
tailscale ip -4         # the 100.x.y.z address of the Spark
```

On the **phone**:

1. Open the **Tailscale app** and confirm the VPN toggle is **ON** and you're
   signed into the **same tailnet** (same account/org) as the Spark.
2. Open the **Tailscale admin console** → Machines. Both the Spark *and* the
   phone must be listed and **not** showing "Expired".

If either device is **Expired** or the phone toggle is **Off**, that's almost
certainly your problem — jump to §1 and §2.

---

## 1. Phone isn't actually on the tailnet

Termius does **not** run Tailscale. The phone's own Tailscale app must be
connected for Termius traffic to reach the Spark's `100.x.y.z` address.

- Install Tailscale from the App Store / Play Store, sign in to the **same**
  tailnet as the Spark, and flip the toggle **ON**.
- iOS: Tailscale is a VPN profile — make sure another VPN isn't overriding it.
- Verify reachability from a separate Termius/terminal session by pinging the
  Spark's tailnet IP if your client supports it, or just try the SSH connect
  after the toggle is on.

## 2. Tailscale key expiry locked you out

By default Tailscale node keys **expire every ~90 days**, after which the device
goes offline until re‑authenticated — this is the #1 "it worked last month and
now I can't log in remotely" cause.

Fix (Spark, and ideally the phone too):

1. Go to <https://login.tailscale.com/admin/machines>.
2. Find the **Spark**, open the **⋯** menu → **Disable key expiry**.
3. If it already expired, on the Spark run `sudo tailscale up` and complete the
   auth URL to bring it back online.

## 3. "Connection refused" / "Connection timed out"

- **Refused** → `sshd` isn't running on the Spark:
  ```bash
  sudo systemctl enable --now ssh
  sudo systemctl status ssh
  ```
- **Timed out / no route** → the network layer isn't there. Re‑check §1/§2, and
  confirm the Spark shows green/online in the admin console. Try the Spark's
  **tailnet IP** (`tailscale ip -4`, a `100.x.y.z` address) in Termius instead
  of a hostname.

## 4. "Could not resolve hostname" → use the Tailnet IP, not MagicDNS

Termius is a third‑party app and does **not** reliably use Tailscale's MagicDNS
resolver on the phone. A name like `spark` or `spark.tail1234.ts.net` may not
resolve.

- In the Termius host, set **Address** to the Spark's **`100.x.y.z`** tailnet IP
  (from `tailscale ip -4`). This is the most robust option.
- If you prefer the name, use the **full MagicDNS** name
  (`spark.<your-tailnet>.ts.net`) and confirm MagicDNS is enabled in the admin
  console → DNS.

## 5. "Permission denied (publickey)" — the most common login failure

The DGX Spark's `sshd` is configured for **key authentication** (password login
over SSH is typically disabled). A password in Termius will be rejected. You have
two clean options:

### Option A — Tailscale SSH (no key management)

If the Spark was brought up with Tailscale SSH, Tailscale authenticates by your
tailnet identity instead of an SSH key:

```bash
# on the Spark
sudo tailscale up --ssh
```

Then in your tailnet **ACLs** (admin console → Access controls) make sure a rule
allows your phone/user to SSH as the Spark's local user, e.g.:

```jsonc
"ssh": [
  {
    "action": "accept",
    "src":    ["autogroup:member"],
    "dst":    ["autogroup:self"],
    "users":  ["autogroup:nonroot", "<your-spark-username>"]
  }
]
```

With this, connect in Termius using just **username + tailnet IP** and **no
key** (leave Termius' key blank / password unused). The username **must** be a
real local account on the Spark (see §6).

### Option B — Classic SSH key (works with any tailnet/ACL)

1. In **Termius** → **Keychain** → generate a new key (Ed25519), or import one
   you already have. Copy its **public** key.
2. On the **Spark**, add that public key:
   ```bash
   mkdir -p ~/.ssh && chmod 700 ~/.ssh
   echo 'ssh-ed25519 AAAA...the-termius-public-key... user@phone' >> ~/.ssh/authorized_keys
   chmod 600 ~/.ssh/authorized_keys
   ```
3. In the Termius host config, attach that key under **Use Key**, set the
   correct **Username**, and **Address** = Spark tailnet IP.

> Permissions matter: `~/.ssh` must be `700` and `authorized_keys` `600`, or
> sshd silently refuses the key.

## 5b. Hangs forever on "Authenticating…" — Tailscale SSH `check` mode

If the connection reaches the auth phase and **spins on "Authenticating…"**
indefinitely (TCP is fine, node is green), the Spark is almost certainly running
Tailscale SSH with an ACL `"action": "check"` rule. `check` mode requires the
user to **re-approve each session in a browser**; Tailscale sends a "visit URL to
authenticate" prompt that a raw client like Termius can't display, so it hangs.

**Signature in the Termius log:** the connection resolves to the `100.x` tailnet
IP, establishes, reports `Remote server: SSH-2.0-Tailscale`, agrees ciphers, says
**"Handshake finished" — then fails** with "Connection could not be
established." Everything up to auth works; Tailscale SSH then *refuses
authorization* because (a) there is no `ssh` ACL `accept` rule matching
src→dst→user, or (b) the rule is `check` (needs a browser approval Termius can't
display), or (c) the login user isn't permitted by the rule's `users`.

Two remote fixes (phone browser, no local console):

- **Best:** connect once via the **Tailscale SSH Console** (admin console →
  `spark-4e24` → SSH) — being a browser, it completes the check automatically and
  logs you in. Good for getting in *now*.
- **Permanent (makes Termius work):** in the admin console → **Access controls**,
  change the SSH rule `action` from `check` to `accept` for your user/device:
  ```jsonc
  "ssh": [
    {
      "action": "accept",            // was: "check"
      "src":    ["autogroup:member"],
      "dst":    ["autogroup:self"],
      "users":  ["autogroup:nonroot", "ubuntu"]
    }
  ]
  ```
  Save, then retry Termius — auth completes instantly with no browser step.

## 5c. Times out on a PUBLIC IP — Termius is bypassing the tailnet

If the Termius connection log shows it resolving the host to a **public** address
(e.g. an IPv6 like `2607:7700:…`, anything outside `100.64.0.0/10` or
`fd7a:115c::/48`) and then **timing out**, Termius is going over the open
internet instead of through Tailscale. The Spark isn't exposed publicly, so it
hangs and fails.

Tailscale ranges (what you SHOULD see it connect to):
- IPv4: `100.x.y.z` (CGNAT range `100.64.0.0/10`)
- IPv6: `fd7a:115c:a1e0:…`

Causes & fixes (phone only):

1. **Phone's Tailscale tunnel isn't actually up.** The node showing "Connected"
   in the Tailscale app's device detail is the *node's* status, not proof your
   phone's VPN is routing. Open the Tailscale app, ensure the main **toggle is
   ON**, and confirm the VPN indicator is in the status bar. If the tunnel were
   up, DNS would resolve to the `100.x`/`fd7a` address, not a public one.
2. **Host Address is a name that resolves publicly.** A literal `100.x` can't
   resolve to a public IPv6 — so the Address field holds a hostname/DDNS. Replace
   it with the **literal Tailscale IPv4** (`tailscale ip -4`, e.g.
   `100.120.71.65`). Remove any separate hostname / jump-host entry.

## 5d. Literal `100.x` IP times out on an IPv6 address — NAT64, tunnel is down

On an **IPv6-only mobile network** (common on 5G), if you connect to the literal
Tailscale IP and the log shows it dialing a synthesized IPv6 and timing out:

```
Starting a new connection to: "100.120.71.65" port 22
Connecting to "2607:7700:0:27:0:2:6478:4741" port 22   ← NAT64 of 100.120.71.65
Connection failed: connection timed out.
```

That IPv6 is **NAT64-synthesized**: the last 32 bits encode the IPv4 in hex
(`100.120.71.65` -> `0x64 0x78 0x47 0x41` -> `6478:4741`), wrapped in the
carrier's NAT64 prefix. It means **the phone's Tailscale tunnel is NOT active** —
so the `100.64.0.0/10` CGNAT address isn't captured by Tailscale and instead
falls through to the carrier's NAT64 gateway, which can't route a private address.

(NB: this is *not* a proxy/jump host — Termius Proxy and Host Chaining are paid
features and usually aren't even enabled. Don't chase those.)

Fix (phone):

1. Open the **Tailscale app**, ensure the **main toggle is ON**, and confirm the
   **VPN indicator** is in the status bar. The node showing "Connected" in the
   device list is the *peer's* status, not your phone's tunnel.
2. Reconnect. With the tunnel up, Tailscale owns the `100.x` route and NAT64
   never sees it.
3. Prefer the **MagicDNS name** (`<host>.<tailnet>.ts.net`) over the literal IP —
   it only resolves while Tailscale is up, so a down tunnel fails loudly instead
   of silently NAT64-ing to a timeout.

## 6. Wrong username

`Permission denied` also appears when the **username** is wrong. SSH as the
account that actually exists on the Spark (the one `whoami` printed in §0) — not
`root`, and not your laptop's username. Set it explicitly in Termius.

## 7. Stale / changed host key

If Termius warns about a **host key mismatch** (e.g. after a Spark reinstall),
delete the saved host entry / known host in Termius and reconnect, accepting the
new fingerprint.

---

## Quick decision guide

| Symptom in Termius                     | Most likely cause | Section |
|----------------------------------------|-------------------|---------|
| Spins then "timed out" / "no route"    | Phone not on tailnet, or key expired | §1, §2 |
| "Connection refused"                   | sshd not running on Spark | §3 |
| "Could not resolve hostname"           | MagicDNS not resolving — use 100.x IP | §4 |
| "Permission denied (publickey)"        | Key not installed / password auth off | §5 |
| "Permission denied" with a key set     | Wrong username, or key perms | §5, §6 |
| Host key / fingerprint warning         | Stale known host | §7 |

## References

- NVIDIA — Set up Tailscale on Your Spark (instructions & troubleshooting):
  <https://build.nvidia.com/spark/tailscale/troubleshooting>
- NVIDIA Developer Forums — Mobile DGX management with Termius + Tailscale:
  <https://forums.developer.nvidia.com/t/mobile-dgx-management-in-2026-dgx-console-on-iphone-jupyterlab-on-ipad-with-termius-tailscale/356609>
- NVIDIA DGX Spark Remote Access Runbook:
  <https://www.xingzhang.me/blog/dgx_spark_remote_access_runbook/>
- Tailscale SSH docs: <https://tailscale.com/docs/features/tailscale-ssh>
- Tailscale SSH Console (browser shell): <https://tailscale.com/docs/features/tailscale-ssh/tailscale-ssh-console>
- NVIDIA Sync (DGX Spark remote access): <https://docs.nvidia.com/dgx/dgx-spark/nvidia-sync.html>
- Tailscale key expiry: <https://login.tailscale.com/admin/machines>
