import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
  ];

  /// No description provided for @splashTagline.
  ///
  /// In en, this message translates to:
  /// **'PRIVATE ACCESS  ·  ANYWHERE'**
  String get splashTagline;

  /// No description provided for @phaseIdle.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get phaseIdle;

  /// No description provided for @phaseConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get phaseConnecting;

  /// No description provided for @phaseConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get phaseConnected;

  /// No description provided for @phaseReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting'**
  String get phaseReconnecting;

  /// No description provided for @phaseDisconnecting.
  ///
  /// In en, this message translates to:
  /// **'Disconnecting'**
  String get phaseDisconnecting;

  /// No description provided for @phaseError.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t connect'**
  String get phaseError;

  /// No description provided for @tapToConnect.
  ///
  /// In en, this message translates to:
  /// **'Tap to connect'**
  String get tapToConnect;

  /// No description provided for @stepGateway.
  ///
  /// In en, this message translates to:
  /// **'Reaching the server'**
  String get stepGateway;

  /// No description provided for @stepSigningIn.
  ///
  /// In en, this message translates to:
  /// **'Signing in'**
  String get stepSigningIn;

  /// No description provided for @stepWaitingCode.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the code'**
  String get stepWaitingCode;

  /// No description provided for @stepApproval.
  ///
  /// In en, this message translates to:
  /// **'Waiting for your approval'**
  String get stepApproval;

  /// No description provided for @stepSso.
  ///
  /// In en, this message translates to:
  /// **'Signing in with your company'**
  String get stepSso;

  /// No description provided for @stepVerifying.
  ///
  /// In en, this message translates to:
  /// **'Verifying code {code}'**
  String stepVerifying(String code);

  /// No description provided for @stepTunnel.
  ///
  /// In en, this message translates to:
  /// **'Opening the tunnel'**
  String get stepTunnel;

  /// No description provided for @tunnelIp.
  ///
  /// In en, this message translates to:
  /// **'IP {ip}'**
  String tunnelIp(String ip);

  /// No description provided for @actionConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get actionConnect;

  /// No description provided for @actionDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get actionDisconnect;

  /// No description provided for @actionCancelConnecting.
  ///
  /// In en, this message translates to:
  /// **'Cancel connecting'**
  String get actionCancelConnecting;

  /// No description provided for @settingsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTooltip;

  /// No description provided for @addConnection.
  ///
  /// In en, this message translates to:
  /// **'Add connection'**
  String get addConnection;

  /// No description provided for @vpnPermissionNeeded.
  ///
  /// In en, this message translates to:
  /// **'Allow the VPN permission to connect'**
  String get vpnPermissionNeeded;

  /// No description provided for @checkingInbox.
  ///
  /// In en, this message translates to:
  /// **'Checking your inbox…'**
  String get checkingInbox;

  /// No description provided for @enterCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your code'**
  String get enterCodeTitle;

  /// No description provided for @typeCode.
  ///
  /// In en, this message translates to:
  /// **'Type the code'**
  String get typeCode;

  /// No description provided for @fix.
  ///
  /// In en, this message translates to:
  /// **'Fix'**
  String get fix;

  /// No description provided for @codeHint.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get codeHint;

  /// No description provided for @codeExpiresHint.
  ///
  /// In en, this message translates to:
  /// **'Enter the newest code quickly. It expires in about a minute.'**
  String get codeExpiresHint;

  /// No description provided for @waitingPushTitle.
  ///
  /// In en, this message translates to:
  /// **'Approve on your phone'**
  String get waitingPushTitle;

  /// No description provided for @waitingPushBody.
  ///
  /// In en, this message translates to:
  /// **'Open your authenticator app, like FortiToken, and approve the sign-in.'**
  String get waitingPushBody;

  /// No description provided for @useCodeInstead.
  ///
  /// In en, this message translates to:
  /// **'Use a code instead'**
  String get useCodeInstead;

  /// No description provided for @waitingSsoTitle.
  ///
  /// In en, this message translates to:
  /// **'Finish signing in'**
  String get waitingSsoTitle;

  /// No description provided for @waitingSsoBody.
  ///
  /// In en, this message translates to:
  /// **'Your company’s sign-in page is open in the browser. Come back here when you’re done.'**
  String get waitingSsoBody;

  /// No description provided for @openSignInPage.
  ///
  /// In en, this message translates to:
  /// **'Open sign-in page'**
  String get openSignInPage;

  /// No description provided for @noProfilesTitle.
  ///
  /// In en, this message translates to:
  /// **'Add your company VPN'**
  String get noProfilesTitle;

  /// No description provided for @noProfilesBody.
  ///
  /// In en, this message translates to:
  /// **'You’ll need the address your IT team uses, like vpn.company.com.'**
  String get noProfilesBody;

  /// No description provided for @details.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get details;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @editConnection.
  ///
  /// In en, this message translates to:
  /// **'Edit connection'**
  String get editConnection;

  /// No description provided for @reviewCertificate.
  ///
  /// In en, this message translates to:
  /// **'Review certificate'**
  String get reviewCertificate;

  /// No description provided for @whatYouCanDo.
  ///
  /// In en, this message translates to:
  /// **'What you can do'**
  String get whatYouCanDo;

  /// No description provided for @technicalDetails.
  ///
  /// In en, this message translates to:
  /// **'Technical details'**
  String get technicalDetails;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @errorNoVpnPassword.
  ///
  /// In en, this message translates to:
  /// **'Add your VPN password first'**
  String get errorNoVpnPassword;

  /// No description provided for @errorAuthRejected.
  ///
  /// In en, this message translates to:
  /// **'The server rejected your username or password'**
  String get errorAuthRejected;

  /// No description provided for @errorUnsupportedChallenge.
  ///
  /// In en, this message translates to:
  /// **'The server asked for a sign-in method this app doesn’t support yet'**
  String get errorUnsupportedChallenge;

  /// No description provided for @errorCertMismatch.
  ///
  /// In en, this message translates to:
  /// **'The server’s certificate changed, so the connection was blocked'**
  String get errorCertMismatch;

  /// No description provided for @errorCertUntrusted.
  ///
  /// In en, this message translates to:
  /// **'The server’s certificate isn’t trusted yet'**
  String get errorCertUntrusted;

  /// No description provided for @errorSsoTimeout.
  ///
  /// In en, this message translates to:
  /// **'Signing in in the browser took too long'**
  String get errorSsoTimeout;

  /// No description provided for @errorSsoFailed.
  ///
  /// In en, this message translates to:
  /// **'Single sign-on couldn’t start'**
  String get errorSsoFailed;

  /// No description provided for @errorNoProfile.
  ///
  /// In en, this message translates to:
  /// **'Add a connection first'**
  String get errorNoProfile;

  /// No description provided for @errorInvalidAddress.
  ///
  /// In en, this message translates to:
  /// **'That doesn’t look like a server address'**
  String get errorInvalidAddress;

  /// No description provided for @errorPermissionRevoked.
  ///
  /// In en, this message translates to:
  /// **'The Android VPN permission was turned off'**
  String get errorPermissionRevoked;

  /// No description provided for @errorOutOfAttempts.
  ///
  /// In en, this message translates to:
  /// **'Tried {count} times without success'**
  String errorOutOfAttempts(int count);

  /// No description provided for @errorOtpTimeout.
  ///
  /// In en, this message translates to:
  /// **'The code didn’t arrive in time'**
  String get errorOtpTimeout;

  /// No description provided for @errorOtpRejected.
  ///
  /// In en, this message translates to:
  /// **'The code was wrong or had expired'**
  String get errorOtpRejected;

  /// No description provided for @errorGatewayUnreachable.
  ///
  /// In en, this message translates to:
  /// **'The server isn’t responding'**
  String get errorGatewayUnreachable;

  /// No description provided for @errorTunnelRefused.
  ///
  /// In en, this message translates to:
  /// **'The server doesn’t allow tunnel mode for your account'**
  String get errorTunnelRefused;

  /// No description provided for @errorProtocol.
  ///
  /// In en, this message translates to:
  /// **'The server sent an unexpected reply'**
  String get errorProtocol;

  /// No description provided for @errorLinkLost.
  ///
  /// In en, this message translates to:
  /// **'The connection dropped'**
  String get errorLinkLost;

  /// No description provided for @errorEmailAuthFailed.
  ///
  /// In en, this message translates to:
  /// **'Email password was rejected'**
  String get errorEmailAuthFailed;

  /// No description provided for @errorEmailUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Can’t reach your mailbox'**
  String get errorEmailUnreachable;

  /// No description provided for @errorEmailNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'No email password saved'**
  String get errorEmailNotConfigured;

  /// No description provided for @fixAuthRejected.
  ///
  /// In en, this message translates to:
  /// **'If your password changed recently, update it here. Trying the old one again can lock your account.'**
  String get fixAuthRejected;

  /// No description provided for @fixGatewayUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Check the address and your internet connection. If you’re on a guest Wi-Fi, try mobile data.'**
  String get fixGatewayUnreachable;

  /// No description provided for @fixCertUntrusted.
  ///
  /// In en, this message translates to:
  /// **'Your phone hasn’t seen this address before. Trust it if it belongs to your company VPN. The app will warn you if its certificate ever changes.'**
  String get fixCertUntrusted;

  /// No description provided for @fixCertMismatch.
  ///
  /// In en, this message translates to:
  /// **'Don’t trust the new certificate unless your IT team confirms the server changed.'**
  String get fixCertMismatch;

  /// No description provided for @fixOtp.
  ///
  /// In en, this message translates to:
  /// **'Try again and enter the newest code right away. Codes usually expire after a minute.'**
  String get fixOtp;

  /// No description provided for @fixTunnelRefused.
  ///
  /// In en, this message translates to:
  /// **'Ask your IT team to enable tunnel mode (FortiClient access) for your account.'**
  String get fixTunnelRefused;

  /// No description provided for @fixGeneric.
  ///
  /// In en, this message translates to:
  /// **'Try again. If it keeps failing, share the activity log with your IT team.'**
  String get fixGeneric;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @continueAction.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueAction;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @change.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get change;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @off.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get off;

  /// No description provided for @optional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optional;

  /// No description provided for @advanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get advanced;

  /// No description provided for @showPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get showPassword;

  /// No description provided for @hidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get hidePassword;

  /// No description provided for @welcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Private access,\nin one tap.'**
  String get welcomeTitle;

  /// No description provided for @welcomeBody.
  ///
  /// In en, this message translates to:
  /// **'Connect to your company’s FortiGate VPN with clear errors, codes read for you, and no repeated passwords.'**
  String get welcomeBody;

  /// No description provided for @featureSignInTitle.
  ///
  /// In en, this message translates to:
  /// **'Signs in for you'**
  String get featureSignInTitle;

  /// No description provided for @featureSignInBody.
  ///
  /// In en, this message translates to:
  /// **'Your password is saved once, encrypted on this phone.'**
  String get featureSignInBody;

  /// No description provided for @featureCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Handles the second step'**
  String get featureCodeTitle;

  /// No description provided for @featureCodeBody.
  ///
  /// In en, this message translates to:
  /// **'Push approval, codes, or reading the code from your email.'**
  String get featureCodeBody;

  /// No description provided for @featureRetryTitle.
  ///
  /// In en, this message translates to:
  /// **'Keeps you connected'**
  String get featureRetryTitle;

  /// No description provided for @featureRetryBody.
  ///
  /// In en, this message translates to:
  /// **'Retries and switches servers until it connects.'**
  String get featureRetryBody;

  /// No description provided for @setUp.
  ///
  /// In en, this message translates to:
  /// **'Set up'**
  String get setUp;

  /// No description provided for @addressTitle.
  ///
  /// In en, this message translates to:
  /// **'Your company VPN'**
  String get addressTitle;

  /// No description provided for @addressBody.
  ///
  /// In en, this message translates to:
  /// **'Enter the address your IT team gave you. It usually looks like vpn.company.com, sometimes with a port.'**
  String get addressBody;

  /// No description provided for @addressLabel.
  ///
  /// In en, this message translates to:
  /// **'VPN address'**
  String get addressLabel;

  /// No description provided for @checkingServer.
  ///
  /// In en, this message translates to:
  /// **'Checking the server…'**
  String get checkingServer;

  /// No description provided for @certTitle.
  ///
  /// In en, this message translates to:
  /// **'A new server'**
  String get certTitle;

  /// No description provided for @certBody.
  ///
  /// In en, this message translates to:
  /// **'This is the first time your phone sees {host}. Company VPNs often use their own certificate, so this is normal. Continue if this is the address your IT team gave you. The app will warn you if it ever changes.'**
  String certBody(String host);

  /// No description provided for @certChangedTitle.
  ///
  /// In en, this message translates to:
  /// **'This server changed'**
  String get certChangedTitle;

  /// No description provided for @certChangedBody.
  ///
  /// In en, this message translates to:
  /// **'The certificate for {host} is different from the one you trusted. Someone could be intercepting the connection. Ask your IT team before you trust it.'**
  String certChangedBody(String host);

  /// No description provided for @certFingerprint.
  ///
  /// In en, this message translates to:
  /// **'Fingerprint (SHA-256)'**
  String get certFingerprint;

  /// No description provided for @certDontConnect.
  ///
  /// In en, this message translates to:
  /// **'Don’t connect'**
  String get certDontConnect;

  /// No description provided for @certTrust.
  ///
  /// In en, this message translates to:
  /// **'Trust this server'**
  String get certTrust;

  /// No description provided for @signInTitle.
  ///
  /// In en, this message translates to:
  /// **'How do you sign in?'**
  String get signInTitle;

  /// No description provided for @signInBody.
  ///
  /// In en, this message translates to:
  /// **'Use the same account as on your computer.'**
  String get signInBody;

  /// No description provided for @methodPassword.
  ///
  /// In en, this message translates to:
  /// **'Username and password'**
  String get methodPassword;

  /// No description provided for @methodSso.
  ///
  /// In en, this message translates to:
  /// **'Company account (single sign-on)'**
  String get methodSso;

  /// No description provided for @ssoExplain.
  ///
  /// In en, this message translates to:
  /// **'Each time you connect, your company’s sign-in page opens in the browser.'**
  String get ssoExplain;

  /// No description provided for @usernameLabel.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get usernameLabel;

  /// No description provided for @passwordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// No description provided for @nameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name for this connection'**
  String get nameLabel;

  /// No description provided for @realmLabel.
  ///
  /// In en, this message translates to:
  /// **'Realm'**
  String get realmLabel;

  /// No description provided for @backupAddressesLabel.
  ///
  /// In en, this message translates to:
  /// **'Backup addresses, one per line'**
  String get backupAddressesLabel;

  /// No description provided for @emailStepTitle.
  ///
  /// In en, this message translates to:
  /// **'Let it read the code'**
  String get emailStepTitle;

  /// No description provided for @emailStepBody.
  ///
  /// In en, this message translates to:
  /// **'If your company emails you the sign-in code, the app can find it in your inbox and finish for you. Nothing to copy.'**
  String get emailStepBody;

  /// No description provided for @emailAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'Email address'**
  String get emailAddressLabel;

  /// No description provided for @emailPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Email password'**
  String get emailPasswordLabel;

  /// No description provided for @imapServerLabel.
  ///
  /// In en, this message translates to:
  /// **'Mail server (IMAP)'**
  String get imapServerLabel;

  /// No description provided for @senderLabel.
  ///
  /// In en, this message translates to:
  /// **'Only codes from this sender'**
  String get senderLabel;

  /// No description provided for @verifyAndContinue.
  ///
  /// In en, this message translates to:
  /// **'Verify & continue'**
  String get verifyAndContinue;

  /// No description provided for @skipEmailCodes.
  ///
  /// In en, this message translates to:
  /// **'Skip, I’ll type codes myself'**
  String get skipEmailCodes;

  /// No description provided for @permissionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Before you connect'**
  String get permissionsTitle;

  /// No description provided for @permissionsBody.
  ///
  /// In en, this message translates to:
  /// **'Android asks once for each permission. You can change them later in system settings.'**
  String get permissionsBody;

  /// No description provided for @permissionVpnTitle.
  ///
  /// In en, this message translates to:
  /// **'VPN connection'**
  String get permissionVpnTitle;

  /// No description provided for @permissionVpnBody.
  ///
  /// In en, this message translates to:
  /// **'Lets the app create the secure tunnel on this phone.'**
  String get permissionVpnBody;

  /// No description provided for @permissionNotificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get permissionNotificationsTitle;

  /// No description provided for @permissionNotificationsBody.
  ///
  /// In en, this message translates to:
  /// **'Shows the connection status with a quick Disconnect button.'**
  String get permissionNotificationsBody;

  /// No description provided for @disclosureTitle.
  ///
  /// In en, this message translates to:
  /// **'What the app accesses'**
  String get disclosureTitle;

  /// No description provided for @disclosureBody.
  ///
  /// In en, this message translates to:
  /// **'The app connects only to the VPN servers and mailbox you add. Passwords stay encrypted on this phone and are never shared. If you turn on email codes, it reads new messages in that mailbox only to find the sign-in code.'**
  String get disclosureBody;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @themeAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get themeAuto;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @themeAutoHint.
  ///
  /// In en, this message translates to:
  /// **'Auto follows your phone’s setting.'**
  String get themeAutoHint;

  /// No description provided for @connections.
  ///
  /// In en, this message translates to:
  /// **'Connections'**
  String get connections;

  /// No description provided for @diagnostics.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get diagnostics;

  /// No description provided for @activityLog.
  ///
  /// In en, this message translates to:
  /// **'Activity log'**
  String get activityLog;

  /// No description provided for @versionLine.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String versionLine(String version);

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// No description provided for @notSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get notSet;

  /// No description provided for @secondFactorLabel.
  ///
  /// In en, this message translates to:
  /// **'Second step'**
  String get secondFactorLabel;

  /// No description provided for @secondFactorAuto.
  ///
  /// In en, this message translates to:
  /// **'Push when available'**
  String get secondFactorAuto;

  /// No description provided for @secondFactorCode.
  ///
  /// In en, this message translates to:
  /// **'Always a code'**
  String get secondFactorCode;

  /// No description provided for @emailCodesLabel.
  ///
  /// In en, this message translates to:
  /// **'Read codes from email'**
  String get emailCodesLabel;

  /// No description provided for @deleteConnection.
  ///
  /// In en, this message translates to:
  /// **'Delete connection'**
  String get deleteConnection;

  /// No description provided for @deleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}? Its saved passwords are removed too.'**
  String deleteConfirm(String name);

  /// No description provided for @activityTitle.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get activityTitle;

  /// No description provided for @nothingYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing yet'**
  String get nothingYet;

  /// No description provided for @scanQr.
  ///
  /// In en, this message translates to:
  /// **'Scan QR code'**
  String get scanQr;

  /// No description provided for @scanQrHint.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at the setup code from your IT team or a colleague.'**
  String get scanQrHint;

  /// No description provided for @notASetupCode.
  ///
  /// In en, this message translates to:
  /// **'That QR code isn’t a connection setup code'**
  String get notASetupCode;

  /// No description provided for @linkMismatchTitle.
  ///
  /// In en, this message translates to:
  /// **'Fingerprint doesn’t match'**
  String get linkMismatchTitle;

  /// No description provided for @linkMismatchBody.
  ///
  /// In en, this message translates to:
  /// **'The certificate of {host} is different from the one in the setup code you used. Don’t connect unless your IT team confirms the server changed.'**
  String linkMismatchBody(String host);

  /// No description provided for @shareSetup.
  ///
  /// In en, this message translates to:
  /// **'Share setup'**
  String get shareSetup;

  /// No description provided for @shareSetupBody.
  ///
  /// In en, this message translates to:
  /// **'Colleagues can scan this to add the same connection. Passwords are never included.'**
  String get shareSetupBody;

  /// No description provided for @includeUsername.
  ///
  /// In en, this message translates to:
  /// **'Include my username'**
  String get includeUsername;

  /// No description provided for @copyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get copyLink;

  /// No description provided for @security.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get security;

  /// No description provided for @appLock.
  ///
  /// In en, this message translates to:
  /// **'App lock'**
  String get appLock;

  /// No description provided for @appLockHint.
  ///
  /// In en, this message translates to:
  /// **'Confirm it’s you with fingerprint or face before saved passwords are used.'**
  String get appLockHint;

  /// No description provided for @appLockUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Set a screen lock on your phone to use this.'**
  String get appLockUnavailable;

  /// No description provided for @alwaysOn.
  ///
  /// In en, this message translates to:
  /// **'Always-on VPN'**
  String get alwaysOn;

  /// No description provided for @alwaysOnHint.
  ///
  /// In en, this message translates to:
  /// **'Keep the VPN on and block connections without it. Opens Android’s VPN settings.'**
  String get alwaysOnHint;

  /// No description provided for @errorLocked.
  ///
  /// In en, this message translates to:
  /// **'Unlock the app to use your saved password'**
  String get errorLocked;

  /// No description provided for @fixLocked.
  ///
  /// In en, this message translates to:
  /// **'Open the app and connect from there, or turn off the app lock in Settings.'**
  String get fixLocked;

  /// No description provided for @enterCodeBody.
  ///
  /// In en, this message translates to:
  /// **'Type the code from your email, text message or authenticator app.'**
  String get enterCodeBody;

  /// No description provided for @submitCode.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get submitCode;

  /// No description provided for @timeLeft.
  ///
  /// In en, this message translates to:
  /// **'{seconds} s left'**
  String timeLeft(int seconds);

  /// No description provided for @updatePassword.
  ///
  /// In en, this message translates to:
  /// **'Update password'**
  String get updatePassword;

  /// No description provided for @fixOutOfAttempts.
  ///
  /// In en, this message translates to:
  /// **'None of the server addresses answered. If other apps work, the VPN may be down, so ask your IT team.'**
  String get fixOutOfAttempts;

  /// No description provided for @fixUnsupportedChallenge.
  ///
  /// In en, this message translates to:
  /// **'Share the activity log with your IT team so they can see which sign-in method your account needs.'**
  String get fixUnsupportedChallenge;

  /// No description provided for @showFingerprint.
  ///
  /// In en, this message translates to:
  /// **'Show fingerprint'**
  String get showFingerprint;

  /// No description provided for @hideFingerprint.
  ///
  /// In en, this message translates to:
  /// **'Hide fingerprint'**
  String get hideFingerprint;

  /// No description provided for @certTrustContinue.
  ///
  /// In en, this message translates to:
  /// **'Trust and continue'**
  String get certTrustContinue;

  /// No description provided for @realmHint.
  ///
  /// In en, this message translates to:
  /// **'Only if your IT team gave you one'**
  String get realmHint;

  /// No description provided for @agreeAndConnect.
  ///
  /// In en, this message translates to:
  /// **'Agree & connect'**
  String get agreeAndConnect;

  /// No description provided for @stepOf.
  ///
  /// In en, this message translates to:
  /// **'Step {step} of {total}'**
  String stepOf(int step, int total);

  /// No description provided for @connectTo.
  ///
  /// In en, this message translates to:
  /// **'Connect to {name}'**
  String connectTo(String name);

  /// No description provided for @shareLog.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get shareLog;

  /// No description provided for @quickTile.
  ///
  /// In en, this message translates to:
  /// **'Quick Settings tile'**
  String get quickTile;

  /// No description provided for @quickTileHint.
  ///
  /// In en, this message translates to:
  /// **'Connect from the panel you swipe down from the top of the screen.'**
  String get quickTileHint;

  /// No description provided for @switchWhileConnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnect to switch connections'**
  String get switchWhileConnected;

  /// No description provided for @logOk.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get logOk;

  /// No description provided for @logError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get logError;

  /// No description provided for @logInfo.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get logInfo;

  /// No description provided for @shortcuts.
  ///
  /// In en, this message translates to:
  /// **'Shortcuts'**
  String get shortcuts;

  /// No description provided for @shareLogSubject.
  ///
  /// In en, this message translates to:
  /// **'Blanarch activity log'**
  String get shareLogSubject;

  /// No description provided for @stepChipServer.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get stepChipServer;

  /// No description provided for @stepChipSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get stepChipSignIn;

  /// No description provided for @stepChipTunnel.
  ///
  /// In en, this message translates to:
  /// **'Tunnel'**
  String get stepChipTunnel;

  /// No description provided for @reachingHost.
  ///
  /// In en, this message translates to:
  /// **'Reaching {host}'**
  String reachingHost(String host);

  /// No description provided for @attemptOf.
  ///
  /// In en, this message translates to:
  /// **'Attempt {attempt} of {total} · {host}'**
  String attemptOf(int attempt, int total, String host);

  /// No description provided for @lastTry.
  ///
  /// In en, this message translates to:
  /// **'Last try: {reason}'**
  String lastTry(String reason);

  /// No description provided for @tryingFor.
  ///
  /// In en, this message translates to:
  /// **'Trying for {time}'**
  String tryingFor(String time);

  /// No description provided for @progressOf.
  ///
  /// In en, this message translates to:
  /// **'Step {step} of {total}, {name}'**
  String progressOf(int step, int total, String name);

  /// No description provided for @activity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get activity;

  /// No description provided for @seeAll.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get seeAll;

  /// No description provided for @eventStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting {name}'**
  String eventStarting(String name);

  /// No description provided for @eventAttempt.
  ///
  /// In en, this message translates to:
  /// **'Attempt {attempt} of {total} · {address}'**
  String eventAttempt(String attempt, String total, String address);

  /// No description provided for @eventSigningIn.
  ///
  /// In en, this message translates to:
  /// **'Signing in as {user}'**
  String eventSigningIn(String user);

  /// No description provided for @eventSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Signed in'**
  String get eventSignedIn;

  /// No description provided for @eventWaitingSso.
  ///
  /// In en, this message translates to:
  /// **'Waiting for sign-in in the browser'**
  String get eventWaitingSso;

  /// No description provided for @eventApprovePush.
  ///
  /// In en, this message translates to:
  /// **'Waiting for approval on your phone'**
  String get eventApprovePush;

  /// No description provided for @eventCodeReceived.
  ///
  /// In en, this message translates to:
  /// **'Got code {code}. Checking it'**
  String eventCodeReceived(String code);

  /// No description provided for @eventConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected · IP {ip}'**
  String eventConnected(String ip);

  /// No description provided for @eventConnectionLost.
  ///
  /// In en, this message translates to:
  /// **'The connection dropped'**
  String get eventConnectionLost;

  /// No description provided for @eventReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting'**
  String get eventReconnecting;

  /// No description provided for @eventDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get eventDisconnected;

  /// No description provided for @checkingHost.
  ///
  /// In en, this message translates to:
  /// **'Checking {host}…'**
  String checkingHost(String host);

  /// No description provided for @factTunnelIp.
  ///
  /// In en, this message translates to:
  /// **'Tunnel IP'**
  String get factTunnelIp;

  /// No description provided for @factGateway.
  ///
  /// In en, this message translates to:
  /// **'Gateway'**
  String get factGateway;

  /// No description provided for @factRouting.
  ///
  /// In en, this message translates to:
  /// **'Routing'**
  String get factRouting;

  /// No description provided for @factDns.
  ///
  /// In en, this message translates to:
  /// **'DNS'**
  String get factDns;

  /// No description provided for @factTraffic.
  ///
  /// In en, this message translates to:
  /// **'Traffic'**
  String get factTraffic;

  /// No description provided for @factSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Signed in'**
  String get factSignedIn;

  /// No description provided for @routingAll.
  ///
  /// In en, this message translates to:
  /// **'All traffic'**
  String get routingAll;

  /// No description provided for @routingSplit.
  ///
  /// In en, this message translates to:
  /// **'Split tunnel · {count} routes'**
  String routingSplit(int count);

  /// No description provided for @backupAddress.
  ///
  /// In en, this message translates to:
  /// **'backup address'**
  String get backupAddress;

  /// No description provided for @signInPassword.
  ///
  /// In en, this message translates to:
  /// **'password'**
  String get signInPassword;

  /// No description provided for @signInCode.
  ///
  /// In en, this message translates to:
  /// **'code'**
  String get signInCode;

  /// No description provided for @signInPush.
  ///
  /// In en, this message translates to:
  /// **'push approval'**
  String get signInPush;

  /// No description provided for @signInSso.
  ///
  /// In en, this message translates to:
  /// **'single sign-on'**
  String get signInSso;

  /// No description provided for @certPinnedMatches.
  ///
  /// In en, this message translates to:
  /// **'Certificate pinned · matches'**
  String get certPinnedMatches;

  /// No description provided for @certSystemTrusted.
  ///
  /// In en, this message translates to:
  /// **'Certificate trusted by the system'**
  String get certSystemTrusted;

  /// No description provided for @allDetails.
  ///
  /// In en, this message translates to:
  /// **'All details'**
  String get allDetails;

  /// No description provided for @detailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Connection details'**
  String get detailsTitle;

  /// No description provided for @sectionNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get sectionNetwork;

  /// No description provided for @sectionServer.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get sectionServer;

  /// No description provided for @sectionSession.
  ///
  /// In en, this message translates to:
  /// **'Session'**
  String get sectionSession;

  /// No description provided for @dnsServers.
  ///
  /// In en, this message translates to:
  /// **'DNS servers'**
  String get dnsServers;

  /// No description provided for @searchDomain.
  ///
  /// In en, this message translates to:
  /// **'Search domain'**
  String get searchDomain;

  /// No description provided for @routesLabel.
  ///
  /// In en, this message translates to:
  /// **'Routes'**
  String get routesLabel;

  /// No description provided for @mtuLabel.
  ///
  /// In en, this message translates to:
  /// **'MTU'**
  String get mtuLabel;

  /// No description provided for @certificateLabel.
  ///
  /// In en, this message translates to:
  /// **'Certificate'**
  String get certificateLabel;

  /// No description provided for @pinned.
  ///
  /// In en, this message translates to:
  /// **'pinned'**
  String get pinned;

  /// No description provided for @encryptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Encryption'**
  String get encryptionLabel;

  /// No description provided for @latencyLabel.
  ///
  /// In en, this message translates to:
  /// **'Latency'**
  String get latencyLabel;

  /// No description provided for @userLabel.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get userLabel;

  /// No description provided for @signInLabel.
  ///
  /// In en, this message translates to:
  /// **'Sign-in'**
  String get signInLabel;

  /// No description provided for @connectedSinceLabel.
  ///
  /// In en, this message translates to:
  /// **'Connected since'**
  String get connectedSinceLabel;

  /// No description provided for @reconnectsLabel.
  ///
  /// In en, this message translates to:
  /// **'Reconnects'**
  String get reconnectsLabel;

  /// No description provided for @addressesTried.
  ///
  /// In en, this message translates to:
  /// **'Addresses tried'**
  String get addressesTried;

  /// No description provided for @copyAll.
  ///
  /// In en, this message translates to:
  /// **'Copy all'**
  String get copyAll;

  /// No description provided for @shareWithIt.
  ///
  /// In en, this message translates to:
  /// **'Share with IT'**
  String get shareWithIt;

  /// No description provided for @detailsShareSubject.
  ///
  /// In en, this message translates to:
  /// **'Blanarch connection details'**
  String get detailsShareSubject;

  /// No description provided for @measuring.
  ///
  /// In en, this message translates to:
  /// **'measuring'**
  String get measuring;

  /// No description provided for @notReported.
  ///
  /// In en, this message translates to:
  /// **'Not reported'**
  String get notReported;

  /// No description provided for @millis.
  ///
  /// In en, this message translates to:
  /// **'{ms} ms'**
  String millis(int ms);

  /// No description provided for @copyValue.
  ///
  /// In en, this message translates to:
  /// **'Copy {label}'**
  String copyValue(String label);

  /// No description provided for @backupShort.
  ///
  /// In en, this message translates to:
  /// **'backup'**
  String get backupShort;

  /// No description provided for @phaseWaitingNetwork.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a network'**
  String get phaseWaitingNetwork;

  /// No description provided for @stepWaitingNetwork.
  ///
  /// In en, this message translates to:
  /// **'Waiting for Wi-Fi or mobile data'**
  String get stepWaitingNetwork;

  /// No description provided for @errorNetworkChanged.
  ///
  /// In en, this message translates to:
  /// **'The network changed'**
  String get errorNetworkChanged;

  /// No description provided for @errorNoNetwork.
  ///
  /// In en, this message translates to:
  /// **'No internet connection'**
  String get errorNoNetwork;

  /// No description provided for @errorSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'The session expired'**
  String get errorSessionExpired;

  /// No description provided for @fixNoNetwork.
  ///
  /// In en, this message translates to:
  /// **'Turn on Wi-Fi or mobile data. The app reconnects by itself when the network is back.'**
  String get fixNoNetwork;

  /// No description provided for @eventNetworkLost.
  ///
  /// In en, this message translates to:
  /// **'No network · waiting'**
  String get eventNetworkLost;

  /// No description provided for @eventNetworkBack.
  ///
  /// In en, this message translates to:
  /// **'Network back'**
  String get eventNetworkBack;

  /// No description provided for @eventNetworkChanged.
  ///
  /// In en, this message translates to:
  /// **'Network changed · rejoining'**
  String get eventNetworkChanged;

  /// No description provided for @eventSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Session expired · signing in again'**
  String get eventSessionExpired;

  /// No description provided for @eventDnsFallback.
  ///
  /// In en, this message translates to:
  /// **'The server gave no DNS. Using {servers} through the tunnel'**
  String eventDnsFallback(String servers);

  /// No description provided for @reconnectedAfter.
  ///
  /// In en, this message translates to:
  /// **'Reconnected · {reason}'**
  String reconnectedAfter(String reason);

  /// No description provided for @errorSslVpnOff.
  ///
  /// In en, this message translates to:
  /// **'This server doesn’t offer SSL-VPN'**
  String get errorSslVpnOff;

  /// No description provided for @errorClientCertRequired.
  ///
  /// In en, this message translates to:
  /// **'This server asks for a client certificate'**
  String get errorClientCertRequired;

  /// No description provided for @fixSslVpnOff.
  ///
  /// In en, this message translates to:
  /// **'It may have moved to IPsec, which Blanarch will support soon. Ask your IT team whether SSL-VPN is still available and at which address.'**
  String get fixSslVpnOff;

  /// No description provided for @fixClientCert.
  ///
  /// In en, this message translates to:
  /// **'Blanarch doesn’t use client certificates yet. Some servers ask for one without requiring it, so you can still try.'**
  String get fixClientCert;

  /// No description provided for @ipsecAnswers.
  ///
  /// In en, this message translates to:
  /// **'The server answers IPsec (IKEv2), so it probably uses IPsec now.'**
  String get ipsecAnswers;

  /// No description provided for @unsupportedTitle.
  ///
  /// In en, this message translates to:
  /// **'This server may not work yet'**
  String get unsupportedTitle;

  /// No description provided for @tellIt.
  ///
  /// In en, this message translates to:
  /// **'What to ask IT'**
  String get tellIt;

  /// No description provided for @tellItSslOff.
  ///
  /// In en, this message translates to:
  /// **'Is SSL-VPN tunnel mode still enabled on {host}? If our FortiGate moved to IPsec, what are the IPsec settings?'**
  String tellItSslOff(String host);

  /// No description provided for @tellItClientCert.
  ///
  /// In en, this message translates to:
  /// **'Does {host} require a client certificate for the VPN, or is it optional?'**
  String tellItClientCert(String host);

  /// No description provided for @tryAnotherAddress.
  ///
  /// In en, this message translates to:
  /// **'Try another address'**
  String get tryAnotherAddress;

  /// No description provided for @continueAnyway.
  ///
  /// In en, this message translates to:
  /// **'Continue anyway'**
  String get continueAnyway;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
