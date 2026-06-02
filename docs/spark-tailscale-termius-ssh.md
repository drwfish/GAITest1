# SSH into a DGX Spark over Tailscale from Termius (phone)

Troubleshooting runbook for: *"My Spark on Tailscale isn't logging in on Termius on my phone."*

This covers an **NVIDIA DGX Spark** reached over a **Tailscale** tailnet from the
**Termius** mobile SSH app. Work top to bottom — the checks are ordered by how
often they're the real cause.

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
- Tailscale key expiry: <https://login.tailscale.com/admin/machines>
