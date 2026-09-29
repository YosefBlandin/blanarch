# FortiClient VPN desktop clients (Windows, macOS, Linux): user and admin complaints

Method note: Reddit (r/fortinet, r/sysadmin, etc.) could not be fetched directly (fetch tool blocked reddit.com) and site-limited web searches returned no Reddit threads. Evidence below comes from the Fortinet Community forum, Fortinet docs/release notes, Hacker News comments (via the Algolia API), review sites (Trustpilot, G2 snippets via search), tech blogs, and security press. Frequency ratings are rough judgements from how often a theme appeared across sources, not measured counts.

## What are the most common desktop complaints?

### Takeaway
The recurring desktop themes are: connection reliability (drops, no auto-reconnect unless the password is saved, stuck at 98% on older Windows builds), DNS and split-DNS breakage (especially Windows 11 and macOS), SAML/SSO browser flow failures, OS-upgrade breakage on macOS (Sequoia permissions, Tahoe crypto and routing), a poor Linux client (blank GUI, install failures, crashes; users switch to openfortivpn), and heaviness/intrusiveness (hard to uninstall, high resource use, cryptic errors, dated UI). Saved-password behaviour is a persistent irritation.

### Summary table (rough frequency / severity)
| Category | Frequency | Severity | Platforms |
|---|---|---|---|
| Drops, no auto-reconnect, cryptic errors | High | High (work stops) | All |
| DNS / split DNS not applied | High | High | Windows 11, macOS |
| OS upgrade breakage (macOS Sequoia/Tahoe) | High at each macOS release | High | macOS |
| SAML/SSO embedded vs external browser | Medium-High | High (cannot log in) | All, esp. Linux |
| Linux client quality (blank GUI, install deps, freezes) | Medium (smaller user base) | High | Linux |
| Save password missing / not persisting | Medium | Medium (daily friction) | All |
| Bloat, intrusive, hard to uninstall, resource use | Medium | Medium | Windows mainly |
| Stuck at 98% | Medium, mostly older (2015-2019) | High | Windows |
| Free VPN-only client limits / discontinuation | Medium (2025-2026 spike) | High for small orgs | Windows |
| Conflicts with other VPN/networking tools | Low-Medium | Medium | All |

### Cited Findings

Reliability, reconnect, saved credentials
- Admin (Jan 2023, FortiOS 7.0.9 / FortiClient 7.0.7): users were dropped and forced to re-authenticate after internet blips over about 10 s. The only fix that worked: "By enabling the 'Save Password' option (which I'm really not crazy about doing), it auto-reconnected the user when their network dropped." DUO MFA was still required on reconnect. Admin compared unfavourably with Cisco AnyConnect behaviour. — [Fortinet Community: SSL VPN Not auto-reconnecting](https://community.fortinet.com/t5/Support-Forum/SSL-VPN-Not-auto-reconnecting/td-p/242860)
- User (Aug 2026, FortiClient VPN 7.4.3 hotfix): the "Save Password" checkbox disappears after disconnect even after enabling it via XML config; "It's just really frustrating to re-enter my password everytime." Staff only asked SSL vs IPsec and linked a KB article. — [Fortinet Community: FortiClient VPN "Save Password" option](https://community.fortinet.com/support-forum-92/forticlient-vpn-save-password-option-229414)
- Review-site cons (search snippets, G2): update issues leading to disconnects; connections occasionally need manual reconnect; "When ZTNA or VPN tunnels drop, error codes are often too cryptic for an average user to solve without opening a ticket with the IT helpdesk"; UI "can feel dated and not very intuitive"; high resource consumption. — [G2 FortiClient pros and cons](https://www.g2.com/products/forticlient/reviews?qs=pros-and-cons) (page returned 403 to direct fetch; content seen only via search snippets, treat as secondary)
- Trustpilot (Fortinet overall 1.5/5 from 43 reviews): "FortiClient is really the worst VPN out there. It is intrusive in the system (You cannot uninstall)" and "if I set up a new connection, it is gone after I click on save." (Jul 30 2025); "blocks everything, including sometimes new tabs...impossible to take off, because task manager" won't end it (Dec 18 2025). — [Trustpilot Fortinet reviews](https://ca.trustpilot.com/review/www.fortinet.com)
- Hacker News: "it's a sorry piece of crap that's more often borken than not" (vladvasiliu, 2025-09-14) — [HN 45238953](https://news.ycombinator.com/item?id=45238953); "turned Forticlient, the worst corporate vpn solution ever, into socks" (k4rli, 2024-04-02) — [HN 39903807](https://news.ycombinator.com/item?id=39903807); running Tailscale and FortiClient together "tailscale does not like it" (2025-09-20) — [HN 45314743](https://news.ycombinator.com/item?id=45314743)

Stuck at 98% (mostly OLDER, pre-2022)
- Long-running "stuck at 98%" thread; attributed to the Windows WAN Miniport driver rather than FortiClient; affected FortiClient 5.3/5.4 on Windows 8/10. Workarounds: reboot, WAN miniport repair. — [Fortinet Community: VPN stuck at status 98%](https://community.fortinet.com/t5/Support-Forum/VPN-stuck-at-status-98/td-p/75229); [Kontech IT write-up](https://kontech.net/forticlient-vpn-connection-getting-stuck-at-status-98/) (OLDER)
- I found no 2022-2026 primary source for "stuck at 40%" in this pass (see Gaps).

DNS and split DNS
- Windows 11 + FortiClient 7.0.2: DNS resolution uses only locally configured DNS, not the tunnel's DNS; does not happen on Windows 10. — [Fortinet Community: DNS resolution over IPsec/SSL VPN with win 11](https://community.fortinet.com/t5/Support-Forum/DNS-resolution-over-IPsec-SSL-VPN-with-win-11-and-forticlient-7/td-p/205653)
- Split DNS inconsistently applied: `ipconfig /all` shows the VPN adapter without the split-DNS servers; some hosts on the same OS work, others not. — [Fortinet Community: FortiClient SplitDNS Issues](https://community.fortinet.com/support-forum-92/forticlient-splitdns-issues-160882); [SSLVPN split-DNS not always working](https://community.fortinet.com/t5/Support-Forum/SSLVPN-split-DNS-not-allways-working/td-p/202720); [Client DNS registering not working with split DNS](https://community.fortinet.com/t5/Support-Forum/Client-DNS-registering-not-working-with-split-DNS/m-p/299793)
- HN: "On Windows and macOS it's a bit more janky, specifically the DNS resolution" (2025-09-10). — [HN 45202088](https://news.ycombinator.com/item?id=45202088)
- Split DNS is also an open topic for openfortivpn. — [openfortivpn issue #561](https://github.com/adrienverge/openfortivpn/issues/561)

SAML / SSO browser flow
- FortiClient 7.4.2 + SSL VPN + Azure SAML fails with the internal (embedded) browser but works with the external browser; older versions were fine. — [Fortinet Community thread](https://community.fortinet.com/support-forum-92/forticlient-7-4-2-and-ssl-vpn-azure-saml-not-working-with-internal-browser-works-with-external-198945)
- External-browser SAML uses local port 8020 by default; if occupied, FortiClient shows "SAML redirect port is unavailable". — [Fortinet docs 7.4.6: external user-agent for SAML](https://docs.fortinet.com/document/forticlient/7.4.6/ems-administration-guide/748803/using-a-browser-as-an-external-user-agent-for-saml-authentication-in-an-ssl-vpn-connection)
- Microsoft security baselines can break FortiClient SAML auth (troubleshooting article). — [deploymentshare.com](https://deploymentshare.com/articles/bp-forticlient-ts/)
- Linux (KUbuntu 22.04): SSO window opens and closes, client stuck on "Connecting...". — [Fortinet Community](https://community.fortinet.com/t5/Support-Forum/FortiClient-VPN-in-KUbuntu-22-04-with-SSO-gets-stuck-in-quot/td-p/267691)

macOS permissions and OS upgrades
- Sequoia (15.0): Apple moved permission panes; users must enable FortiClient under System Settings > Login Items & Extensions > Network Extensions or VPN fails. — [Fortinet Community: Sequoia support for FortiClient VPN 7.4](https://community.fortinet.com/t5/Support-Forum/MacOs-Sequoia-15-0-support-for-FortiClient-VPN-7-4/td-p/342309)
- Tahoe (26): thread opened Sep 22 2025, 12+ replies: apps not using the VPN, traffic leaving from local IP instead of VPN IP. Staff: Tahoe not yet on the support list, "most likely with version 7.4.5". — [Fortinet Community: Issues on macOS Tahoe](https://community.fortinet.com/support-forum-92/issues-on-macos-tahoe-214802)
- Tahoe 26.2 + FortiClient VPN 7.4.3: "Unable to connect to VPN because tunnel configuration..." — [Fortinet Community thread](https://community.fortinet.com/support-forum-92/macbook-tahoe-26-2-ortinetclient-vpn-7-4-3-6667-unable-to-connect-to-vpn-because-tunnel-configurati-223606); [IPsec VPN and Mac OS Tahoe](https://community.fortinet.com/support-forum-92/ipsec-vpn-and-mac-os-tahoe-225749)
- A third-party vendor attributes many Tahoe IPsec failures to Apple dropping legacy algorithms (3DES, SHA1, old DH groups); users report fixing by moving to DH group 21. (Vendor blog with a commercial interest.) — [VPN Tracker blog](https://blog.vpntracker.com/forticlient-macos-tahoe-not-working/)

Linux client quality, openfortivpn as alternative
- FortiClient would not install on Ubuntu 24.04 LTS (bug 1032729, fix promised in 7.2.5/7.4.1); workaround was stripping libappindicator dependencies from the .deb. — [Fortinet Community: Support for FortiClient VPN 7.4 for Ubuntu 24.04](https://community.fortinet.com/t5/Support-Forum/Support-for-FortiClient-VPN-7-4-for-Ubuntu-24-04-LTS/m-p/321348); [How to let forticlient vpn work properly in Ubuntu 24.04](https://community.fortinet.com/support-forum-92/how-to-let-forticlient-vpn-work-properly-in-ubuntu-24-04-228174)
- SAML login in Linux GUI freezes the system after 3-4 minutes. — [Fortinet Community: FortiClient VPN crashes computer (linux)](https://community.fortinet.com/t5/Support-Forum/FortiClient-VPN-crashes-computer-linux/m-p/333567)
- Blank GUI window (7.0.7 on several Ubuntu releases). — [Fortinet Community: Blank GUI screen](https://community.fortinet.com/t5/Support-Forum/Blank-GUI-screen-for-Forticlient-7-0-7-VPN-on-Ubun/m-p/240607)
- 7.4 VPN-only client: "Failed to add module FortiClient ZTNA", missing libcertd.so, so SAML unusable (the free VPN-only client dragging in ZTNA modules). — [Fortinet Community: libcertd.so is missing](https://community.fortinet.com/support-forum-92/libcertd-so-is-missing-7-4-vpn-only-client-not-able-to-use-saml-221506?postid=221521)
- Blog (Mar 24 2025): "The official Fortinet SSL VPN client for Ubuntu is unstable and slow. Use openfortivpn instead"; connections took up to 5 minutes to establish or close; crashes. openfortivpn 1.23.0 added SAML. — [nezhar.com](https://nezhar.com/blog/openfortivpn-make-fortinet-ssl-vpn-great-again-on-linux/)
- Other alternatives: OpenFortiGUI (Qt GUI over openfortivpn). — [hadler.me](https://hadler.me/linux/openfortigui/); [openfortivpn GitHub](https://github.com/adrienverge/openfortivpn)

### Inferences
- Reconnect behaviour and credential storage are tightly linked in FortiClient: admins must choose between security (no saved password) and usability (auto-reconnect). A client that reconnects with a fresh OTP or keeps a session alive without a stored password would address a documented pain.
- DNS correctness is the most "silent" failure: the tunnel is up but names do not resolve. Showing applied DNS/routes in the UI would help support staff.
- Every major macOS release produces a wave of "VPN broke" threads, with Fortinet support lagging weeks behind.

### Gaps
- No direct Reddit quotes (fetch blocked). Reddit sentiment likely strong but uncited here.
- "Stuck at 40%" not found in a 2022-2026 source in this pass.
- No measured data on throughput, CPU or battery use of the desktop client beyond review-site generalities.
- Forced upgrades via EMS: not found with a specific primary source.

## What changed with FortiOS 7.6 / FortiClient 7.4, and how are users and admins reacting?

### Takeaway
FortiOS 7.6.3 (April 2025) removed SSL VPN tunnel mode on all FortiGate models, replacing it with IPsec (optionally over TCP 443), and existing SSL tunnel config is deleted on upgrade. In parallel, FortiClient (Windows) 7.4.4 shipped no new free VPN-only agent and dropped IKEv1, widely read as the end of the free VPN-only client. Reactions are migration anxiety from admins and anger about "enshittification" from small users.

### Cited Findings
- "Starting in FortiOS 7.6.3, the SSL VPN tunnel mode feature is replaced with IPsec VPN, which can be configured to use TCP port 443. SSL VPN tunnel mode is no longer available in the GUI and CLI." Settings are not upgraded. — [FortiOS 7.6.3 release notes](https://docs.fortinet.com/document/fortigate/7.6.3/fortios-release-notes/173430/ssl-vpn-tunnel-mode-no-longer-supported)
- 7.6.3 released April 17 2025; tunnel mode removed on ALL models; web mode (renamed "agentless VPN") remains only on larger 3-digit models; small G-series (50G/70G/90G) lose web mode already in 7.4.8; 2 GB RAM models had lost both earlier. — [boll.ch tech blog](https://blog.boll.ch/fortios-7-6-3-ssl-vpn-tunnel-mode-is-no-longer-supported/)
- Fortinet migration guide: unsupported SSL tunnel config "is automatically removed after upgrade"; migrate before upgrading. — [FortiOS 7.6.3 admin guide: SSL VPN tunnel mode to IPsec migration](https://docs.fortinet.com/document/fortigate/7.6.3/administration-guide/155142/ssl-vpn-tunnel-mode-to-ipsec-vpn-migration-new)
- Consultants frame it as a forced project: users on SSL tunnel mode "will break immediately upon upgrade". — [Network Devices Inc.](https://networkdevicesinc.com/community/blog/fortios-7-6-3-ssl-vpn-ipsec-migration); [Infortech, Dec 2025](https://www.infortech.com/2025/12/18/fortinets-ssl-vpn-is-going-away-migrate-to-ipsec-vpn-now/); [ConnectaSec: IPsec or ZTNA?](https://connectasec.com/en/blog/fortigate-elimina-ssl-vpn-ipsec-o-ztna/)
- End user, Trustpilot (Jun 8 2026, 1 star): "Update to firmware 7.4 removed SSL VPN and IPSEC VPN didn't work at all". — [Trustpilot](https://ca.trustpilot.com/review/www.fortinet.com)
- FortiClient (Windows) 7.4.4 "does not include a new version of the free VPN-only agent"; 7.4.3 is the last free VPN-only build; 7.4.4 drops IKEv1 (IKEv2 only). Reader: "more and more companies are becoming increasingly greedy"; another: "enshitification", many firms rely on the free client for external freelancers, suggests open-source alternatives. Article update (July 2026) says a Fortinet employee reportedly confirmed discontinuation, pointing users to EMS or SASE (secondhand; not verified at a Fortinet primary source). — [Born's Tech and Windows World, Sep 11 2025](https://borncity.com/win/2025/09/11/has-fortinet-just-discontinued-its-free-vpn-client/)
- Fortinet's feature comparison between free VPN-only and licensed FortiClient. — [FortiClient 7.4.4 feature comparison](https://docs.fortinet.com/document/forticlient/7.4.4/administration-guide/269675/forticlient-feature-comparison)

### Inferences
- Any client that speaks only SSL-VPN tunnel mode faces a shrinking addressable base as gateways move to 7.6.3+. Gateways on 7.4 and earlier (and orgs that refuse to upgrade) remain, but a long-term client needs an IPsec/IKEv2 path.
- The combination of "free client frozen" + "SSL tunnel removed" + "IKEv1 dropped" pushes small orgs and contractors toward paid EMS or third-party clients, a plausible opening for an alternative client.

### Gaps
- Could not collect Reddit/r/fortinet admin reactions to 7.6.3 directly.
- No official Fortinet statement found confirming end of the free VPN-only client; only the release-note wording and secondhand reports.

## Security reputation issues users cite

### Takeaway
Fortinet's SSL-VPN (sslvpnd) has a long record of critical, actively exploited pre-auth bugs, and in 2025-2026 FortiClient EMS itself had an exploited zero-day. This history is widely cited as a reason Fortinet removed SSL VPN tunnel mode and as a reason users distrust the product.

### Cited Findings
- CVE-2024-21762: out-of-bounds write in sslvpnd, CVSS 9.8, pre-auth RCE as root; disclosed Feb 8 2024 and added to CISA KEV the same day. — [Tenable](https://www.tenable.com/blog/cve-2024-21762-critical-fortinet-fortios-out-of-bound-write-ssl-vpn-vulnerability); [Rapid7](https://www.rapid7.com/blog/post/2024/02/12/etr-critical-fortinet-fortios-cve-2024-21762-exploited/)
- April 2025: attackers who exploited CVE-2022-42475, CVE-2023-27997 and CVE-2024-21762 kept read-only access to patched FortiGates through an SSL-VPN symlink trick. — [The Hacker News](https://thehackernews.com/2025/04/fortinet-warns-attackers-retain.html); [Help Net Security](https://www.helpnetsecurity.com/2025/04/11/fortios-fortigate-vulnerabilities-symlink-trick-limited-access/)
- Real-world SSL-VPN intrusion case study. — [Darktrace](https://www.darktrace.com/blog/from-exploit-to-escalation-tracking-and-containing-a-real-world-fortinet-ssl-vpn-attack)
- CVE-2026-35616: FortiClient EMS pre-auth API access bypass (CVSS 9.1), 7.4.5-7.4.6, zero-day exploitation seen from Mar 31 2026. — [The Hacker News, Apr 2026](https://thehackernews.com/2026/04/fortinet-patches-actively-exploited-cve.html); [Cybersecurity Dive](https://www.cybersecuritydive.com/news/critical-flaw-forticlient-ems-exploitation/816699/)
- CVE-2024-47574: FortiClient Windows local privilege escalation via spoofed named-pipe messages (7.4.0, 7.2.0-7.2.4, 7.0.0-7.0.12). — [search summary of Fortinet advisory; CVE list at cvedetails](https://www.cvedetails.com/vulnerability-list/vendor_id-3080/product_id-25405/Fortinet-Forticlient.html)
- A 2026 FortiClient advisory describes a heap overflow in a kernel driver (missing size validation). — [FortiGuard FG-IR-26-156](https://fortiguard.fortinet.com/psirt/FG-IR-26-156) (title only seen in search; details not verified)

### Inferences
- Security history is a gateway-side issue mostly, but it colours perception of the client, and the desktop client's own kernel drivers and privileged services add local attack surface. A lean client with no privileged background services is a genuine differentiator.

### Gaps
- Did not find end-user posts explicitly citing CVEs as their reason to avoid FortiClient (Reddit inaccessible).
- FG-IR-26-156 and CVE-2024-47574 details confirmed only through search snippets, not the advisory pages.
