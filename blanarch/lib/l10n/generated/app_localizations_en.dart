// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get splashTagline => 'PRIVATE ACCESS  ·  ANYWHERE';

  @override
  String get phaseIdle => 'Not connected';

  @override
  String get phaseConnecting => 'Connecting';

  @override
  String get phaseConnected => 'Connected';

  @override
  String get phaseReconnecting => 'Reconnecting';

  @override
  String get phaseDisconnecting => 'Disconnecting';

  @override
  String get phaseError => 'Couldn’t connect';

  @override
  String get tapToConnect => 'Tap to connect';

  @override
  String get stepGateway => 'Reaching the server';

  @override
  String get stepSigningIn => 'Signing in';

  @override
  String get stepWaitingCode => 'Waiting for the code';

  @override
  String get stepApproval => 'Waiting for your approval';

  @override
  String get stepSso => 'Signing in with your company';

  @override
  String stepVerifying(String code) {
    return 'Verifying code $code';
  }

  @override
  String get stepTunnel => 'Opening the tunnel';

  @override
  String tunnelIp(String ip) {
    return 'IP $ip';
  }

  @override
  String get actionConnect => 'Connect';

  @override
  String get actionDisconnect => 'Disconnect';

  @override
  String get actionCancelConnecting => 'Cancel connecting';

  @override
  String get settingsTooltip => 'Settings';

  @override
  String get addConnection => 'Add connection';

  @override
  String get vpnPermissionNeeded => 'Allow the VPN permission to connect';

  @override
  String get checkingInbox => 'Checking your inbox…';

  @override
  String get enterCodeTitle => 'Enter your code';

  @override
  String get typeCode => 'Type the code';

  @override
  String get fix => 'Fix';

  @override
  String get codeHint => 'Code';

  @override
  String get codeExpiresHint =>
      'Enter the newest code quickly. It expires in about a minute.';

  @override
  String get waitingPushTitle => 'Approve on your phone';

  @override
  String get waitingPushBody =>
      'Open your authenticator app, like FortiToken, and approve the sign-in.';

  @override
  String get useCodeInstead => 'Use a code instead';

  @override
  String get waitingSsoTitle => 'Finish signing in';

  @override
  String get waitingSsoBody =>
      'Your company’s sign-in page is open in the browser. Come back here when you’re done.';

  @override
  String get openSignInPage => 'Open sign-in page';

  @override
  String get noProfilesTitle => 'Add your company VPN';

  @override
  String get noProfilesBody =>
      'You’ll need the address your IT team uses, like vpn.company.com.';

  @override
  String get details => 'Details';

  @override
  String get tryAgain => 'Try again';

  @override
  String get editConnection => 'Edit connection';

  @override
  String get reviewCertificate => 'Review certificate';

  @override
  String get whatYouCanDo => 'What you can do';

  @override
  String get technicalDetails => 'Technical details';

  @override
  String get copy => 'Copy';

  @override
  String get copied => 'Copied';

  @override
  String get errorNoVpnPassword => 'Add your VPN password first';

  @override
  String get errorAuthRejected =>
      'The server rejected your username or password';

  @override
  String get errorUnsupportedChallenge =>
      'The server asked for a sign-in method this app doesn’t support yet';

  @override
  String get errorCertMismatch =>
      'The server’s certificate changed, so the connection was blocked';

  @override
  String get errorCertUntrusted => 'The server’s certificate isn’t trusted yet';

  @override
  String get errorSsoTimeout => 'Signing in in the browser took too long';

  @override
  String get errorSsoFailed => 'Single sign-on couldn’t start';

  @override
  String get errorNoProfile => 'Add a connection first';

  @override
  String get errorInvalidAddress => 'That doesn’t look like a server address';

  @override
  String get errorPermissionRevoked =>
      'The Android VPN permission was turned off';

  @override
  String errorOutOfAttempts(int count) {
    return 'Tried $count times without success';
  }

  @override
  String get errorOtpTimeout => 'The code didn’t arrive in time';

  @override
  String get errorOtpRejected => 'The code was wrong or had expired';

  @override
  String get errorGatewayUnreachable => 'The server isn’t responding';

  @override
  String get errorTunnelRefused =>
      'The server doesn’t allow tunnel mode for your account';

  @override
  String get errorProtocol => 'The server sent an unexpected reply';

  @override
  String get errorLinkLost => 'The connection dropped';

  @override
  String get errorEmailAuthFailed => 'Email password was rejected';

  @override
  String get errorEmailUnreachable => 'Can’t reach your mailbox';

  @override
  String get errorEmailNotConfigured => 'No email password saved';

  @override
  String get fixAuthRejected =>
      'If your password changed recently, update it here. Trying the old one again can lock your account.';

  @override
  String get fixGatewayUnreachable =>
      'Check the address and your internet connection. If you’re on a guest Wi-Fi, try mobile data.';

  @override
  String get fixCertUntrusted =>
      'Your phone hasn’t seen this address before. Trust it if it belongs to your company VPN. The app will warn you if its certificate ever changes.';

  @override
  String get fixCertMismatch =>
      'Don’t trust the new certificate unless your IT team confirms the server changed.';

  @override
  String get fixOtp =>
      'Try again and enter the newest code right away. Codes usually expire after a minute.';

  @override
  String get fixTunnelRefused =>
      'Ask your IT team to enable tunnel mode (FortiClient access) for your account.';

  @override
  String get fixGeneric =>
      'Try again. If it keeps failing, share the activity log with your IT team.';

  @override
  String get back => 'Back';

  @override
  String get cancel => 'Cancel';

  @override
  String get continueAction => 'Continue';

  @override
  String get done => 'Done';

  @override
  String get save => 'Save';

  @override
  String get change => 'Change';

  @override
  String get remove => 'Remove';

  @override
  String get delete => 'Delete';

  @override
  String get off => 'Off';

  @override
  String get optional => 'Optional';

  @override
  String get advanced => 'Advanced';

  @override
  String get showPassword => 'Show password';

  @override
  String get hidePassword => 'Hide password';

  @override
  String get welcomeTitle => 'Private access,\nin one tap.';

  @override
  String get welcomeBody =>
      'Connect to your company’s FortiGate VPN with clear errors, codes read for you, and no repeated passwords.';

  @override
  String get featureSignInTitle => 'Signs in for you';

  @override
  String get featureSignInBody =>
      'Your password is saved once, encrypted on this phone.';

  @override
  String get featureCodeTitle => 'Handles the second step';

  @override
  String get featureCodeBody =>
      'Push approval, codes, or reading the code from your email.';

  @override
  String get featureRetryTitle => 'Keeps you connected';

  @override
  String get featureRetryBody =>
      'Retries and switches servers until it connects.';

  @override
  String get setUp => 'Set up';

  @override
  String get addressTitle => 'Your company VPN';

  @override
  String get addressBody =>
      'Enter the address your IT team gave you. It usually looks like vpn.company.com, sometimes with a port.';

  @override
  String get addressLabel => 'VPN address';

  @override
  String get checkingServer => 'Checking the server…';

  @override
  String get certTitle => 'A new server';

  @override
  String certBody(String host) {
    return 'This is the first time your phone sees $host. Company VPNs often use their own certificate, so this is normal. Continue if this is the address your IT team gave you. The app will warn you if it ever changes.';
  }

  @override
  String get certChangedTitle => 'This server changed';

  @override
  String certChangedBody(String host) {
    return 'The certificate for $host is different from the one you trusted. Someone could be intercepting the connection. Ask your IT team before you trust it.';
  }

  @override
  String get certFingerprint => 'Fingerprint (SHA-256)';

  @override
  String get certDontConnect => 'Don’t connect';

  @override
  String get certTrust => 'Trust this server';

  @override
  String get signInTitle => 'How do you sign in?';

  @override
  String get signInBody => 'Use the same account as on your computer.';

  @override
  String get methodPassword => 'Username and password';

  @override
  String get methodSso => 'Company account (single sign-on)';

  @override
  String get ssoExplain =>
      'Each time you connect, your company’s sign-in page opens in the browser.';

  @override
  String get usernameLabel => 'Username';

  @override
  String get passwordLabel => 'Password';

  @override
  String get nameLabel => 'Name for this connection';

  @override
  String get realmLabel => 'Realm';

  @override
  String get backupAddressesLabel => 'Backup addresses, one per line';

  @override
  String get emailStepTitle => 'Let it read the code';

  @override
  String get emailStepBody =>
      'If your company emails you the sign-in code, the app can find it in your inbox and finish for you. Nothing to copy.';

  @override
  String get emailAddressLabel => 'Email address';

  @override
  String get emailPasswordLabel => 'Email password';

  @override
  String get imapServerLabel => 'Mail server (IMAP)';

  @override
  String get senderLabel => 'Only codes from this sender';

  @override
  String get verifyAndContinue => 'Verify & continue';

  @override
  String get skipEmailCodes => 'Skip, I’ll type codes myself';

  @override
  String get permissionsTitle => 'Before you connect';

  @override
  String get permissionsBody =>
      'Android asks once for each permission. You can change them later in system settings.';

  @override
  String get permissionVpnTitle => 'VPN connection';

  @override
  String get permissionVpnBody =>
      'Lets the app create the secure tunnel on this phone.';

  @override
  String get permissionNotificationsTitle => 'Notifications';

  @override
  String get permissionNotificationsBody =>
      'Shows the connection status with a quick Disconnect button.';

  @override
  String get disclosureTitle => 'What the app accesses';

  @override
  String get disclosureBody =>
      'The app connects only to the VPN servers and mailbox you add. Passwords stay encrypted on this phone and are never shared. If you turn on email codes, it reads new messages in that mailbox only to find the sign-in code.';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get appearance => 'Appearance';

  @override
  String get themeAuto => 'Auto';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeAutoHint => 'Auto follows your phone’s setting.';

  @override
  String get connections => 'Connections';

  @override
  String get diagnostics => 'Diagnostics';

  @override
  String get activityLog => 'Activity log';

  @override
  String versionLine(String version) {
    return 'Version $version';
  }

  @override
  String get saved => 'Saved';

  @override
  String get notSet => 'Not set';

  @override
  String get secondFactorLabel => 'Second step';

  @override
  String get secondFactorAuto => 'Push when available';

  @override
  String get secondFactorCode => 'Always a code';

  @override
  String get emailCodesLabel => 'Read codes from email';

  @override
  String get deleteConnection => 'Delete connection';

  @override
  String deleteConfirm(String name) {
    return 'Delete $name? Its saved passwords are removed too.';
  }

  @override
  String get activityTitle => 'Activity';

  @override
  String get nothingYet => 'Nothing yet';

  @override
  String get scanQr => 'Scan QR code';

  @override
  String get scanQrHint =>
      'Point the camera at the setup code from your IT team or a colleague.';

  @override
  String get notASetupCode => 'That QR code isn’t a connection setup code';

  @override
  String get linkMismatchTitle => 'Fingerprint doesn’t match';

  @override
  String linkMismatchBody(String host) {
    return 'The certificate of $host is different from the one in the setup code you used. Don’t connect unless your IT team confirms the server changed.';
  }

  @override
  String get shareSetup => 'Share setup';

  @override
  String get shareSetupBody =>
      'Colleagues can scan this to add the same connection. Passwords are never included.';

  @override
  String get includeUsername => 'Include my username';

  @override
  String get copyLink => 'Copy link';

  @override
  String get security => 'Security';

  @override
  String get appLock => 'App lock';

  @override
  String get appLockHint =>
      'Confirm it’s you with fingerprint or face before saved passwords are used.';

  @override
  String get appLockUnavailable =>
      'Set a screen lock on your phone to use this.';

  @override
  String get alwaysOn => 'Always-on VPN';

  @override
  String get alwaysOnHint =>
      'Keep the VPN on and block connections without it. Opens Android’s VPN settings.';

  @override
  String get errorLocked => 'Unlock the app to use your saved password';

  @override
  String get fixLocked =>
      'Open the app and connect from there, or turn off the app lock in Settings.';

  @override
  String get enterCodeBody =>
      'Type the code from your email, text message or authenticator app.';

  @override
  String get submitCode => 'Send code';

  @override
  String timeLeft(int seconds) {
    return '$seconds s left';
  }

  @override
  String get updatePassword => 'Update password';

  @override
  String get fixOutOfAttempts =>
      'None of the server addresses answered. If other apps work, the VPN may be down, so ask your IT team.';

  @override
  String get fixUnsupportedChallenge =>
      'Share the activity log with your IT team so they can see which sign-in method your account needs.';

  @override
  String get showFingerprint => 'Show fingerprint';

  @override
  String get hideFingerprint => 'Hide fingerprint';

  @override
  String get certTrustContinue => 'Trust and continue';

  @override
  String get realmHint => 'Only if your IT team gave you one';

  @override
  String get agreeAndConnect => 'Agree & connect';

  @override
  String stepOf(int step, int total) {
    return 'Step $step of $total';
  }

  @override
  String connectTo(String name) {
    return 'Connect to $name';
  }

  @override
  String get shareLog => 'Share';

  @override
  String get quickTile => 'Quick Settings tile';

  @override
  String get quickTileHint =>
      'Connect from the panel you swipe down from the top of the screen.';

  @override
  String get switchWhileConnected => 'Disconnect to switch connections';

  @override
  String get logOk => 'Success';

  @override
  String get logError => 'Error';

  @override
  String get logInfo => 'Info';

  @override
  String get shortcuts => 'Shortcuts';

  @override
  String get shareLogSubject => 'Blanarch activity log';

  @override
  String get stepChipServer => 'Server';

  @override
  String get stepChipSignIn => 'Sign in';

  @override
  String get stepChipTunnel => 'Tunnel';

  @override
  String reachingHost(String host) {
    return 'Reaching $host';
  }

  @override
  String attemptOf(int attempt, int total, String host) {
    return 'Attempt $attempt of $total · $host';
  }

  @override
  String lastTry(String reason) {
    return 'Last try: $reason';
  }

  @override
  String tryingFor(String time) {
    return 'Trying for $time';
  }

  @override
  String progressOf(int step, int total, String name) {
    return 'Step $step of $total, $name';
  }

  @override
  String get activity => 'Activity';

  @override
  String get seeAll => 'See all';

  @override
  String eventStarting(String name) {
    return 'Starting $name';
  }

  @override
  String eventAttempt(String attempt, String total, String address) {
    return 'Attempt $attempt of $total · $address';
  }

  @override
  String eventSigningIn(String user) {
    return 'Signing in as $user';
  }

  @override
  String get eventSignedIn => 'Signed in';

  @override
  String get eventWaitingSso => 'Waiting for sign-in in the browser';

  @override
  String get eventApprovePush => 'Waiting for approval on your phone';

  @override
  String eventCodeReceived(String code) {
    return 'Got code $code. Checking it';
  }

  @override
  String eventConnected(String ip) {
    return 'Connected · IP $ip';
  }

  @override
  String get eventConnectionLost => 'The connection dropped';

  @override
  String get eventReconnecting => 'Reconnecting';

  @override
  String get eventDisconnected => 'Disconnected';

  @override
  String checkingHost(String host) {
    return 'Checking $host…';
  }

  @override
  String get factTunnelIp => 'Tunnel IP';

  @override
  String get factGateway => 'Gateway';

  @override
  String get factRouting => 'Routing';

  @override
  String get factDns => 'DNS';

  @override
  String get factTraffic => 'Traffic';

  @override
  String get factSignedIn => 'Signed in';

  @override
  String get routingAll => 'All traffic';

  @override
  String routingSplit(int count) {
    return 'Split tunnel · $count routes';
  }

  @override
  String get backupAddress => 'backup address';

  @override
  String get signInPassword => 'password';

  @override
  String get signInCode => 'code';

  @override
  String get signInPush => 'push approval';

  @override
  String get signInSso => 'single sign-on';

  @override
  String get certPinnedMatches => 'Certificate pinned · matches';

  @override
  String get certSystemTrusted => 'Certificate trusted by the system';

  @override
  String get allDetails => 'All details';

  @override
  String get detailsTitle => 'Connection details';

  @override
  String get sectionNetwork => 'Network';

  @override
  String get sectionServer => 'Server';

  @override
  String get sectionSession => 'Session';

  @override
  String get dnsServers => 'DNS servers';

  @override
  String get searchDomain => 'Search domain';

  @override
  String get routesLabel => 'Routes';

  @override
  String get mtuLabel => 'MTU';

  @override
  String get certificateLabel => 'Certificate';

  @override
  String get pinned => 'pinned';

  @override
  String get encryptionLabel => 'Encryption';

  @override
  String get latencyLabel => 'Latency';

  @override
  String get userLabel => 'User';

  @override
  String get signInLabel => 'Sign-in';

  @override
  String get connectedSinceLabel => 'Connected since';

  @override
  String get reconnectsLabel => 'Reconnects';

  @override
  String get addressesTried => 'Addresses tried';

  @override
  String get copyAll => 'Copy all';

  @override
  String get shareWithIt => 'Share with IT';

  @override
  String get detailsShareSubject => 'Blanarch connection details';

  @override
  String get measuring => 'measuring';

  @override
  String get notReported => 'Not reported';

  @override
  String millis(int ms) {
    return '$ms ms';
  }

  @override
  String copyValue(String label) {
    return 'Copy $label';
  }

  @override
  String get backupShort => 'backup';

  @override
  String get phaseWaitingNetwork => 'Waiting for a network';

  @override
  String get stepWaitingNetwork => 'Waiting for Wi-Fi or mobile data';

  @override
  String get errorNetworkChanged => 'The network changed';

  @override
  String get errorNoNetwork => 'No internet connection';

  @override
  String get errorSessionExpired => 'The session expired';

  @override
  String get fixNoNetwork =>
      'Turn on Wi-Fi or mobile data. The app reconnects by itself when the network is back.';

  @override
  String get eventNetworkLost => 'No network · waiting';

  @override
  String get eventNetworkBack => 'Network back';

  @override
  String get eventNetworkChanged => 'Network changed · rejoining';

  @override
  String get eventSessionExpired => 'Session expired · signing in again';

  @override
  String eventDnsFallback(String servers) {
    return 'The server gave no DNS. Using $servers through the tunnel';
  }

  @override
  String reconnectedAfter(String reason) {
    return 'Reconnected · $reason';
  }

  @override
  String get errorSslVpnOff => 'This server doesn’t offer SSL-VPN';

  @override
  String get errorClientCertRequired =>
      'This server asks for a client certificate';

  @override
  String get fixSslVpnOff =>
      'It may have moved to IPsec, which Blanarch will support soon. Ask your IT team whether SSL-VPN is still available and at which address.';

  @override
  String get fixClientCert =>
      'Blanarch doesn’t use client certificates yet. Some servers ask for one without requiring it, so you can still try.';

  @override
  String get ipsecAnswers =>
      'The server answers IPsec (IKEv2), so it probably uses IPsec now.';

  @override
  String get unsupportedTitle => 'This server may not work yet';

  @override
  String get tellIt => 'What to ask IT';

  @override
  String tellItSslOff(String host) {
    return 'Is SSL-VPN tunnel mode still enabled on $host? If our FortiGate moved to IPsec, what are the IPsec settings?';
  }

  @override
  String tellItClientCert(String host) {
    return 'Does $host require a client certificate for the VPN, or is it optional?';
  }

  @override
  String get tryAnotherAddress => 'Try another address';

  @override
  String get continueAnyway => 'Continue anyway';
}
