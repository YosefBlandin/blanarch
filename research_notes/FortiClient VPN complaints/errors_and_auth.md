# FortiClient SSL-VPN connection errors and authentication failures

Scope note: sources are mostly Fortinet Community technical tips (staff-written, dated), Fortinet docs, third-party admin blogs, and IT help-desk KBs. Reddit threads could not be retrieved through the search tools used (site:reddit.com queries returned nothing), so user sentiment from r/fortinet and r/sysadmin is not represented directly. No source gives hard frequency numbers; "how often" is inferred from how many separate KB articles, forum threads and third-party fix pages exist per error.

## Q1. Common codes/messages and their real causes (-7200, -14, -5, -6005, -8, -455, "server may be unreachable", stuck percentages, hostcheck, certificates)

### Takeaway
FortiClient reuses a handful of generic strings for very different root causes. "The VPN server may be unreachable" is attached to codes -14, -8, -5, -20199 and -6005, whose causes range from no internet, to a missing firewall policy after a *successful* login, to an IP lockout, to an unfinished SAML login. "-7200 Credential or SSLVPN configuration is wrong" covers wrong password, locked or expired AD account, Windows Internet Options security level, TLS settings, and a server upgrade that silently disabled tunnel mode. The progress percentage is often the most diagnostic signal, and Fortinet staff publish a map from percentage to cause.

### Cited Findings
**-7200 "Credential or SSLVPN configuration is wrong"**
- Fortinet staff tip (June 16, 2023): caused by incorrect user ID or password, or by Windows "Internet Options > Security > Security Level" set to High. Fix is lowering it to Medium-high or Medium. It can also show up as an SSL connection timeout after authentication seemed to succeed. [Fortinet Community](https://community.fortinet.com/t5/FortiGate/Troubleshooting-Tip-When-logging-in-with-SSL-VPN-the-error/ta-p/260630)
- After upgrading FortiGate to 7.6.3, tunnel mode in the SSL VPN portal may be disabled, which produces -7200 even though the credentials are correct (posted June 2, 2025). [Fortinet Community](https://community.fortinet.com/t5/FortiGate/Troubleshooting-Tip-FortiClient-error-Credential-or-SSL-VPN/ta-p/392381)
- Another staff tip ties -7200 to "sslvpn_login_cert_checked_error", which is a client-certificate check failure, not a password problem. [Fortinet Community](https://community.fortinet.com/t5/FortiGate/Troubleshooting-Tip-Failure-to-connect-via-SSL-VPN-with/ta-p/282593)
- Third-party fix guide lists wrong username or password, wrong VPN settings, TLS settings (disable TLS 1.3 in Internet Options), and outdated client. It also says usernames are case-sensitive with LDAP/RADIUS in recent versions. [WinTips](https://www.wintips.org/fix-forticlient-credential-or-sslvpn-configuration-is-wrong-7200/)
- An MSP's error list attributes -7200 to a wrong password or token, or to an AD account that is locked or has an expired password. [Cloup.co](https://cloup.co/en/blog/security/error-messages-in-forticlient/)
- Fortinet has a general "-7200 with any type of authentication" tech tip, which shows how broad the code is. [Fortinet Community](https://community.fortinet.com/fortigate-3/technical-tip-credential-or-ssl-vpn-configuration-is-wrong-7200-for-ssl-vpn-with-any-type-of-authentication-219912)

**"Unable to establish the VPN connection. The VPN server may be unreachable" (-14, -8, -5, -20199, no code)**
- -14: in a Fortinet forum case (staff answer Feb 13, 2023), the user was authenticated ("fnbamd return auth success") but the log showed "SSL VPN login matched rule (0)". There was no firewall policy for them. The client still said "server may be unreachable". [Fortinet Community](https://community.fortinet.com/t5/Support-Forum/VPN-Server-may-be-unreachable-14-Forticlient-SSL-VPN/td-p/245552)
- The MSP list says -14 and -20199 are OS or VPN conflicts that a restart fixes, -8 is the same as -7200 (credentials), and no code means no internet. [Cloup.co](https://cloup.co/en/blog/security/error-messages-in-forticlient/)
- Another source describes -8 as a temporary block of the source IP after repeated failed logins (anti-brute-force). [SAMURAJ-cz search snippet](https://www.samuraj-cz.com/en/article/fortigate-problems-connecting-to-ssl-vpn-via-forticlient/) (page itself returned HTTP 401, so this is snippet-level only). This conflicts with Cloup.co's "credentials" framing, though both are plausible: an IP lockout follows failed credentials.
- -5: one Microsoft Q&A report had -5 "server may be unreachable", and it turned out to be caused by Windows updates, not the server (search-result summary). [Microsoft Q&A](https://learn.microsoft.com/en-us/answers/questions/446759/vpn-affected-by-windows-updates). I found no authoritative Fortinet definition of -5.
- An admin blog says the "unreachable" message can mean a DNS failure, an unresponsive host or a wrong port, and notes that generic messaging hides the real cause, so admins have to test several possibilities (updated July 21, 2025). [BOLL Tech Blog](https://blog.boll.ch/troubleshooting-the-fortigate-sslvpn/)

**-6005 "Unable to establish VPN connection. The VPN server may be unreachable (-6005)"**
- Fortinet tip (Sept 18, 2023, updated since): usually the user did not finish IdP (SAML) authentication within FortiGate's `remoteauthtimeout`. The default is 5 s, and 180 s is recommended for SAML with 2FA. Other causes: wrong gateway config, networks that block VPN, and a SAML signing-certificate misconfiguration after upgrades to 7.2.12, 7.4.9 or 7.6.4. The fix for the last one is setting Entra "Sign SAML Response and Assertion". [Fortinet Community](https://community.fortinet.com/t5/FortiGate/Troubleshooting-Tip-How-to-fix-the-error-Unable-to-establish-VPN/ta-p/274253)
- A separate tip covers -6005 at 31%. [Fortinet Community](https://community.fortinet.com/t5/FortiGate/Troubleshooting-Tip-Fixing-a-FortiClient-stops-loading-at-31/ta-p/232404)

**-455 "Permission denied"**
- Help-desk case: the user typed the full email address instead of the short username. [University of Saint Joseph KB](https://usj.teamdynamix.com/TDClient/1899/Portal/KB/ArticleDet?ID=105917)
- Third-party guide: it means the FortiGate reached authentication but rejected the login or tunnel request. It does not prove the password is wrong. Causes include a case-sensitive username mismatch, a missing group or portal mapping, a failed MFA or certificate prompt, an SSL-VPN setup that needs migrating after a FortiOS upgrade, and on macOS blocked system or network extensions. [RottenWifi](https://rottenwifi.com/fix-forticlient-ssl-vpn-permission-denied-455/) (secondary source, but consistent with Fortinet's percentage map below)
- Many forum threads exist for -455. [Fortinet Community](https://community.fortinet.com/support-forum-92/forticlient-vpn-permission-denied-455-167537), [Fortinet Community](https://community.fortinet.com/support-forum-92/impossible-to-connect-to-vpn-permission-denied-455-46898)

**Stuck-at-percentage map (Fortinet staff, May 13, 2022)** [Fortinet Community](https://community.fortinet.com/t5/FortiGate/Troubleshooting-Tip-Possible-reasons-for-FortiClient-SSL-VPN/ta-p/211965)
- 10%: "server may be unreachable". Network, wrong gateway or port, certificate, policy, VIP, geo-restriction, or SSL VPN disabled.
- 31%: TLS version mismatch (-5029).
- 40%: untrusted-certificate prompt, TLS mismatch, expired custom certificate, wrong key, SAML issues.
- 42-45%: authentication (wrong credentials, user not in LDAP group, LDAP timeout).
- 48%: two-factor failure, -7200, -455, certificate validation, SAML group mismatch.
- 80%: user group or portal mismatch, tunnel mode not enabled.
- 89%: cannot write to %localappdata%\FortiClient (-5052/-5053).
- 98%: latency, IPv4/IPv6, blocked traffic, corrupted install.
- Error (0): user not in any SSL VPN auth rule or policy.
- The BOLL blog repeats the same map, with 48% as a "missing, incorrect or expired token code". [BOLL Tech Blog](https://blog.boll.ch/troubleshooting-the-fortigate-sslvpn/)

**98% specifically**
- Fortinet tip (Mar 8, 2023): the gateway FQDN resolves to both IPv4 and IPv6, or the virtual adapter is missing. Authentication completes, then it stops at 98%. Fixes: prefer IPv4 (registry, or "Resolve to IPv4 only" in 7.2.5+), remove GPOs that block driver install, remove specific Windows updates, disable local proxy. [Fortinet Community](https://community.fortinet.com/t5/FortiGate/Troubleshooting-Tip-SSL-VPN-fails-at-98/ta-p/248363)
- Help-desk and MSP pages exist just for "stuck at 98%". [Kontech](https://kontech.net/forticlient-vpn-connection-getting-stuck-at-status-98/), [Fortinet forum](https://community.fortinet.com/t5/Support-Forum/VPN-stuck-at-status-98/td-p/75229)

**Host check / "hostcheck timeout"**
- "hostcheck timeout" appears in FortiGate event logs as a tunnel shutdown reason. The free VPN-only FortiClient (6.2+) cannot do host checks, so if host check is enabled on the portal it always errors. FortiClient on Windows Server cannot connect with host-check enabled. [Fortinet Community](https://community.fortinet.com/t5/FortiGate/Technical-Tip-Host-check-errors-while-connecting-SSL-VPN/ta-p/190372), [Fortinet Community](https://community.fortinet.com/t5/FortiClient/Technical-Tip-FortiClient-Host-Checker-Support-for-Windows/ta-p/192227), [Fortinet Community (80%)](https://community.fortinet.com/forticlient-4/technical-tip-forticlient-sslvpn-gets-struck-at-80-95957)

**Server-side platform change (context)**
- From FortiOS 7.6.3, SSL VPN tunnel mode is removed on all FortiGate models and replaced with IPsec (optionally over TCP 443). The config is deleted on upgrade and not migrated. [Fortinet release notes 7.6.3](https://docs.fortinet.com/document/fortigate/7.6.3/fortios-release-notes/173430/ssl-vpn-tunnel-mode-no-longer-supported), [Migration guide](https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/155142/ssl-vpn-tunnel-mode-to-ipsec-vpn-migration). This helps explain the 2025 wave of -7200 errors after upgrades.

### Inferences
- The client's message tells the user almost nothing actionable. The same "server may be unreachable" string covers no network, IP lockout, missing policy after a good login, and a SAML timeout. The same "-7200 credential" string covers server misconfiguration the user cannot fix. A client that tells apart "server not reachable (TCP/TLS failed)", "credentials rejected", "logged in but no access/policy", "locked out, retry in N s" and "code expired" would be a real improvement.
- The percentage is the de facto diagnostic, and help desks teach it. Mapping stages to plain-language states is low-hanging fruit.
- Volume proxy: -7200, -455, 98% and -6005 each have several Fortinet staff tips plus many third-party "FIX:" pages (WinTips, RottenWifi and clones), which suggests high search demand. This is not a measured frequency.

### Gaps
- No Fortinet-published table of FortiClient negative error codes. The meanings of -5, -8 and -12 are only known from third parties and are partly inconsistent.
- No quantitative frequency data (ticket counts, survey) was found.
- Reddit threads could not be retrieved.

## Q2. MFA friction (push not arriving, OTP expiry, re-entering password, save-password, lockouts)

### Takeaway
Most MFA failures come from FortiGate timers. Email/SMS codes default to 60 s. `remoteauthtimeout` defaults to 5 s and limits how long the gateway waits. The lockout default is only 2 failed attempts, then a 60 s block per source IP. Push depends on port 4433 reachability and on RADIUS timeouts. "Save password" is controlled by the server or EMS and often shows greyed out.

### Cited Findings
- Email and SMS token codes (`two-factor-email-expiry`, `two-factor-sms-expiry`) default to 60 s. SSL VPN waits "10x remoteauthtimeout + 30 s" for a code, whatever the token's own validity. The maximum is 300 s. [Fortinet Community](https://community.fortinet.com/t5/FortiGate/Troubleshooting-Tip-SSL-VPN-and-two-factor-expiry-timers/ta-p/191661) (original 2019, still referenced), [Fortinet Community: increasing email token expiry](https://community.fortinet.com/fortigate-3/technical-tip-increasing-email-token-expiry-time-93263)
- Timers (Jan 25, 2022): `login-attempt-limit` default 2 (0-10), `login-block-time` default 60 s, applied per source IP. `login-timeout` is 30 s. `remoteauthtimeout` is 5 s by default and must be raised for MFA. Admins clear blocks with `diagnose vpn ssl blocklist`. [Fortinet Community](https://community.fortinet.com/fortigate-3/technical-tip-ssl-vpn-timers-explanation-and-ssl-vpn-login-attempt-limit-aka-lockout-102761), [Fortinet docs 6.2](https://docs.fortinet.com/document/fortigate/6.2.0/cookbook/279661/configuring-the-maximum-log-in-attempts-and-lockout-period)
- Admins ask how to unblock banned IPs, which shows users do hit the lockout. [Fortinet Community](https://community.fortinet.com/t5/Support-Forum/Howto-unblock-banned-IP-on-SSL-VPN/td-p/210358), [Fortinet Community](https://community.fortinet.com/t5/Support-Forum/Forticlient-SSL-VPN-failed-login-limit/td-p/255556)
- FortiToken Mobile push needs FTM enabled on the WAN interface, and port 4433 free and port-forwarded if the FortiGate is behind NAT. With RADIUS, the 5 s default timeout is too short for the push round trip. [Fortinet Community](https://community.fortinet.com/t5/FortiGate/Technical-Tip-FortiToken-Mobile-push-notification/ta-p/195578), [Fortinet Community: push issue](https://community.fortinet.com/t5/FortiGate/Troubleshooting-Tip-FortiToken-Mobile-push-notification-issue/ta-p/277343), [Fortinet docs](https://docs.fortinet.com/document/fortigate/6.4.0/administration-guide/183204/ssl-vpn-with-fortitoken-mobile-push-authentication)
- Push is not supported with IKEv1. If push is enabled globally, FTM users cannot log in to IKEv1 dial-up (search summary). [Fortinet Community](https://community.fortinet.com/t5/FortiGate/Technical-Tip-FortiToken-Mobile-push-notification/ta-p/195578)
- Users missed the FortiClient auth-request notification and thought the VPN was down (search snippet). [Cisco Community thread](https://community.cisco.com/t5/protecting-applications/forticlient-ssl-vpn-notification/m-p/4878793/highlight/true)
- Save password: the FortiGate portal setting "allow client to save password" must be on. EMS profiles can force `<show_remember_password>0`. Users report it greyed out or not working (for example 7.0.2.0069). [Fortinet Community](https://community.fortinet.com/t5/Support-Forum/Saving-Password-does-not-work-with-Forti-CLient-VPN-7-0-2-0069/td-p/204205), [Fortinet Community](https://community.fortinet.com/t5/Support-Forum/Fortigate-60F-SSL-VPN-Portal-quot-allow-client-to-save-password/td-p/248314), [Fortinet Community](https://community.fortinet.com/support-forum-92/ems-forticlient-vpn-remember-password-restricted-116647)
- A 48% failure means a missing, wrong or expired token code. [BOLL Tech Blog](https://blog.boll.ch/troubleshooting-the-fortigate-sslvpn/)

### Inferences
- With default settings, a user who mistypes a code once and then retries a slow emailed code can be locked out for 60 s after the second failure. The client shows a generic error, not "locked, wait N s".
- Emailed OTP with a 60 s expiry is tight whenever mail delivery lags. This matches this project's own gotcha ("code expires in about a minute"). Automatically reading the code (as the Blanarch IMAP check does) directly addresses the friction.
- No source confirmed whether FortiClient keeps the password when a retry is needed after a code expires. Anecdotally users re-enter it, but that is unverified.

### Gaps
- No primary user reports (Reddit) about push delays or re-entering the password on each retry.
- No data on how often push notifications fail to arrive.

## Q3. SAML/SSO issues (embedded browser, Entra conditional access, external browser, MFA after SAML)

### Takeaway
SAML problems cluster around the embedded browser (blank screens, cached sessions, no device identity for conditional access), a too-short `remoteauthtimeout` (shown as -6005 "unreachable"), and signing-certificate changes after FortiOS upgrades. Fortinet's fix is the external-browser option (FortiClient 7.0.1+, local port 8020).

### Cited Findings
- External browser as SAML user-agent needs FortiClient 7.0.1+. It uses local redirect port 8020, and the client warns if that port is taken. It reuses an existing browser SSO session. [Fortinet docs 7.6.2](https://docs.fortinet.com/document/fortigate/7.6.2/administration-guide/364443/using-a-browser-as-an-external-user-agent-for-saml-authentication-in-an-ssl-vpn-connection), [FortiClient 7.4.7 EMS guide](https://docs.fortinet.com/document/forticlient/7.4.7/ems-administration-guide/748803/using-a-browser-as-an-external-user-agent-for-saml-authentication-in-an-ssl-vpn-connection)
- Blank screen after Azure SAML login in FortiClient 7.2.4+ (IPsec dial-up). The fix is switching `<after_logon_saml_auth>` to Electron or WebView2. Electron support arrived in 7.2.9 and 7.4.1+. [Fortinet Community](https://community.fortinet.com/t5/FortiGate/Troubleshooting-Tip-Blank-screen-on-FortiClient-while-connecting/ta-p/379845)
- Forum complaints include "Horrible blank window on login", iOS SAML blank page, and how to clear cached SAML cookies with Entra in 7.2.8. [Fortinet Community](https://community.fortinet.com/t5/Support-Forum/Horrible-blank-window-on-login-to-FortiClient-VPN/m-p/290477), [Fortinet Community iOS](https://community.fortinet.com/t5/Support-Forum/iOS-FortiClientVPN-SSO-SAML-displaying-blank-page/m-p/204564), [Fortinet Community](https://community.fortinet.com/support-forum-92/forticlient-7-2-8-ipsec-clear-saml-cache-cookies-entra-azure-197576)
- A SAML timeout surfaces as -6005 "server may be unreachable". The fix is raising `remoteauthtimeout` (5 s to 180 s) and using the Entra "Sign SAML Response and Assertion" option after 7.2.12/7.4.9/7.6.4 upgrades. [Fortinet Community](https://community.fortinet.com/t5/FortiGate/Troubleshooting-Tip-How-to-fix-the-error-Unable-to-establish-VPN/ta-p/274253), [Fortinet forum: SAML auth timeout](https://community.fortinet.com/t5/Support-Forum/Forticlient-SAML-Authentication-timeout/m-p/357943)
- "The authentication did not complete within the specified timeout" is the SAML-too-slow message. [BOLL Tech Blog](https://blog.boll.ch/troubleshooting-the-fortigate-sslvpn/)
- Entra + FortiGate: some users need several attempts with 7.2.x. About 1% of users get "No group info in SAML response". [Microsoft Q&A](https://learn.microsoft.com/en-us/answers/questions/1663138/microsoft-entra-sso-integration-with-fortigate-ssl), [Microsoft Q&A](https://learn.microsoft.com/en-us/answers/a/1227903)
- Creative Cloud-installed certificates blocked the FortiClient SAML/Entra login. [Adobe Community](https://community.adobe.com/questions-624/forticlient-vpn-client-login-blocked-by-creative-cloud-certificates-681889)
- Conditional access "device compliant" fails in embedded VPN browsers that do not pass device ID. The documented case is Cisco AnyConnect, and FortiClient is only analogous (inference). [Cisco Community](https://community.cisco.com/t5/security-knowledge-base/anyconnect-azure-ad-saml-sso/tac-p/4481279), [Microsoft Q&A](https://learn.microsoft.com/en-us/answers/questions/335679/conditional-access-with-azure-ad-registered-device)

### Inferences
- SAML failures are reported as "server unreachable", which sends users and help desks down the wrong path.
- Embedded-browser engine churn (IE, then WebView2, then Electron) has produced regressions across FortiClient versions.

### Gaps
- No FortiClient-specific primary source on Entra conditional-access loops.
- Nothing found on "MFA after SAML breaking" beyond timeout causes.

## Q4. Session drops (idle timeout, DTLS vs TLS, auth-timeout, reconnect needing full re-login)

### Takeaway
Defaults force re-authentication every 8 h (`auth-timeout` 28800 s) and cut idle sessions at 5 min (`idle-timeout` 300 s). DTLS is on by default, and disabling it (or sometimes enabling it) is the standard fix for random drops. Auto-reconnect and always-up need the EMS-licensed client, so the free client needs a full re-login, including MFA.

### Cited Findings
- `idle-timeout` 300 s, `auth-timeout` 28800 s (range up to 259200), `dtls-hello-timeout` 10 s. [Fortinet Community](https://community.fortinet.com/fortigate-3/technical-tip-ssl-vpn-timers-explanation-and-ssl-vpn-login-attempt-limit-aka-lockout-102761)
- Recurring "logout after 8 hours" and "drops every 8 hours" threads. [Fortinet Community](https://community.fortinet.com/fortigate-3/technical-tip-ssl-vpn-connection-logout-after-8-hours-93836), [Fortinet Community](https://community.fortinet.com/support-forum-92/forticlient-connection-drops-every-8-hours-175607)
- Auto connect and always up only work with EMS (licensed FortiClient). [51SEC blog, Nov 2024](https://blog.51sec.org/2024/11/forticlient-advanced-features-idle.html)
- Disconnection causes per Fortinet: conflicting VPN apps (AnyConnect), traffic shapers or DoS policies, SD-WAN multiple WANs (fix `preserve-session-route`), client sleep, timeouts, and a session limit ("Deleted to make way for another session"). Test DTLS versus TLS. [Fortinet Community](https://community.fortinet.com/t5/FortiGate/Technical-Tip-SSL-VPN-disconnection-issues-when-connected-with/ta-p/207851)
- DTLS: disabling it server-side forces TLS for everyone (`set dtls-tunnel disable`). Admins report it as a fix for drops. [SAMURAJ-cz snippet](https://www.samuraj-cz.com/en/article/fortigate-problems-connecting-to-ssl-vpn-via-forticlient/). A third-party guide instead calls switching to UDP/DTLS the most effective fix, and blames DPD timeouts and MTU. [0nol.com](https://0nol.com/fortinet/troubleshooting-forticlient-vpn-disconnections.html) (low-authority source). The two conflict, so the right transport depends on the path.

### Inferences
- For a free or unmanaged client, every drop (sleep, Wi-Fi change, 8 h timer) means a full login plus a new OTP. That is where MFA friction adds up.

### Gaps
- No data on whether FortiClient re-uses its session cookie to reconnect without re-authenticating after brief network changes.

## Q5. Certificate warnings and click-through

### Takeaway
Many FortiGates serve the factory self-signed certificate. FortiClient then shows "The Certificate Issuer for this site is Untrusted or unknown" and offers a per-connection "Do not warn invalid server certificate" option, which trains users to click through.

### Cited Findings
- The untrusted-issuer warning appears when the FortiGate uses the self-signed Fortinet_Factory certificate. [Fortinet Community](https://community.fortinet.com/t5/FortiGate/Technical-Tip-How-to-fix-FortiClient-VPN-certificate-error-The/ta-p/368678)
- A name-mismatch warning ("A secure connection with this site cannot be verified... does not match the name of the site") is also covered. [Fortinet Community](https://community.fortinet.com/t5/FortiGate/Technical-Tip-How-to-fix-certificate-warning-A-secure-connection/ta-p/303467)
- Other FortiClient tips: "untrusted certificate errors" and "certificate revoked" warnings. [Fortinet Community](https://community.fortinet.com/t5/FortiGate/Troubleshooting-Tip-How-to-resolve-FortiClient-untrusted/ta-p/337214), [Fortinet Community](https://community.fortinet.com/t5/FortiClient/Troubleshooting-Tip-FortiClient-error-The-security-certificate/ta-p/369416)
- The "Do not Warn Invalid Server Certificate" option lets users connect, but it is acknowledged as not fixing the issue. [Fortinet Community](https://community.fortinet.com/t5/Support-Forum/Certificate-inspection-untrusted-certificate-warning-broken-5-4/m-p/938) (search-summary level)
- Certificate prompts can stall at 40%. [Fortinet Community](https://community.fortinet.com/t5/Support-Forum/VPN-Client-stuck-at-40-with-certificate-error/m-p/199142), [percentage map](https://community.fortinet.com/t5/FortiGate/Troubleshooting-Tip-Possible-reasons-for-FortiClient-SSL-VPN/ta-p/211965)

### Inferences
- The FortiClient model is a yes/no "untrusted, continue?" prompt plus a global suppress option. It has no fingerprint display or pinning, so users learn to accept any certificate, including a MITM one. Blanarch's "confirm fingerprint, then pin per host" design directly addresses this.

### Gaps
- No survey data on how often users click through.
- No help-desk KB found that explicitly tells users to click "Yes", though that is commonly reported anecdotally.
