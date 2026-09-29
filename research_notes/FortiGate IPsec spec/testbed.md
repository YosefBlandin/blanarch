# FortiGate test bed for a third-party IKEv2 dial-up client

Researched 2026-09-28. Scope: how to stand up a FortiGate we control, so the Blanarch IKEv2 engine can be developed and
traced against a real gateway.

Clean-room method note: the sources are Fortinet public docs (docs.fortinet.com), Fortinet Community KB and forum
threads, IETF RFCs (rfc-editor.org), the IANA IKEv2 registry, Android developer docs, cloud vendor pricing and terms
pages (AWS, Microsoft, Google), UTM user docs, the Wireshark user guide, and one practitioner blog (yurisk.info). No
source code, code repositories, READMEs or issue trackers of any VPN/IPsec implementation were opened. One blog links
to a GitHub cheat sheet, and it was not followed. Forum posts quoted below contain FortiGate CLI and debug output, which
is product output, not implementation code.

Confidence tags: **[doc]** Fortinet or IETF documentation says so. **[KB]** Fortinet staff KB article.
**[forum]** community post by a user. **[blog]** third-party blog. **[inference]** my reasoning from the cited facts.
**[trace]** means the claim must be confirmed on a live FortiGate before the engine relies on it.

---

## 1. Bottom line

### Takeaway
- The free "permanent trial" FortiGate-VM is real, free, and never expires, but it is **low encryption only**. Users
  report that IPsec proposals are limited to DES or NULL ciphers, with no AES or 3DES. DES is "MUST NOT" in RFC 8247,
  and Android's IKE API has no DES constant at all. So the trial can exercise the IKEv2 **state machine, EAP, mode-cfg,
  split tunnel and TCP transport**, but not the cipher suites a real company gateway will use. [doc] [forum]
- For AES/SHA2 you need a real license. There are three cheap routes: (a) the AWS Marketplace PAYG FortiGate, whose
  **software** fee is free for 30 days (you still pay the EC2 instance); (b) a 60-day evaluation license from a Fortinet
  sales engineer, which lifts the trial limits; (c) a paid license. [doc] [KB] [blog]
- On an Apple Silicon Mac, Fortinet itself documents running the **ARM64 KVM** FortiGate image in UTM with
  "Virtualize" (native speed). Emulating the x86 image works in principle, but it is slow. Whether the permanent trial
  license activates on the ARM64 KVM image is not stated anywhere. [KB] [doc] [trace]
- Fortinet documents a complete **dial-up IKEv2 + EAP + local user group + mode-cfg pool + split-include + TCP
  transport** example (quoted in section 6). Since FortiOS 7.6.3 the default TCP port for IKE/ESP over TCP is 443. [doc]
- Email two-factor for local users needs **no license**. But Fortinet says the FortiClient token prompt during IKEv2
  "relies on proprietary EAP extensions" and is not supported for other VPN clients. The documented escape hatch is
  appending the OTP to the password (shown for FortiToken). Whether the same works for **email** OTP is undocumented
  and must be traced. [KB] [trace]

### Recommended bench (inference)
1. Phase A (free): UTM on the Mac + FortiGate ARM64 KVM image + permanent trial. Build the IKE_SA_INIT / IKE_AUTH / EAP
   / CFG / TCP-encapsulation code paths with a lab-only DES proposal, **or** skip straight to phase B if the trial
   refuses to license the ARM64 image. [inference]
2. Phase B (short, paid by the hour): AWS PAYG FortiGate (t2.small x86 or t4g/c6g.medium ARM64) during its 30-day
   software trial, to test AES-CBC/AES-GCM + SHA2 + DH 14/19/20 exactly like a production gateway. Stop the instance
   when not in use. [inference]
3. Keep one FortiOS version on the bench close to the company gateway's version, because defaults (TCP port, transport
   knobs) changed between 7.4, 7.6 and 8.0 (section 6.3). [inference]

---

## 2. Permanent trial (evaluation) license

### How to get it
- FortiGate-VM has a permanent evaluation license. It applies to all private cloud hypervisors (VMware ESXi, KVM, and so
  on) and to all BYOL public cloud instances. On first boot you either log in to FortiCloud to activate the trial, or
  upload a license. [doc] https://docs.fortinet.com/document/fortigate/7.6.6/administration-guide/441460/permanent-trial-mode-for-fortigate-vm
- CLI activation (documented):
  ```
  execute vm-license-options account-id xxxx@fortinet.com
  execute vm-license-options account-password xxxxxxx
  execute vm-license
  ```
  The prompt says "This VM is using the evaluation license. This license does not expire." and the VM reboots. The GUI
  path is the "FortiGate VM License" page, "Evaluation License", then the FortiCare email and password. [doc] same URL
- Check with `get system status` (License Status: Valid, "VM Resources: 1 CPU/1 allowed, ... 2048 MB allowed"),
  `diagnose hardware sysinfo vm full`, and `diagnose debug vm-print-license` (shows "Model: EVAL"). [doc] same URL
- A free FortiCloud (FortiCare) account is enough. The VM needs Internet access (DNS for FortiGuard names) to activate,
  or a FortiManager can apply the license. [blog] https://yurisk.info/2022/08/08/Fortigate-free-VM-Evaluation-License-is-now-permanent-not-15-days/
- One evaluation per FortiCloud account. The license is bound to the VM instance that requested it. If the VM is lost,
  a new request fails with "Error downloading license: invalid serial number" (CLI: "Forticare response error 61")
  until the old unit is **decommissioned** in FortiCloud Asset Management. [KB] https://community.fortinet.com/t5/FortiGate/Technical-Tip-Requesting-a-new-FortiGate-evaluation-license/ta-p/364440
- Download the **FortiGate** "New deployment" image. The FortiFirewall-VM image or the "Upgrade" image will not
  accept the trial. [forum] https://community.fortinet.com/support-forum-92/fortinet-trials-am-i-missing-something-227695 ·
  [forum] https://community.fortinet.com/t5/Support-Forum/Evaluation-license/td-p/392759

### Which FortiOS versions
- The permanent trial started with **FortiOS 7.2.1** and replaced the 15-day evaluation. 7.2.0 and earlier still carry
  the 15-day license. [doc] https://docs.fortinet.com/document/fortigate/7.2.0/new-features/007398/permanent-trial-mode-for-fortigate-vm-7-2-1
- The same "Permanent trial mode" page exists for 7.4.x, 7.6.x and 8.0.0, with the same limits. [doc]
  https://docs.fortinet.com/document/fortigate/8.0.0/administration-guide/441460/permanent-trial-mode-for-fortigate-vm
- Current VM builds listed in the release notes include FG-VM64 (VMware), FG-VM64-KVM, FG-VM64-HV (Hyper-V),
  FG-VM64-XEN and **FG-ARM64-KVM** (7.4.9 and 7.6.6). [doc] https://docs.fortinet.com/document/fortigate/7.6.6/fortios-release-notes/519763/fortigate-vm-firmware ·
  https://docs.fortinet.com/document/fortigate/7.4.9/fortios-release-notes/519763/fortigate-vm-firmware

### All documented limits (7.6.6 admin guide, verbatim list)
| Limit | Value | Source |
|---|---|---|
| Copies | "Maximum of one free evaluation copy per FortiCloud account" | [doc] 7.6.6 page above |
| Crypto | "Support for low encryption operation only, except for GUI management access and FortiManager communications" | [doc] |
| CPU / RAM | "Maximum of 1 CPU and 2 GB of memory" | [doc] |
| Interfaces, policies, routes | "Maximum of three interfaces, firewall policies, and routes" | [doc] |
| Support | "No FortiCare support", "No FortiGuard support" | [doc] |
| VDOMs | "maximum of two virtual domains (VDOM)", root must be admin type | [doc] |
| Factory cert | Fortinet_Factory has CN = FortiGate, so the trial cannot connect to FortiManager | [KB] https://community.fortinet.com/customer-service-42/customer-service-tip-free-trial-licenses-available-for-fortinet-products-225800 |
| More vCPUs than allowed | "License is invalid for current VM configuration" | [KB] https://community.fortinet.com/fortigate-3/troubleshooting-tip-license-is-invalid-for-current-vm-configuration-upload-a-new-license-or-reconfigure-the-vm-102882 |

Undocumented limits: VPN tunnel count, local user count, and whether tunnel interfaces or zones count toward the
three-interface cap are **not publicly documented**. One blogger found the interface cap counts disabled interfaces
and loopbacks, and that the route cap was not enforced on 7.2.1. [blog] https://yurisk.info/2022/08/08/Fortigate-free-VM-Evaluation-License-is-now-permanent-not-15-days/ [trace]

VMs are exempt from the "no proxy features on 2 GB models" rule of 7.4.4+, though 4 GB is recommended. Not relevant to
IPsec, noted only so the 2 GB cap is not blamed wrongly. [doc] https://docs.fortinet.com/document/fortigate/7.4.4/fortios-release-notes/768039/2-gb-ram-fortigate-models-no-longer-support-fortios-proxy-related-features

### What "low encryption" means for IKEv2 AES/SHA2
- Fortinet's definition for LENC devices: they "cannot use or inspect high encryption protocols, such as 3DES and AES"
  and "only use 56-bit DES encryption to work with Agentless VPN and IPsec VPN". [doc] https://docs.fortinet.com/document/fortigate/7.6.6/administration-guide/721455/low-encryption-models
  · [KB] https://community.fortinet.com/t5/FortiCache/Technical-Tip-Low-Encryption-LENC-device-FAQ/ta-p/190323
  The trial page does not say the trial **is** a LENC model, only that it supports "low encryption operation only".
  The practical effect below comes from user reports. [inference]
- On a trial VM, `set proposal ?` in phase2-interface offered only: `null-md5 null-sha1 null-sha256 null-sha384
  null-sha512 des-null des-md5 des-sha1 des-sha256 des-sha384 des-sha512`. No AES, no 3DES, no GCM, no ChaCha20.
  [forum] (June 2026) https://community.fortinet.com/support-forum-92/fortigate-site-2-site-ipsec-vpn-confiuration-with-cisco-router-don-t-waste-time-if-you-are-using-trail-license-228210
- Another trial user: "The only encryption I can choose is either DES or NULL on the server side." The FortiGate's
  own proposal in the debug used ESP_DES with MD5/SHA1 and PFS DH groups 14, 2 and 1, so MODP group 14 was accepted.
  FortiClient offered only 3DES/AES and got "no SA proposal chosen". [forum] https://community.fortinet.com/support-forum-92/forticlient-vpn-does-not-negotiate-des-159848
- The phase1 (IKE SA) proposal list on a trial was not shown in any source found. It is very likely DES-only too, but
  that is **not publicly documented**. [trace]
- Integrity/PRF with SHA2 appears to remain available (`des-sha256` etc.). Whether ECP groups (19, 20, 21) are allowed
  on the trial is **not publicly documented**. [trace]
- Standards view: RFC 8247 lists ENCR_DES as **MUST NOT** for IKEv2 ("provides no meaningful security whatsoever").
  [doc] https://www.rfc-editor.org/rfc/rfc8247.txt · RFC 8221 lists ENCR_DES as MUST NOT for ESP.
  [doc] https://www.rfc-editor.org/rfc/rfc8221.txt · IANA marks transform 2 ENCR_DES as DEPRECATED.
  [doc] https://www.iana.org/assignments/ikev2-parameters/ikev2-parameters.xhtml
- Android's platform IKE API (`android.net.ipsec.ike.SaProposal`) offers 3DES, AES-CBC, AES-CTR, AES-GCM-8/12/16 and
  ChaCha20-Poly1305, and no DES. Its DH constants are MODP 1024/1536/2048/3072/4096 and Curve25519. [doc]
  https://developer.android.com/reference/android/net/ipsec/ike/SaProposal
- Blog summary of the older 15-day trial, same crypto rule: "only DES is enabled as algorithm", and IPsec "including
  Forticlient dial-up, will come up just fine with DES". [blog] https://yurisk.info/2021/02/28/fortigate-vm-evaluation-license-15-days-limitations/

### Is dial-up IPsec with EAP user auth allowed on the trial?
- No Fortinet source says dial-up IPsec or EAP is disabled on the trial. The documented limits are crypto, sizing and
  support only. [doc] trial page above
- Users report IPsec remote access working on a trial once both sides use DES. [forum] https://community.fortinet.com/support-forum-92/fortigate-evaluation-licence-is-not-working-for-ssl-vpn-and-ipsec-201922
  · [blog] yurisk 2021 above
- So: allowed, but only with DES/NULL proposals, three firewall policies, and three interfaces. [inference] [trace]
- EAP-MSCHAPv2 does not need TLS, so it should be unaffected. EAP-TTLS runs TLS on the FortiGate's internal EAP server
  using the `wifi-certificate`. Whether low-encryption mode limits that TLS is **not publicly documented**. [trace]

---

## 3. Other license routes (when you need AES)
- **60-day evaluation from sales**: "request an evaluation license, which is an enhanced version of a trial license that
  removes the basic trial limitations and also includes technical support". [KB] https://community.fortinet.com/customer-service-42/customer-service-tip-free-trial-licenses-available-for-fortinet-products-225800
  · Yuri: the 60-day license "has almost NO limitations". [blog] https://yurisk.info/2021/02/28/fortigate-vm-evaluation-license-15-days-limitations/
- **Fortinet 30-day FortiGate-VM trial for public cloud** (form on fortinet.com, mentions AWS, Azure, GCP, OCI).
  The page lists no crypto limits. [doc] https://www.fortinet.com/offers/fortigate-vm-trial
- **AWS Marketplace PAYG** (section 4.4): license included, 30-day free trial of the software fee.
- **BYOL cloud image + permanent trial**: allowed ("all BYOL public cloud instances"), but still low encryption, so no
  gain over the local VM except a public IP. [doc] trial page above

---

## 4. Images, hypervisors, Apple Silicon, cloud

### 4.1 Where images come from
- FortiGate-VM deployment packages are on the Customer Service & Support site (support.fortinet.com): Download ->
  VM Images -> Product FortiGate -> Platform (e.g. KVM) -> version. There is an "upgrade" file and a "new deployment"
  file. An account login is required. [doc] https://docs.fortinet.com/document/fortigate-private-cloud/8.0.0/kvm-administration-guide/961760/downloading-the-fortigate-vm-deployment-package
- A free FortiCloud account is enough to reach VM Images. Fortinet staff: "You have to download the image and the
  license from the Customer portal. We can't share firmware on the community or via mail." [forum] https://community.fortinet.com/support-forum-92/need-to-have-image-of-fortigate-vm-for-gns3-trial-evaluation-without-purchasing-172980
- Older claim (2021): without a support contract you can download only the **latest** VM image; with a contract, any
  version. [blog] https://yurisk.info/2021/02/28/fortigate-vm-evaluation-license-15-days-limitations/
  Current state for free accounts is **not documented by Fortinet**. [open question]
- KVM package: `FORTINET.out.kvm.zip` contains `fortios.qcow2`. You add a log disk yourself. [doc]
  https://docs.fortinet.com/document/fortigate-private-cloud/8.0.0/kvm-administration-guide/42217/deployment-package-contents
- ARM64 KVM package name example: `FGT_ARM64_KVM-v7.4.*.M-build27**-FORTINET.out.kvm.zip`. [KB]
  https://community.fortinet.com/t5/FortiGate/Technical-Tip-How-to-create-FortiGate-VM-in-MacOS/ta-p/361722

### 4.2 Hypervisors
- VM builds: VMware ESXi (FG-VM64), KVM (FG-VM64-KVM), Hyper-V (FG-VM64-HV), Xen (FG-VM64-XEN), ARM64 KVM
  (FG-ARM64-KVM), plus cloud builds (AWS, Azure, GCP, OCI, Alibaba, IBM) including ARM64 for AWS, Azure, GCP and OCI.
  [doc] https://docs.fortinet.com/document/fortigate/7.6.6/fortios-release-notes/519763/fortigate-vm-firmware
- ARM64 KVM has been supported since 7.0.1: libvirt import, Architecture aarch64, Machine Type virt. [doc]
  https://docs.fortinet.com/document/fortigate/7.0.0/new-features/564436/fortigate-vm-on-kvm-running-arm-processors-7-0-1

### 4.3 Apple Silicon Mac
- **ARM64 image, native**: Fortinet KB (Dec 2024) walks through UTM: choose "Virtualize" for best performance, "Other",
  no boot device, set CPU and memory "according to the VM license", delete UTM's default VirtIO drive and import
  `fortios.qcow2`, add a Serial device for the console. "Once the license is uploaded, the FortiGate VM will function
  properly." [KB] https://community.fortinet.com/t5/FortiGate/Technical-Tip-How-to-create-FortiGate-VM-in-MacOS/ta-p/361722
- UTM runs ARM64 guests through Apple's Hypervisor framework "at near native speeds", and offers "lower performance
  emulation" of x86/x64 on Apple Silicon. [doc] https://mac.getutm.app/
- x86 emulation on Apple Silicon: UTM uses one core for x86_64 guests because "emulating multiple x86_64 cores on an
  ARM64 system will be done on a single core and thus reduce performance". [doc] https://docs.getutm.app/guides/windows/
  The trial allows only 1 vCPU anyway, so single-core emulation is functionally fine. Expect slow boot and CPU-bound
  crypto, which is acceptable for low-rate IKE testing. [inference] [trace]
- Earlier user reports (2024) were mixed: ARM KVM image in UTM "was not working at full performance", and one user got
  it working only with the hypervisor disabled (emulation), "but i warn u its slow". [forum]
  https://community.fortinet.com/t5/Support-Forum/Struggle-with-macos-m1-Fortigate-VM/td-p/325775
- Unknown: whether `execute vm-license` (permanent trial) is accepted on FG-ARM64-KVM. The trial page says "all private
  cloud (VMware ESXi, KVM, and so on)" but never names ARM64. [open question] [trace]
- UTM networking: "Shared Network" lets guest and host see each other; "Host Only" blocks WAN (the trial needs WAN once,
  to activate); "Bridged" puts the VM on the LAN, which is how a physical phone on the same Wi-Fi would reach it.
  [doc] https://docs.getutm.app/settings-qemu/devices/network/network/

### 4.4 Cloud options and cost
- **AWS x86 PAYG** ("Fortinet FortiGate VM Next-Generation Firewall"): 30-day free trial "according to the free trial
  terms set by the vendor", then usage pricing. It auto-converts to paid unless cancelled. Software price is $0.36/h on
  t2.small (smallest listed) and $1.02/h on the recommended c6in.xlarge. Latest version shown: 8.0.1. Infrastructure
  is billed separately. [doc] https://aws.amazon.com/marketplace/pp/prodview-wory773oau6wq
- **AWS ARM64/Graviton PAYG**: same 30-day free trial. $0.36/h on t4g.medium, c6g.medium and c6gn.medium. Version 8.0.1.
  [doc] https://aws.amazon.com/marketplace/pp/prodview-ohcnwr7nr2icy
- EC2 on-demand reference prices: t2.small (1 vCPU, 2 GiB) $0.023/h. [doc] https://aws.amazon.com/ec2/instance-types/t2/
  · t3.small (2 vCPU, 2 GiB) $0.0209/h. [doc] https://aws.amazon.com/ec2/instance-types/t3/
- AWS credits: new accounts get up to $200 (100 at sign-up + 100 earned). The free plan lasts 6 months. [doc]
  https://aws.amazon.com/about-aws/whats-new/2025/07/aws-free-tier-credits-month-free-plan/
  The **free account plan** excludes "certain AWS Marketplace offers that can incur charges", so you must upgrade to the
  paid plan to subscribe. [doc] https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/free-tier-plans.html
  Promotional credits are not applied to AWS Marketplace fees. [doc] https://aws.amazon.com/awscredits/
  So during the 30-day software trial the credits can cover the EC2 instance. After it, the $0.36/h software fee is
  real money. [inference]
- Rough cost (inference): software fee after the trial, left on 24/7: 0.36 x 730 h ≈ $263/month. Run only 40 h/month:
  ≈ $14 software + about $1 EC2. During the 30-day trial, t2.small 24/7 is about $17 EC2, which credits can cover.
  [inference, from the prices above]
- **Azure**: $200 credit for 30 days, which "can't be applied to Azure Marketplace offers". [doc]
  https://learn.microsoft.com/en-us/azure/cost-management-billing/manage/create-free-services
  The FortiGate PAYG listing advertises a 30-day free trial (listing page returned 403 to the fetcher, seen only in a
  search snippet). [low confidence] https://marketplace.microsoft.com/en-us/product/fortinet.fortinet_fortigate-vm
- **Google Cloud**: $300 free trial credit, but a free-trial billing account "can't use Google Cloud Marketplace" until
  upgraded. [doc] https://docs.cloud.google.com/free/docs/free-cloud-features
- A cloud gateway also gives a **public IP**, which is the only way to test real carrier NAT and UDP-blocking networks
  from the phone on mobile data. [inference]

---

## 5. FortiToken trial tokens and email two-factor

### FortiToken Mobile
- "Each FortiGate comes with two free FortiToken Mobile tokens." If absent, import them (the FortiGate must be
  registered and reach the FortiToken servers):
  `execute fortitoken-mobile import 0000-0000-0000-0000-0000`. [doc]
  https://docs.fortinet.com/document/fortigate/7.6.6/administration-guide/877068/registering-fortitoken-mobile
- They carry an FTMTRIAL license, do not expire, and are tied to that unit through FortiGuard. [KB]
  https://community.fortinet.com/t5/FortiGate/Technical-Tip-Trial-FortiToken-Mobile-in-FortiGate-or/ta-p/193793
- Import bugs (only one token shows) in FortiOS before 7.2.12, 7.4.9, 7.6.5, 8.0.0. [KB]
  https://community.fortinet.com/t5/FortiGate/Technical-Tip-Unable-to-import-trial-FortiToken-Mobile/ta-p/304266
- Whether the permanent-trial VM (which has "No FortiGuard support") can import the two trial tokens is **not publicly
  documented**. On FortiAuthenticator, unlicensed VMs cannot get trial tokens. [forum]
  https://community.fortinet.com/t5/Support-Forum/Unable-to-Get-FortiTokenMobile-free-trial-tokens/td-p/249406 [trace]

### Email OTP for local users
- Configured only in the CLI: `config system email-server` (server, port, auth, security), then per user
  `set two-factor email` + `set email-to <addr>`. The OTP is time-based, six digits, every 60 s by default. NTP is
  recommended. Tune `set two-factor-email-expiry 300` and `set remoteauthtimeout 300` under `config system global`.
  [KB] https://community.fortinet.com/t5/FortiGate/Technical-Tip-Email-Two-Factor-Authentication-on-FortiGate/ta-p/194890
- No license is needed for email delivery. You are only limited by the maximum number of local users. [forum, Fortinet
  staff] https://community.fortinet.com/support-forum-92/licences-for-email-2fa-117494
- Fortinet lists Email/SMS as a valid MFA method for IKEv2 dial-up with local users: "User enters OTP on FortiClient,
  similar to FortiToken use cases." [KB] https://community.fortinet.com/fortigate-3/technical-tip-fortios-ikev2-dial-up-vpn-user-and-multi-factor-authentication-resources-220170
  · IKEv2 + local users: "Any method on FortiGate". [KB] https://community.fortinet.com/t5/FortiGate/Technical-Tip-Overview-of-compatible-IKE-versions-user/ta-p/420733

### The catch for a third-party client
- "FortiGate triggering MFA prompts for IKEv2 Dialup Gateway clients relies on proprietary EAP extensions. It is only
  supported when FortiClient is used." And: "Manual OTP code entry or FortiToken mobile push for other VPN clients is
  not supported." [KB] https://community.fortinet.com/fortigate-3/technical-tip-required-firmware-software-versions-for-using-fortitoken-mobile-or-otp-mfa-with-fortigate-ikev2-dialup-ipsec-219452
  The format of that extension is **not publicly documented**, so it is out of bounds for the clean-room engine.
- Documented workaround (FortiToken, local users): put the code after the password (`p@ssw0rd345678`). fnbamd then logs
  "2fa code has already been verified in concatenated password". Without it the log shows `FNBAM_NEED_TOKEN` and
  "EAP requires token for user". [KB] https://community.fortinet.com/fortigate-3/technical-tip-ipsec-dial-up-tunnel-using-ikev2-with-fortitoken-2fa-for-local-users-201395
- Open: with **email** OTP the code is only emailed after the first factor passes, so the client cannot know it before
  the first attempt. Whether a failed first EAP attempt still triggers the email, so a second attempt can send
  password+code, is **not documented**. [trace] This matters because the company gateway uses emailed codes.
- Raise `negotiate-timeout` (default 30 s, 1 to 300) when OTP entry is involved. [KB] https://community.fortinet.com/fortigate-3/technical-tip-fortios-ikev2-eap-user-authentication-operation-217759

---

## 6. Minimal configuration (documented)

### 6.1 The documented example (FortiOS 7.6.4 admin guide, "Dialup IPsec VPN using custom TCP port")
Source: [doc] https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/567401/dialup-ipsec-vpn-using-custom-tcp-port

Context from the page: "FortiGate is configured as a dialup IPsec server using IKE version 2 (IKEv2) and operating on a
custom TCP port (5500). IKEv2 is configured to use EAP for user authentication." "The custom TCP port functionality for
IPsec is exclusively supported with IKE version 2 (IKEv2), and does not support NPU offloading." Quoted CLI:

```
config user local
 edit "ipsec"
 set type password
 set passwd *****
 next
end

config user group
 edit "IPSEC"
 set member "ipsec"
 next
end

config system interface
 edit "port3"
 set vdom "root"
 set ip 10.100.55.1 255.255.255.0
 set type physical
 set alias "internal"
 next
end
config firewall address
 edit "internal network"
 set subnet 10.10.111.0 255.255.255.0
 next
end
config firewall addrgrp
 edit "v2_psk-120_split"
 set member "internal network"
 next
end

config system interface
 edit "port1"
 set vdom "root"
 set ip 10.152.35.150 255.255.255.0
 set type physical
 set alias "wan1"
 next
end
config router static
 edit 1
 set gateway 10.152.35.151
 set device "port1"
 next
end

config vpn ipsec phase1-interface
 edit "v2_psk-120"
 set type dynamic
 set interface "port1"
 set ike-version 2
 set peertype any
 set net-device disable
 set mode-cfg enable
 set ipv4-dns-server1 8.8.8.8
 set proposal aes128-sha256 aes256-sha256 aes128gcm-prfsha256 aes256gcm-prfsha384 chacha20poly1305-prfsha256
 set dhgrp 20 21
 set eap enable
 set eap-identity send-request
 set authusrgrp "IPSEC"
 set transport tcp
 set fortinet-esp disable
 set ipv4-start-ip 9.5.6.7
 set ipv4-end-ip 9.5.6.70
 set ipv4-split-include "v2_psk-120_split"
 set save-password enable
 set client-auto-negotiate enable
 set client-keep-alive enable
 set psksecret *******
 next
end

config vpn ipsec phase2-interface
 edit "v2_psk-120"
 set phase1name "v2_psk-120"
 set proposal aes128-sha1 aes256-sha1 aes128-sha256 aes256-sha256 aes128gcm aes256gcm chacha20poly1305
 set dhgrp 20 21
 next
end

config firewall policy
 edit 1
 set name "vpn_v2_psk-120_local_allow"
 set srcintf "vpn_v2_psk-120_zone"
 set dstintf "port3"
 set action accept
 set srcaddr "v2_psk-120_range"
 set dstaddr "internal network"
 set schedule "always"
 set service "ALL"
 set nat enable
 next
end
```
Port part of the same page: `show full-configuration system settings | grep ike-tcp` shows `set ike-tcp-port 443`
("Notice the setting ike-tcp-port set to 443 by default"), then:
```
config system settings
 set ike-tcp-port 5500
end
```
and, for the 443 conflict with the admin GUI:
```
config system global
 set admin-sport <port>
end
```
Verification quoted from the page: `diagnose vpn ike gateway list` shows `transport: TCP`, `eap-user: ipsec`,
`assigned IPv4 address: 9.5.6.7/255.255.255.255`, `proposal: aes256-sha256`. Then
`diagnose sniffer packet wan1 "port 5500" 4 0 l`. The page recommends `transport auto` in practice.

### 6.2 Same pattern on TCP 443 (7.6.6 "SSL VPN tunnel mode to IPsec VPN migration", Example 2, split tunnel)
Source: [doc] https://docs.fortinet.com/document/fortigate/7.6.6/administration-guide/155142/ssl-vpn-tunnel-mode-to-ipsec-vpn-migration
```
config vpn ipsec phase1-interface
 edit "split-dns"
 set type dynamic
 set interface "wan1"
 set ike-version 2
 set authmethod psk
 set peertype any
 set net-device disable
 set mode-cfg enable
 set ipv4-dns-server1 10.10.10.8
 set ipv4-dns-server2 10.10.10.9
 set ipv4-dns-server3 10.10.10.10
 set internal-domain-list "domain1.com"
 set proposal aes128-sha256 aes256-sha256 aes128gcm-prfsha256 aes256gcm-prfsha384 chacha20poly1305-prfsha256
 set eap enable
 set eap-identity send-request
 set authusrgrp "group-split-dns"
 set network-overlay enable
 set network-id 3
 set transport tcp
 set psksecret *****
 set assign-ip-from name
 set ipv4-split-include "Local-LAN"
 set ipv4-name "REMOTE-CLIENT-ADDRESS-RANGE"
 set save-password enable
 set client-auto-negotiate enable
 set client-keep-alive enable
 next
end
...
Default port number when TCP is used as transport:
config system settings
 set ike-tcp-port 443
end
```
The same page: "This configuration uses TCP port 443 by default", TCP transport needs FortiOS 7.4.2+ and FortiClient
7.4.1+. The user group must be in phase1 **or** the policy, not both, or traffic will not flow. In IKEv2, FortiClient
sends a Network ID that FortiGate matches to pick among several dial-up tunnels on one interface. IKEv2 dial-up
supports split DNS. IKEv1 supports only a DNS suffix. [doc]

### 6.3 Version differences that change the bench
- 7.4.3 docs: `ike-tcp-port` default = **4500**, feature "only works with IKE version 2", no ADVPN. [doc]
  https://docs.fortinet.com/document/fortigate/7.4.3/administration-guide/351073/encapsulate-esp-packets-within-tcp-headers
- 7.6.3 docs: default = **443**. If the port is not 4500, "the IKE daemon listens on port 4500 and port 11443 while
  traffic enters on the ike-tcp-port and redirects to port 11443". [doc]
  https://docs.fortinet.com/document/fortigate/7.6.3/administration-guide/351073/encapsulate-esp-packets-within-tcp-headers
- 7.6.4 docs contradict each other (ESP-in-TCP page says 4500, custom-port page shows 443). Check with
  `show full-configuration system settings | grep ike-tcp`. [doc] [trace]
  https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/351073/encapsulate-esp-packets-within-tcp-headers
- `transport {auto | udp | tcp}` and `fortinet-esp` (must stay **disable** for dial-up and third-party peers; enable
  means "non-standard TCP headers"). `fallback-tcp-threshold` 1 to 300, default 15 s. [doc] same 7.6.4 page
- **8.0**: TCP is enabled per VDOM: `config system settings` / `set ike-tcp-service enable` (default disabled) /
  `set ike-tcp-port` (default 443). Phase1 `transport {auto | udp}` exists only for static/ddns tunnels. "When
  ike-tcp-service is enabled, dialup VPNs configured in the VDOM will behave as the Auto transport option". [doc]
  https://docs.fortinet.com/document/fortigate/8.0.0/administration-guide/351073/encapsulate-esp-packets-within-tcp-headers
  · https://docs.fortinet.com/document/fortigate/8.0.0/administration-guide/567401/dialup-ipsec-vpn-using-custom-tcp-port
  · https://docs.fortinet.com/document/fortigate/8.0.0/new-features/428828/tls-1-3-based-vpn-over-tcp
- 8.0 also adds `ike-tls-service` (IKE and ESP over TLS 1.3). It is FortiGate to FortiGate only. "FortiClient
  endpoints do not currently support TLS based VPN over TCP." [doc] same TLS page. Not needed for the client. [inference]
- Standard reference for the TCP framing: RFC 9329 (obsoletes RFC 8229). The TCP originator sends the "IKETCP" stream
  prefix once, and implementations "MUST support TCP encapsulation on TCP port 4500". [doc]
  https://www.rfc-editor.org/rfc/rfc9329.txt · https://www.rfc-editor.org/rfc/rfc8229.txt
- A debug line seen when a TCP client connects: `ike V=root:accepts ike tcp-transport(... x.x.x.x:4500->y.y.y.y:10670
  ...)` followed by `IKEv2 exchange=SA_INIT`. [forum] https://community.fortinet.com/support-forum-92/dialup-ipsec-over-tcp-with-forticlient-vpn-a-gotcha-221477

### 6.4 Adapting the example to the free trial VM (inference, not documented)
- Interfaces: port1 = WAN, port2 = LAN, plus the tunnel. Do **not** tick "Create and add interface to zone". Point the
  policy at the tunnel name, like the migration example does. Use no loopback. That stays within 3 interfaces if the
  tunnel counts as one. [inference] [trace]
- Policies: 1 (tunnel -> LAN), maybe 2 (tunnel -> WAN for full-tunnel tests). Limit is 3. [inference]
- Proposals: the trial will likely only accept DES-based suites. Try `set proposal des-sha256` and `set dhgrp 14` in
  phase1, and `set proposal des-sha256` in phase2. The engine then needs a **lab-only** DES transform (IANA ID 2), which
  RFC 8247 forbids. Keep it behind a debug build flag, or skip the trial for crypto testing. [inference] [trace]
- TCP 443: `set admin-sport 8443` first, then `set ike-tcp-port 443`, then `transport tcp` (7.4/7.6) or
  `ike-tcp-service enable` (8.0). [doc for the knobs, inference for the order]
- One dial-up tunnel per WAN interface avoids Network ID selection, whose on-wire encoding is not in these docs.
  [inference]
- Server authentication: Fortinet's FortiClient examples use a **PSK** for the gateway plus EAP for the user. RFC 7296
  §2.16 says EAP "MUST be used in conjunction with a public-key-signature-based authentication of the responder to the
  initiator". A second bench profile should use `set authmethod signature` + `set certificate <local cert>` + EAP, as
  in Fortinet's cert+EAP example, with `eap-cert-auth disable` when the client has no certificate. [doc]
  https://www.rfc-editor.org/rfc/rfc7296.txt · https://docs.fortinet.com/document/fortigate/7.6.6/administration-guide/298520/ipsec-ikev2-vpn-2fa-with-eap-and-certificate-authentication
  [inference for the combination] [trace]
- EAP method: FortiClient's default is EAP-MSCHAPv2. The FortiOS internal EAP server "does support other EAP methods",
  and third-party clients "may authenticate successfully" but are "outside the scope". EAP-TTLS terminates on the
  FortiGate's internal RADIUS using `wifi-certificate` (default `Fortinet_Wifi`). [KB]
  https://community.fortinet.com/fortigate-3/technical-tip-fortios-ikev2-eap-user-authentication-operation-217759

---

## 7. Capturing traces

### 7.1 FortiGate IKE debug
- Filter first, then debug (7.4.1+ syntax):
  ```
  diagnose vpn ike log filter clear
  diagnose vpn ike log filter rem-addr4 <client public IP>
  diagnose debug application ike -1
  diagnose debug console timestamp enable
  diagnose debug enable
  ...
  diagnose debug disable
  diagnose debug reset
  ```
  Before 7.4.1 it was `diagnose vpn ike log-filter dst-addr4`. Filters persist across sessions, so always `clear`
  first. Output stops after 30 minutes by default. 7.6.3+ can run it from the GUI ("CLI diagnostics" on a tunnel).
  [KB] https://community.fortinet.com/t5/FortiGate/Troubleshooting-Tip-IPsec-Tunnel-debugging-IKE/ta-p/190052
- `-1` = all levels. Individual bits: error 0x01, config 0x02, negotiate 0x04, debug 0x08, keepalive 0x10, dpd 0x20,
  **keys 0x40**, packet 0x80, SLBC 0x100. [KB] same URL
- The output includes whole packets in hex ("in ..." / "out ...") and, for encrypted messages, the **decrypted**
  payload ("dec ..."). [KB] same URL · https://community.fortinet.com/t5/FortiGate/Technical-Tip-Understanding-IPsec-iked-debug-logs/ta-p/256321
- For EAP and user auth add `diagnose debug application fnbamd -1` and `diagnose debug application eap_proxy -1`.
  For email OTP add `alertmail -1`. [KB] https://community.fortinet.com/fortigate-3/technical-tip-fortios-ikev2-eap-user-authentication-operation-217759
  · https://community.fortinet.com/t5/FortiGate/Technical-Tip-Email-Two-Factor-Authentication-on-FortiGate/ta-p/194890
- Take the debug with the FortiGate as **responder** (client initiates). [KB] https://community.fortinet.com/t5/FortiGate/Technical-Tip-Understanding-IPsec-iked-debug-logs/ta-p/256321

### 7.2 FortiGate state and key dumps
- `diagnose vpn ike status`, `diagnose vpn ike gateway list [name <tunnel>_0]`, `diagnose vpn tunnel list`,
  `diagnose vpn ipsec status`. [doc] https://docs.fortinet.com/document/fortigate/8.0.0/administration-guide/44240/ipsec-related-diagnose-commands
- `diagnose vpn ike gateway list` prints the IKE SA keys **SK_ei, SK_er, SK_ai, SK_ar**, plus eap-user, FortiClient
  UID, assigned IP, transport and proposal. `diagnose vpn tunnel list` prints the ESP **enc/dec keys** per SPI.
  [doc] same URL
- These are exactly what Wireshark needs: the ISAKMP "IKEv2 decryption table" takes SPIs + SK_ei/SK_er/SK_ai/SK_ar as
  hex, and the ESP preference "ESP SAs" takes the ESP keys. [doc] https://www.wireshark.org/docs/wsug_html_chunked/ChIKEv2DecryptionSection.html
  · https://wiki.wireshark.org/ESP_Preferences

### 7.3 FortiGate packet capture
- CLI: `diagnose sniffer packet <interface|any> '<filter>' <verbose 1-6> <count> <a|l>`. Level 3 or 6 = full Ethernet
  frame with data. 4 to 6 add the interface name. Capture the terminal to a file. [doc]
  https://docs.fortinet.com/document/fortigate/7.6.5/administration-guide/680228/performing-a-sniffer-trace-or-packet-capture
- GUI: Network > Diagnostics > Packet Capture, with an advanced BPF filter, then "Save as pcap". CLI control:
  `config firewall on-demand-sniffer` + `diagnose on-demand-sniffer start|stop`. Without a disk, captures are deleted 24
  h after completion or on reboot. [doc] https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/462154/using-the-packet-capture-tool
- Useful filters: `'udp port 500 or udp port 4500'`, `'tcp port 443'` (or the chosen ike-tcp-port), and the inner
  tunnel interface (e.g. `v2_psk-120_0`) for decrypted traffic. [inference from the syntax above]

### 7.4 Client side (Android)
- Emulator 36.5+: Wi-Fi traffic goes through netsim. Capture with `emulator -netsim-args="--pcap"`. Files land in the
  `pcap` subfolder of `$ANDROID_TMP/android-$USER/netsimd/`, one per radio. [doc]
  https://developer.android.com/studio/run/emulator-networking-advanced
- Emulator console `network capture start <file>` / `stop <file>` now only captures legacy cellular/WAN traffic through
  the QEMU slirp stack. Files go to `~/.android/avd/<name>.avd/console_out/`. [doc] https://developer.android.com/studio/run/emulator-console
- The emulator reaches the host's loopback as 10.0.2.2 and sits behind its own virtual router (10.0.2.0/24), so the
  gateway sees a NATed client. That is good for NAT-T tests. [doc] https://developer.android.com/studio/run/emulator-networking-address
- Root (for on-device tcpdump or reading logs) is possible only on AOSP images without Google Play. Play images are
  release-signed and cannot `adb root`. [doc] https://developer.android.com/studio/run/managing-avds
- Physical phone (not rooted): capture on the FortiGate side or on the Mac if the Mac routes the phone's traffic.
  [inference]
- Mac host capture works for either: `tcpdump -i <UTM bridge/vmnet interface> -w bench.pcap 'udp port 500 or udp port
  4500 or tcp port 443'`. [doc for flags] https://www.tcpdump.org/manpages/tcpdump.1.html [inference for the interface]
- The engine's own logs can record message types, SPIs, transform IDs, notify types and timings, which is enough to
  line up with the FortiGate debug. [inference]

### 7.5 What is safe to record
Treat every raw trace as secret until redacted. Keep it in a git-ignored folder, as the project already does for
signing keys. Use throwaway lab credentials only. Never reuse the company password or PSK on the bench.

| Artifact | Contains | Rule |
|---|---|---|
| `diagnose vpn ike gateway list` | SK_ei/er/ai/ar, eap-user, FortiClient UID | Lab only. Redact the SK_* lines before sharing or committing. [doc] 8.0 diagnose page |
| `diagnose vpn tunnel list` | ESP enc/auth keys per SPI | Same. [doc] same |
| `diagnose debug application ike -1` | full packets, decrypted payloads ("dec"), "keys" level | Contains EAP payloads and identities. Redact. Assume key material may appear (level 0x40 is named "keys"). [KB] 190052 |
| EAP-MSCHAPv2 exchange (decrypted) | challenge + NT-Response derived from the password hash | Enough for an offline guess of the password. Never publish. [doc] https://www.rfc-editor.org/rfc/rfc2759.txt (GenerateNTResponse / NtPasswordHash) |
| fnbamd / eap_proxy / alertmail debug | usernames, auth results, OTP handling | Redact usernames and any codes. [KB] 194890, 217759 |
| `show vpn ipsec phase1-interface`, `show user local` | `set psksecret ENC ...`, `set passwd ENC ...` | Strip before sharing configs. [KB] 256321 shows `set psksecret ENC KEY` |
| `execute vm-license-options account-password` | FortiCloud password in the CLI session | Type it once. Do not paste the session log anywhere. [doc] trial page |
| pcap (outer) | public IPs, IKE SPIs, encrypted payloads | Fine to keep. Encrypted payloads are safe without the SK_* keys. Rewrite public IPs before sharing. [inference] |
| pcap + key table together | full plaintext of IKE and ESP | Lab only. Never commit. [inference] |

Clean-room note: a live trace is a black-box observation, so it is allowed input. Record in `docs/protocol/PROVENANCE.md`
that a behaviour came from a FortiGate trace (version, date), not from any implementation. [inference, per CLAUDE.md]

---

## 8. Open questions (all need a live trace or a Fortinet answer)
1. Phase1 proposal list on the permanent trial: DES only? Are SHA2 PRFs and ECP groups 19/20/21 offered?
2. Does the trial's three-interface cap count the dial-up tunnel interface, per-client instances, or a VPN zone?
3. Does `execute vm-license` activate the permanent trial on **FG-ARM64-KVM** under UTM "Virtualize"?
4. Can a free FortiCloud account download any FortiOS version, or only the latest?
5. Can the trial VM import the two free FortiToken Mobile tokens without FortiGuard entitlement?
6. Email OTP with a third-party client: does a failed first EAP-MSCHAPv2 attempt send the email, and does a second
   attempt with password+code (concatenated) succeed, as documented for FortiToken?
7. Actual `ike-tcp-port` default on the version we deploy (docs disagree for 7.6.4). Also: does the TCP listener on
   443 speak plain RFC 9329 framing (IKETCP prefix) when `fortinet-esp disable`?
8. Does low-encryption mode affect EAP-TTLS (TLS on the internal EAP server)?
9. On-wire encoding of FortiClient's Network ID and FCT-UID (seen as "received FCT-UID" in debug) is not publicly
   documented. Is either one required for a single dial-up tunnel? (Expected: no.)
10. Is a PSK-authenticated responder + EAP (Fortinet's default, outside RFC 7296 §2.16) the only mode the company gateway
    offers? That decides whether the engine must support it.

---

## Sources (all opened on 2026-09-28)
- Fortinet docs: permanent trial 7.6.6 https://docs.fortinet.com/document/fortigate/7.6.6/administration-guide/441460/permanent-trial-mode-for-fortigate-vm
  · 7.2.1 new feature https://docs.fortinet.com/document/fortigate/7.2.0/new-features/007398/permanent-trial-mode-for-fortigate-vm-7-2-1
  · 8.0.0 https://docs.fortinet.com/document/fortigate/8.0.0/administration-guide/441460/permanent-trial-mode-for-fortigate-vm
  · low encryption models https://docs.fortinet.com/document/fortigate/7.6.6/administration-guide/721455/low-encryption-models
  · KVM download https://docs.fortinet.com/document/fortigate-private-cloud/8.0.0/kvm-administration-guide/961760/downloading-the-fortigate-vm-deployment-package
  · KVM package contents https://docs.fortinet.com/document/fortigate-private-cloud/8.0.0/kvm-administration-guide/42217/deployment-package-contents
  · ARM KVM https://docs.fortinet.com/document/fortigate/7.0.0/new-features/564436/fortigate-vm-on-kvm-running-arm-processors-7-0-1
  · VM firmware list https://docs.fortinet.com/document/fortigate/7.6.6/fortios-release-notes/519763/fortigate-vm-firmware
  · dial-up custom TCP port 7.6.4 https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/567401/dialup-ipsec-vpn-using-custom-tcp-port
  · 8.0.0 https://docs.fortinet.com/document/fortigate/8.0.0/administration-guide/567401/dialup-ipsec-vpn-using-custom-tcp-port
  · ESP in TCP 7.4.3 / 7.6.3 / 7.6.4 / 8.0.0 https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/351073/encapsulate-esp-packets-within-tcp-headers
  · TLS 1.3 VPN over TCP https://docs.fortinet.com/document/fortigate/8.0.0/new-features/428828/tls-1-3-based-vpn-over-tcp
  · SSL VPN to IPsec migration https://docs.fortinet.com/document/fortigate/7.6.6/administration-guide/155142/ssl-vpn-tunnel-mode-to-ipsec-vpn-migration
  · FortiClient as dialup client (IKEv1 example, key dump sample) https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/785501/forticlient-as-dialup-client
  · cert + EAP https://docs.fortinet.com/document/fortigate/7.6.6/administration-guide/298520/ipsec-ikev2-vpn-2fa-with-eap-and-certificate-authentication
  · FortiToken Mobile https://docs.fortinet.com/document/fortigate/7.6.6/administration-guide/877068/registering-fortitoken-mobile
  · sniffer https://docs.fortinet.com/document/fortigate/7.6.5/administration-guide/680228/performing-a-sniffer-trace-or-packet-capture
  · packet capture tool https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/462154/using-the-packet-capture-tool
  · IPsec diagnose commands https://docs.fortinet.com/document/fortigate/8.0.0/administration-guide/44240/ipsec-related-diagnose-commands
  · 2 GB proxy note https://docs.fortinet.com/document/fortigate/7.4.4/fortios-release-notes/768039/2-gb-ram-fortigate-models-no-longer-support-fortios-proxy-related-features
- Fortinet Community KB: 364440, 361722, 190323, 193793, 304266, 194890, 201395, 217759, 219452, 220170, 420733, 190052,
  256321, 225800, 102882 (full URLs inline above).
- Fortinet Community forum threads: 228210, 159848, 201922, 392759, 227695, 172980, 325775, 117494, 249406, 221477.
- fortinet.com: https://www.fortinet.com/offers/fortigate-vm-trial
- IETF/IANA: RFC 7296, RFC 8247, RFC 8221, RFC 9329, RFC 8229, RFC 2759 (rfc-editor.org), IANA IKEv2 parameters.
- Android: SaProposal reference, emulator networking (advanced, address space), emulator console, managing AVDs.
- Cloud vendors: AWS Marketplace listings prodview-wory773oau6wq and prodview-ohcnwr7nr2icy, EC2 t2/t3 pages, AWS Free
  Tier announcement and plans doc, AWS credits page, Microsoft Learn Azure free account, Google Cloud free program.
- Tools: UTM (mac.getutm.app, docs.getutm.app), Wireshark user guide + wiki, tcpdump man page.
- Blog: Yuri Slobodyanyuk, yurisk.info (2021-02-28, 2022-04-13, 2022-08-08 posts).
