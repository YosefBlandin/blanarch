# FortiClient VPN: the admin/helpdesk view and third-party alternatives

## Onboarding pain: distributing gateway, port, certs, realms; mobile provisioning (MDM/EMS)

### Takeaway
Fortinet's supported way to push VPN settings to endpoints is licensed: EMS (optionally fed by Intune/MDM managed-app config). The free VPN-only client has no central management, so admins fall back to written instructions or hand-built config files, and even licensed Mac deployment through MDM is described as poorly documented.

### Cited Findings
- The free VPN-only agent runs standalone with no license. Central management, auto-connect, always-up and MSI packages for enterprise deployment are excluded from it. EMS is what enables VPN auto-connect, pre-logon access and GPO installs — [Fortinet Community: FortiClient licensing and support](https://community.fortinet.com/t5/FortiClient/Technical-Tip-FortiClient-licensing-and-support/ta-p/196327)
- A lighter licensed "FortiClient Standalone" (v7.4.7+) needs at least 50 seats — [same](https://community.fortinet.com/t5/FortiClient/Technical-Tip-FortiClient-licensing-and-support/ta-p/196327)
- Android/iOS: Intune managed-app configuration keys (`cloud_invite_code`, `ems_server`/`ems_port`, `invitation_code`) enrol FortiClient into EMS. `intune_device_id` is mandatory on Android. MDM-pushed VPN profiles are read-only in the app. Per-app SSL VPN on Android is set up through Intune — [Fortinet Intune Deployment Guide 7.4](https://docs.fortinet.com/document/forticlient/7.4.0/intune-deployment-guide/721527/enrolling-forticlient-mobile-endpoints-to-ems-with-intune-integration); [per-app SSL VPN Android](https://docs.fortinet.com/document/forticlient/7.4.0/intune-deployment-guide/352273/configuring-per-application-ssl-vpn-on-forticlient-android)
- Jamf admins (Mar to Oct 2022) deploying FortiClient VPN-only on macOS reported: a blank window when config files were missing; the public VPN-only download lacks the `install.mpkg`, which has to come from the support portal; `custom.conf`/`default.conf` from EMS must be placed precisely; updates don't automate well (you must uninstall first); no clear PPPC/system-permission guidance — [Jamf Nation thread](https://community.jamf.com/general-discussions-2/deploying-forticlient-vpn-only-27054)
- FortiClient for Mac has no GUI setting for IPsec over TCP, and its config can't be hand-edited because the password is encrypted, so EMS deployment is needed — [Fortinet Community: Dialup IPsec over TCP gotcha](https://community.fortinet.com/support-forum-92/dialup-ipsec-over-tcp-with-forticlient-vpn-a-gotcha-221477)
- Universities publish step-by-step "type this gateway and port" pages for the free Android client, which shows how manual onboarding works without EMS — [University of Edinburgh: Android FortiClient SSL config](https://information-services.ed.ac.uk/computing/desktop-personal/vpn/forticlient-vpn/android-forticlient-configuration-for-ssl-vpn)

### Inferences
- Organisations without EMS (small businesses, schools, anyone on the free client) have no zero-touch way to push gateway, port and realm to phones. A setup-link/QR flow that carries host, port, realm and a cert pin (never a password) fills a real gap between "email a PDF of instructions" and "buy EMS + Intune".
- A third-party client can't join the EMS/Intune managed-config ecosystem unless it implements its own Android managed-configuration (app restrictions) schema. That is cheap to add and would let MDM admins push profiles without EMS.

### Gaps
- No quantitative data on how many orgs use free FortiClient vs EMS.
- Couldn't access Reddit threads directly. Admin sentiment here comes from vendor forums, Jamf Nation and review aggregators.

## Helpdesk load: which issues generate the most tickets

### Takeaway
The most-documented ticket driver is the generic "Permission denied (-455)" error, which covers wrong password, username case, group/portal mapping and MFA failures under one message. Next come connect-then-disconnect regressions after client upgrades, SSO/SAML problems, certificate interference and general instability.

### Cited Findings
- "-455" is the FortiGate refusing login or tunnel. Causes include a wrong or disabled password, username case (JohnSmith vs johnsmith, which Fortinet documents), an LDAP/RADIUS user not in the SSL-VPN group, a portal without tunnel access, policy/schedule/source restrictions, or MFA token state — [rottenwifi -455 guide](https://rottenwifi.com/fix-forticlient-ssl-vpn-permission-denied-455/); [Fortinet Community -455 with 2FA + LDAP group](https://community.fortinet.com/fortigate-3/technical-tip-ssl-vpn-connection-with-the-permission-denied-455-on-the-2fa-mobile-free-trialtoken-and-ldap-server-user-group-188570); [Fortinet Community thread](https://community.fortinet.com/support-forum-92/forticlient-vpn-permission-denied-455-167537)
- Wrong gateway address/port also produces -455 — [wintips.org](https://www.wintips.org/fix-ssl-vpn-connection-is-down-in-forticlient-permission-denied-455/)
- FortiClient 7.x "connects, then immediately disconnects" (SSO), fixed only by rolling back to 6.4.1 (2022) — [Jamf Nation](https://community.jamf.com/general-discussions-2/deploying-forticlient-vpn-only-27054)
- FortiClient 7.2.4: certificates installed by Adobe Creative Cloud blocked part of the VPN login — [Adobe Community](https://community.adobe.com/questions-624/forticlient-vpn-client-login-blocked-by-creative-cloud-certificates-681889)
- Aggregated reviews cite frequent drops, heavy resource use, complex setup, weak support, conflicts with other security software and difficult uninstall — [Capterra FortiClient reviews](https://www.capterra.com/p/151916/FortiClient/reviews/)
- Free-client users get no TAC support. Their support channel is the community forums, which pushes the burden onto internal helpdesks — [Fortinet licensing tip](https://community.fortinet.com/t5/FortiClient/Technical-Tip-FortiClient-licensing-and-support/ta-p/196327)
- Client-side CVE-2024-47574 (CVSS 7.8, local privilege escalation in FortiClient) means yet another patch cycle for admins — [The Register, Nov 2024](https://www.theregister.com/2024/11/14/fortinet_vpn_authentication_bypass_bug/)

### Inferences
- A client that turns ambiguous gateway replies into specific, actionable messages ("wrong password" vs "your account is not allowed to use VPN, contact IT" vs "code expired") and gives users a copyable diagnostics sheet for IT removes the biggest ticket driver's worst part: guessing. The server can't always tell the client the cause, so some ambiguity will remain.
- Group/portal/policy misconfiguration is server-side, and no client can fix it.

### Gaps
- No helpdesk ticket statistics (percent of tickets by cause) found. The public university/council KB I found (Trafford) needs a login.

## Licensing and product confusion: free VPN vs licensed FortiClient/EMS, removals, ZTNA push

### Takeaway
There are several SKUs with shifting feature sets. Auto-connect/always-up went behind the licence after v6. The free client gets no support. Fortinet's messaging pushes toward EMS, ZTNA and FortiSASE as SSL-VPN is retired.

### Cited Findings
- After FortiClient v6, the free version dropped the "Auto Connect" and "Always Up" options — [Fortinet Community licensing clarification](https://community.fortinet.com/support-forum-92/forticlient-licensing-and-ems-clarification-205768) (as summarised in search results; see also the [licensing tip](https://community.fortinet.com/t5/FortiClient/Technical-Tip-FortiClient-licensing-and-support/ta-p/196327))
- The free VPN-only agent includes basic IPsec and SSL VPN, split tunnel and 2FA. Current versions are 7.2 and 7.4.3. The licensing tip also lists "new security patches" among what free versions exclude — [Fortinet licensing tip](https://community.fortinet.com/t5/FortiClient/Technical-Tip-FortiClient-licensing-and-support/ta-p/196327)
- Fortinet's stated reasons for the SSL-VPN sunset include resources on small boxes, recurring vulnerabilities and the move to ZTNA. The recommended alternatives are FortiSASE and FortiClient EMS — [Mirazon: RIP FortiGate SSL VPN](https://www.mirazon.com/rip-fortigate-ssl-vpn-what-you-need-to-know/)
- Android has two apps on Play: "FortiClient VPN" (free, limited) and "FortiClient – Fabric Agent" (EMS-managed) — [Google Play: FortiClient VPN](https://play.google.com/store/apps/details?id=com.fortinet.forticlient_vpn&hl=en); [Google Play: FortiClient](https://play.google.com/store/apps/details?id=com.fortinet.forticlient_fa)
- IKEv2 over TCP isn't officially supported in the free VPN client. Community reports conflict: one says 7.4.3 VPN-only on Windows works with IPsec over TCP, another relays a Fortinet statement that Windows/macOS VPN-only 7.4.3+ does *not* support IPsec over TCP — [Fortinet Community IKEv2 free client thread](https://community.fortinet.com/support-forum-92/vpn-ipsec-ikev2-with-ldap-authentication-fortitoken-possible-with-the-free-vpn-only-client-220649/index1.html); [IPsec-over-TCP thread](https://community.fortinet.com/t5/Support-Forum/FortiClient-Remote-Access-IPsec-over-TCP-not-working/m-p/388503); [gotcha thread](https://community.fortinet.com/support-forum-92/dialup-ipsec-over-tcp-with-forticlient-vpn-a-gotcha-221477)

### Inferences
- The free-client user base loses the most in the SSL-VPN to IPsec transition: the replacement transport (IKEv2/TCP 443) is officially unsupported or undocumented for them. That uncertainty is a helpdesk cost and an opening for a well-documented third-party client, but only one that speaks IPsec/IKEv2 (see next sections).
- A third-party client can legitimately offer always-up/auto-reconnect for free. That is a real admin-visible difference from the free FortiClient.

### Gaps
- Couldn't confirm from a Fortinet release note exactly which free-client platform/version supports IKEv2 over TCP (conflicting forum statements).

## Policy features admins need that a third-party client would lack

### Takeaway
Host checks and endpoint posture, EMS tagging/ZTNA, centrally enforced always-up/pre-logon and MDM integration all depend on the FortiClient agent reporting to EMS. A third-party SSL-VPN client can do cert-pinned, cert-based and OTP login, split tunnel and DNS, but not posture compliance.

### Cited Findings
- EMS is what provides auto-connect, pre-logon, central management and ZTNA — [Fortinet licensing tip](https://community.fortinet.com/t5/FortiClient/Technical-Tip-FortiClient-licensing-and-support/ta-p/196327)
- Mobile posture and ZTNA go through EMS enrolment (Intune keys, `intune_device_id`) — [Fortinet Intune guide](https://docs.fortinet.com/document/forticlient/7.4.0/intune-deployment-guide/786701/configuring-microsoft-intune-integration-to-allow-forticlient-android-to-connect-to-ems)
- OpenConnect's Fortinet support covers username/password, optional TLS client certificate and optional MFA token, and prefers PPP-over-DTLS. Its docs don't mention host checks or SAML. The newer "v2" wire protocol (FortiOS 6.2.6+) is unsupported, and reconnection "still doesn't work very well" — [OpenConnect Fortinet page](https://www.infradead.org/openconnect/fortinet.html)
- openfortivpn supports client certificates including PKCS#11 smartcards, SAML through an external helper (openfortivpn-webview), trusted-cert SHA-256 pinning and custom DNS/routes. It needs root for pppd, routes and DNS — [openfortivpn README](https://github.com/adrienverge/openfortivpn)

### Inferences
- Gateways that enforce FortiClient host checks or EMS-tag-based policies will reject or restrict any third-party client. The app should say so plainly rather than fail with a generic error.
- Cert-based auth (Android KeyChain), split DNS and IPv6 are client-implementable features where a third-party client can match FortiClient.

### Gaps
- No source quantified how many deployments enforce host checks/EMS tags. IPv6 and split-DNS behaviour of FortiClient vs alternatives wasn't researched in depth.

## FortiOS 7.6.3 removal of SSL-VPN tunnel mode: timeline, reach, IPsec migration, third-party implications

### Takeaway
SSL-VPN tunnel mode is gone from every FortiGate from FortiOS 7.6.3 (released April 2025). Configs are deleted on upgrade, not converted. Small models lost it earlier (7.6.0, and 7.4.8 for 50G/70G/90G). The 7.4 branch keeps SSL-VPN and is supported until 11 Nov 2028, so SSL-VPN gateways will remain for about two more years, and then shrink.

### Cited Findings
- 7.6.0: SSL VPN (web and tunnel) removed on models with 2 GB RAM or less (FG-40F/60F/61F and similar) — [Fortinet 7.6.0 release notes](https://docs.fortinet.com/document/fortigate/7.6.0/fortios-release-notes/877104/ssl-vpn-removed-from-2gb-ram-models-for-tunnel-and-web-mode); [Sikich](https://www.sikich.com/insight/fortinet-removes-ssl-vpn-from-lower-end-firewalls-what-you-need-to-know/)
- 7.6.3: tunnel mode replaced by IPsec on all models. Not in GUI or CLI, settings not upgraded, must migrate before upgrading. IPsec can use TCP 443. Web mode continues as "Agentless VPN" but not on 40F/60F/90G — [Fortinet 7.6.3 release notes](https://docs.fortinet.com/document/fortigate/7.6.3/fortios-release-notes/173430/ssl-vpn-tunnel-mode-no-longer-supported); [7.6.3 migration guide](https://docs.fortinet.com/document/fortigate/7.6.3/administration-guide/155142/ssl-vpn-tunnel-mode-to-ipsec-vpn-migration-new)
- 7.6.3 released 17 Apr 2025. Agentless VPN is limited to 19-inch (3-digit) models. G-series entry models (50G/70G/90G) lose SSL VPN web and tunnel — [boll.ch Tech Blog](https://blog.boll.ch/fortios-7-6-3-ssl-vpn-tunnel-mode-is-no-longer-supported/)
- 7.4.8+: 50G/70G/90G lose SSL VPN, and active configs are removed on upgrade. The rest of 7.4 keeps it — [Mirazon](https://www.mirazon.com/rip-fortigate-ssl-vpn-what-you-need-to-know/); [Fortinet 7.4.4 SSL VPN support note](https://docs.fortinet.com/document/fortigate/7.4.4/fortios-release-notes/973252/ssl-vpn-support)
- FortiOS 7.4 end of support extended from 11 Nov 2027 to 11 Nov 2028 (CSB-260330-1, March 2026) — [Fortinet Community EoS change](https://community.fortinet.com/fortigate-3/technical-tip-fortios-end-of-support-change-for-fortios-v7-4-and-v7-6-224876); [endoflife.date](https://endoflife.date/fortios)
- Recommended replacement: dial-up IPsec, IKEv2 over TCP 443 — [dev.to summary](https://dev.to/madhushan/fortios-763-update-ssl-vpn-tunnel-mode-no-longer-supported-27hg); [forti.blog guide](https://forti.blog/guides/forticlient-dial-up-ipsec-vpn-on-fortigate)
- Migration gotcha: IPsec over TCP dial-up needs NPU offload disabled on the VPN policy (`auto-asic-offload disable`), which isn't clearly documented and costs CPU and throughput. Reported on FortiGate 7.4.9 with FortiClient VPN 7.4.3 — [Fortinet Community gotcha](https://community.fortinet.com/support-forum-92/dialup-ipsec-over-tcp-with-forticlient-vpn-a-gotcha-221477)
- Security context driving the retirement: over 10k FortiGates still exposed to a 5-year-old SSL-VPN 2FA bypass (late 2025); 16,620 devices with a symlink backdoor surviving patches (Apr 2025) — [BleepingComputer 2FA bypass](https://www.bleepingcomputer.com/news/security/over-10-000-fortinet-firewalls-exposed-to-ongoing-2fa-bypass-attacks/); [The Hacker News symlink](https://thehackernews.com/2025/04/fortinet-warns-attackers-retain.html)
- "FortiBleed" (18 Jun 2026): leaked VPN credentials, including plaintext passwords, for about 73.9k to 75k firewall URLs in 194 countries, reportedly "roughly half of all internet-accessible Fortinet firewalls". Attackers reportedly cracked intercepted SSL-VPN auth hashes. Source of the leak is unclear — [BleepingComputer](https://www.bleepingcomputer.com/news/security/fortibleed-leak-exposes-fortinet-vpn-credentials-for-73-000-devices/)

### Inferences
- The FortiBleed figure implies roughly 150k internet-reachable Fortinet VPN firewalls. That is a rough, secondhand estimate, not a census of SSL-VPN-enabled gateways.
- An SSL-VPN-only third-party client has a shrinking but multi-year market: 7.4 gateways until at least Nov 2028, plus orgs that postpone 7.6. New deployments and small models will be IPsec-only. Long-term relevance needs IKEv2 (Android has built-in IKEv2 via `Ikev2VpnProfile`, and strongSwan exists), including Fortinet's IKEv2-over-TCP 443 (RFC 8229-style) and EAP/2FA handling.
- Admins mid-migration need to know which transport a gateway speaks. A client that detects "tunnel mode not available on this gateway" and says so clearly would save tickets.

### Gaps
- No reliable data on what fraction of deployed FortiGates are on 7.6.3+ vs 7.4 or earlier. Whether Fortinet's IKEv2-over-TCP is plain RFC 8229 or has proprietary parts wasn't established (relevant for interop with Android/strongSwan). No Reddit migration threads retrieved.

## Alternatives: openfortivpn, OpenConnect, NetworkManager plugins, Android/iOS third-party clients

### Takeaway
On desktop Linux/macOS, openfortivpn (GPLv3, PPP+TLS, SAML via helper) and OpenConnect (`--protocol=fortinet`, experimental since 2021, DTLS) are the established alternatives. On Android, the only notable third-party Fortinet-capable options are OpenConnect-based apps. None does posture checks, and all are tied to SSL-VPN tunnel mode, which 7.6.3 removed.

### Cited Findings
- openfortivpn: "Client for PPP+TLS VPN tunnel services", Fortinet-compatible, spawns pppd. Linux/macOS/FreeBSD. PKCS#11 smartcards, SAML (openfortivpn-webview), trusted-cert SHA-256 pinning, config file, pinentry. Needs root. About 116 open issues. GPL-3.0 — [openfortivpn GitHub](https://github.com/adrienverge/openfortivpn)
- A report in search results says openfortivpn 1.23.1 to 1.24.0 broke compatibility for a downstream (AUR/NetworkManager) user, with an upstream PR pending. Not independently verified — [AUR networkmanager-fortisslvpn](https://aur.archlinux.org/packages/networkmanager-fortisslvpn)
- NetworkManager-fortisslvpn (GUI plugin wrapping openfortivpn ≥1.10): its GitHub repo was archived by the owner on 8 Sep 2026 and is read-only. The README doesn't say why, and it may be a mirror of the GNOME GitLab project — [GitHub NetworkManager-fortisslvpn](https://github.com/NetworkManager/NetworkManager-fortisslvpn)
- OpenConnect Fortinet support: experimental since March 2021 (v9.00+). Password, client cert and MFA tokens. PPP-over-DTLS with TLS fallback. Before FortiOS 6.2.1, no reconnect cookie (so re-auth after a drop), and reconnect is still unreliable. The "v2" protocol for 6.2.6+ is unsupported — [OpenConnect Fortinet](https://www.infradead.org/openconnect/fortinet.html); [OpenConnect protocols](https://www.infradead.org/openconnect/protocols.html)
- OpenConnect for Android (F-Droid) supports AnyConnect, Juniper, GlobalProtect, Pulse, F5 and Fortinet, with RSA/TOTP soft tokens and no root — [F-Droid](https://f-droid.org/packages/net.openconnect_vpn.android/)
- "OpenConnect" by Digital Software Solutions (Google Play, free, GPLv2-based) lists FortiGate among 7 gateway families, with per-app split tunnel, DTLS, auto-reconnect and SecurID — [getopenconnect.app](https://getopenconnect.app/)
- OpenFortiGUI: a Linux GUI on top of openfortivpn — [hadler.me](https://hadler.me/linux/openfortigui/)
- Native OS IPsec clients (macOS, Windows, iOS) are an official alternative once gateways move to IPsec — [Infortech](https://www.infortech.com/2025/12/18/fortinets-ssl-vpn-is-going-away-migrate-to-ipsec-vpn-now/)

### Inferences
- The Android space for a dedicated, Fortinet-focused, polished third-party client is nearly empty: OpenConnect apps are multi-vendor, generic in UX and carry OpenConnect's reconnect limits on Fortinet. Differentiators for a new client: reliable reconnect, email/SMS/FortiToken OTP handling, cert pinning with a user-confirmed fingerprint, setup links/QR, and clear errors.
- What a third-party client can't address: EMS posture/ZTNA tags, host checks, MDM-enforced always-on via EMS, and TAC support. Without IKEv2 it also can't address 7.6.3+ gateways at all.
- Clean-room note: GPL projects (openfortivpn GPLv3, OpenConnect LGPL/GPL) were researched from descriptions only, and no code was read.

### Gaps
- No iOS third-party Fortinet SSL-VPN client found (iOS needs a NetworkExtension and OpenConnect has no maintained App Store build that I could confirm).
- Didn't retrieve issue-title lists or user complaints for the Android OpenConnect apps, and didn't verify the AUR breakage claim first-hand.
