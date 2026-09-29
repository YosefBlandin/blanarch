// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get splashTagline => 'ACCESO PRIVADO  ·  DONDE ESTÉS';

  @override
  String get phaseIdle => 'Desconectado';

  @override
  String get phaseConnecting => 'Conectando';

  @override
  String get phaseConnected => 'Conectado';

  @override
  String get phaseReconnecting => 'Reconectando';

  @override
  String get phaseDisconnecting => 'Desconectando';

  @override
  String get phaseError => 'No se pudo conectar';

  @override
  String get tapToConnect => 'Toca para conectar';

  @override
  String get stepGateway => 'Contactando el servidor';

  @override
  String get stepSigningIn => 'Iniciando sesión';

  @override
  String get stepWaitingCode => 'Esperando el código';

  @override
  String get stepApproval => 'Esperando tu aprobación';

  @override
  String get stepSso => 'Iniciando sesión con tu empresa';

  @override
  String stepVerifying(String code) {
    return 'Verificando el código $code';
  }

  @override
  String get stepTunnel => 'Abriendo el túnel';

  @override
  String tunnelIp(String ip) {
    return 'IP $ip';
  }

  @override
  String get actionConnect => 'Conectar';

  @override
  String get actionDisconnect => 'Desconectar';

  @override
  String get actionCancelConnecting => 'Cancelar la conexión';

  @override
  String get settingsTooltip => 'Ajustes';

  @override
  String get addConnection => 'Agregar conexión';

  @override
  String get vpnPermissionNeeded => 'Permite el acceso a la VPN para conectar';

  @override
  String get checkingInbox => 'Revisando tu correo…';

  @override
  String get enterCodeTitle => 'Escribe tu código';

  @override
  String get typeCode => 'Escribir el código';

  @override
  String get fix => 'Corregir';

  @override
  String get codeHint => 'Código';

  @override
  String get codeExpiresHint =>
      'Escribe rápido el código más reciente. Vence en aproximadamente un minuto.';

  @override
  String get waitingPushTitle => 'Aprueba en tu teléfono';

  @override
  String get waitingPushBody =>
      'Abre tu app de autenticación, como FortiToken, y aprueba el inicio de sesión.';

  @override
  String get useCodeInstead => 'Usar un código';

  @override
  String get waitingSsoTitle => 'Termina de iniciar sesión';

  @override
  String get waitingSsoBody =>
      'La página de tu empresa está abierta en el navegador. Vuelve aquí cuando termines.';

  @override
  String get openSignInPage => 'Abrir la página de inicio';

  @override
  String get noProfilesTitle => 'Agrega la VPN de tu empresa';

  @override
  String get noProfilesBody =>
      'Necesitarás la dirección que usa tu equipo de TI, como vpn.empresa.com.';

  @override
  String get details => 'Detalles';

  @override
  String get tryAgain => 'Reintentar';

  @override
  String get editConnection => 'Editar conexión';

  @override
  String get reviewCertificate => 'Revisar certificado';

  @override
  String get whatYouCanDo => 'Qué puedes hacer';

  @override
  String get technicalDetails => 'Detalles técnicos';

  @override
  String get copy => 'Copiar';

  @override
  String get copied => 'Copiado';

  @override
  String get errorNoVpnPassword => 'Primero agrega tu contraseña de la VPN';

  @override
  String get errorAuthRejected => 'El servidor rechazó tu usuario o contraseña';

  @override
  String get errorUnsupportedChallenge =>
      'El servidor pidió un método de acceso que esta app aún no admite';

  @override
  String get errorCertMismatch =>
      'El certificado del servidor cambió, así que se bloqueó la conexión';

  @override
  String get errorCertUntrusted =>
      'Aún no confías en el certificado del servidor';

  @override
  String get errorSsoTimeout =>
      'El inicio de sesión en el navegador tardó demasiado';

  @override
  String get errorSsoFailed => 'No se pudo iniciar el inicio de sesión único';

  @override
  String get errorNoProfile => 'Primero agrega una conexión';

  @override
  String get errorInvalidAddress => 'Eso no parece la dirección de un servidor';

  @override
  String get errorPermissionRevoked =>
      'Se desactivó el permiso de VPN de Android';

  @override
  String errorOutOfAttempts(int count) {
    return 'Se intentó $count veces sin éxito';
  }

  @override
  String get errorOtpTimeout => 'El código no llegó a tiempo';

  @override
  String get errorOtpRejected => 'El código era incorrecto o había vencido';

  @override
  String get errorGatewayUnreachable => 'El servidor no responde';

  @override
  String get errorTunnelRefused =>
      'El servidor no permite el modo túnel para tu cuenta';

  @override
  String get errorProtocol => 'El servidor envió una respuesta inesperada';

  @override
  String get errorLinkLost => 'Se perdió la conexión';

  @override
  String get errorEmailAuthFailed => 'Se rechazó la contraseña del correo';

  @override
  String get errorEmailUnreachable => 'No se puede acceder a tu buzón';

  @override
  String get errorEmailNotConfigured => 'No hay contraseña de correo guardada';

  @override
  String get fixAuthRejected =>
      'Si cambiaste tu contraseña hace poco, actualízala aquí. Probar la anterior otra vez puede bloquear tu cuenta.';

  @override
  String get fixGatewayUnreachable =>
      'Revisa la dirección y tu conexión a internet. Si estás en un Wi-Fi de invitados, prueba con datos móviles.';

  @override
  String get fixCertUntrusted =>
      'Tu teléfono no había visto esta dirección. Confía en ella si pertenece a la VPN de tu empresa. La app te avisará si su certificado cambia.';

  @override
  String get fixCertMismatch =>
      'No confíes en el nuevo certificado a menos que tu equipo de TI confirme que el servidor cambió.';

  @override
  String get fixOtp =>
      'Vuelve a intentarlo y escribe el código más reciente de inmediato. Los códigos suelen vencer al minuto.';

  @override
  String get fixTunnelRefused =>
      'Pide a tu equipo de TI que habilite el modo túnel (acceso con FortiClient) para tu cuenta.';

  @override
  String get fixGeneric =>
      'Vuelve a intentarlo. Si sigue fallando, comparte el registro de actividad con tu equipo de TI.';

  @override
  String get back => 'Atrás';

  @override
  String get cancel => 'Cancelar';

  @override
  String get continueAction => 'Continuar';

  @override
  String get done => 'Listo';

  @override
  String get save => 'Guardar';

  @override
  String get change => 'Cambiar';

  @override
  String get remove => 'Quitar';

  @override
  String get delete => 'Eliminar';

  @override
  String get off => 'Desactivado';

  @override
  String get optional => 'Opcional';

  @override
  String get advanced => 'Avanzado';

  @override
  String get showPassword => 'Mostrar contraseña';

  @override
  String get hidePassword => 'Ocultar contraseña';

  @override
  String get welcomeTitle => 'Acceso privado,\nen un toque.';

  @override
  String get welcomeBody =>
      'Conéctate a la VPN FortiGate de tu empresa con errores claros, códigos leídos por ti y sin repetir contraseñas.';

  @override
  String get featureSignInTitle => 'Inicia sesión por ti';

  @override
  String get featureSignInBody =>
      'Tu contraseña se guarda una vez, cifrada en este teléfono.';

  @override
  String get featureCodeTitle => 'Resuelve el segundo paso';

  @override
  String get featureCodeBody =>
      'Aprobación push, códigos o lectura del código en tu correo.';

  @override
  String get featureRetryTitle => 'Te mantiene conectado';

  @override
  String get featureRetryBody =>
      'Reintenta y cambia de servidor hasta conectar.';

  @override
  String get setUp => 'Configurar';

  @override
  String get addressTitle => 'La VPN de tu empresa';

  @override
  String get addressBody =>
      'Escribe la dirección que te dio tu equipo de TI. Suele verse como vpn.empresa.com, a veces con un puerto.';

  @override
  String get addressLabel => 'Dirección de la VPN';

  @override
  String get checkingServer => 'Comprobando el servidor…';

  @override
  String get certTitle => 'Un servidor nuevo';

  @override
  String certBody(String host) {
    return 'Es la primera vez que tu teléfono ve $host. Las VPN de empresa suelen usar su propio certificado, así que es normal. Continúa si es la dirección que te dio tu equipo de TI. La app te avisará si alguna vez cambia.';
  }

  @override
  String get certChangedTitle => 'Este servidor cambió';

  @override
  String certChangedBody(String host) {
    return 'El certificado de $host es distinto del que aceptaste. Alguien podría estar interceptando la conexión. Consulta a tu equipo de TI antes de confiar en él.';
  }

  @override
  String get certFingerprint => 'Huella digital (SHA-256)';

  @override
  String get certDontConnect => 'No conectar';

  @override
  String get certTrust => 'Confiar en este servidor';

  @override
  String get signInTitle => '¿Cómo inicias sesión?';

  @override
  String get signInBody => 'Usa la misma cuenta que en tu computadora.';

  @override
  String get methodPassword => 'Usuario y contraseña';

  @override
  String get methodSso => 'Cuenta de la empresa (SSO)';

  @override
  String get ssoExplain =>
      'Cada vez que te conectes, se abrirá en el navegador la página de inicio de sesión de tu empresa.';

  @override
  String get usernameLabel => 'Usuario';

  @override
  String get passwordLabel => 'Contraseña';

  @override
  String get nameLabel => 'Nombre de esta conexión';

  @override
  String get realmLabel => 'Realm';

  @override
  String get backupAddressesLabel => 'Direcciones de respaldo, una por línea';

  @override
  String get emailStepTitle => 'Deja que lea el código';

  @override
  String get emailStepBody =>
      'Si tu empresa te envía el código por correo, la app puede encontrarlo en tu bandeja y terminar por ti. No tienes que copiar nada.';

  @override
  String get emailAddressLabel => 'Correo electrónico';

  @override
  String get emailPasswordLabel => 'Contraseña del correo';

  @override
  String get imapServerLabel => 'Servidor de correo (IMAP)';

  @override
  String get senderLabel => 'Solo códigos de este remitente';

  @override
  String get verifyAndContinue => 'Verificar y continuar';

  @override
  String get skipEmailCodes => 'Omitir, escribiré los códigos yo';

  @override
  String get permissionsTitle => 'Antes de conectar';

  @override
  String get permissionsBody =>
      'Android pregunta una vez por cada permiso. Puedes cambiarlos luego en los ajustes del sistema.';

  @override
  String get permissionVpnTitle => 'Conexión VPN';

  @override
  String get permissionVpnBody =>
      'Permite que la app cree el túnel seguro en este teléfono.';

  @override
  String get permissionNotificationsTitle => 'Notificaciones';

  @override
  String get permissionNotificationsBody =>
      'Muestra el estado de la conexión con un botón rápido para desconectar.';

  @override
  String get disclosureTitle => 'A qué accede la app';

  @override
  String get disclosureBody =>
      'La app se conecta solo a los servidores VPN y al buzón que agregues. Las contraseñas quedan cifradas en este teléfono y nunca se comparten. Si activas los códigos por correo, lee los mensajes nuevos de ese buzón solo para encontrar el código de acceso.';

  @override
  String get settingsTitle => 'Ajustes';

  @override
  String get appearance => 'Apariencia';

  @override
  String get themeAuto => 'Auto';

  @override
  String get themeLight => 'Claro';

  @override
  String get themeDark => 'Oscuro';

  @override
  String get themeAutoHint => 'Auto sigue la configuración de tu teléfono.';

  @override
  String get connections => 'Conexiones';

  @override
  String get diagnostics => 'Diagnóstico';

  @override
  String get activityLog => 'Registro de actividad';

  @override
  String versionLine(String version) {
    return 'Versión $version';
  }

  @override
  String get saved => 'Guardada';

  @override
  String get notSet => 'Sin configurar';

  @override
  String get secondFactorLabel => 'Segundo paso';

  @override
  String get secondFactorAuto => 'Push si está disponible';

  @override
  String get secondFactorCode => 'Siempre un código';

  @override
  String get emailCodesLabel => 'Leer códigos del correo';

  @override
  String get deleteConnection => 'Eliminar conexión';

  @override
  String deleteConfirm(String name) {
    return '¿Eliminar $name? También se borran sus contraseñas guardadas.';
  }

  @override
  String get activityTitle => 'Actividad';

  @override
  String get nothingYet => 'Aún no hay nada';

  @override
  String get scanQr => 'Escanear código QR';

  @override
  String get scanQrHint =>
      'Apunta la cámara al código de configuración de tu equipo de TI o de un colega.';

  @override
  String get notASetupCode =>
      'Ese código QR no es de configuración de una conexión';

  @override
  String get linkMismatchTitle => 'La huella no coincide';

  @override
  String linkMismatchBody(String host) {
    return 'El certificado de $host es distinto del que trae el código de configuración que usaste. No te conectes a menos que tu equipo de TI confirme que el servidor cambió.';
  }

  @override
  String get shareSetup => 'Compartir configuración';

  @override
  String get shareSetupBody =>
      'Tus colegas pueden escanearlo para agregar la misma conexión. Nunca incluye contraseñas.';

  @override
  String get includeUsername => 'Incluir mi usuario';

  @override
  String get copyLink => 'Copiar enlace';

  @override
  String get security => 'Seguridad';

  @override
  String get appLock => 'Bloqueo de la app';

  @override
  String get appLockHint =>
      'Confirma que eres tú con huella o rostro antes de usar las contraseñas guardadas.';

  @override
  String get appLockUnavailable =>
      'Configura un bloqueo de pantalla en tu teléfono para usar esto.';

  @override
  String get alwaysOn => 'VPN siempre activa';

  @override
  String get alwaysOnHint =>
      'Mantén la VPN activa y bloquea las conexiones sin ella. Abre los ajustes de VPN de Android.';

  @override
  String get errorLocked =>
      'Desbloquea la app para usar tu contraseña guardada';

  @override
  String get fixLocked =>
      'Abre la app y conéctate desde ahí, o desactiva el bloqueo de la app en Ajustes.';

  @override
  String get enterCodeBody =>
      'Escribe el código de tu correo, SMS o app de autenticación.';

  @override
  String get submitCode => 'Enviar código';

  @override
  String timeLeft(int seconds) {
    return 'Quedan $seconds s';
  }

  @override
  String get updatePassword => 'Actualizar contraseña';

  @override
  String get fixOutOfAttempts =>
      'Ninguna dirección del servidor respondió. Si otras apps funcionan, puede que la VPN esté caída. Consulta a tu equipo de TI.';

  @override
  String get fixUnsupportedChallenge =>
      'Comparte el registro de actividad con tu equipo de TI para que vean qué método de inicio de sesión necesita tu cuenta.';

  @override
  String get showFingerprint => 'Ver huella digital';

  @override
  String get hideFingerprint => 'Ocultar huella digital';

  @override
  String get certTrustContinue => 'Confiar y continuar';

  @override
  String get realmHint => 'Solo si tu equipo de TI te dio uno';

  @override
  String get agreeAndConnect => 'Aceptar y conectar';

  @override
  String stepOf(int step, int total) {
    return 'Paso $step de $total';
  }

  @override
  String connectTo(String name) {
    return 'Conectar a $name';
  }

  @override
  String get shareLog => 'Compartir';

  @override
  String get quickTile => 'Botón en ajustes rápidos';

  @override
  String get quickTileHint =>
      'Conéctate desde el panel que deslizas desde arriba de la pantalla.';

  @override
  String get switchWhileConnected => 'Desconéctate para cambiar de conexión';

  @override
  String get logOk => 'Correcto';

  @override
  String get logError => 'Error';

  @override
  String get logInfo => 'Información';

  @override
  String get shortcuts => 'Atajos';

  @override
  String get shareLogSubject => 'Registro de actividad de Blanarch';

  @override
  String get stepChipServer => 'Servidor';

  @override
  String get stepChipSignIn => 'Inicio de sesión';

  @override
  String get stepChipTunnel => 'Túnel';

  @override
  String reachingHost(String host) {
    return 'Contactando $host';
  }

  @override
  String attemptOf(int attempt, int total, String host) {
    return 'Intento $attempt de $total · $host';
  }

  @override
  String lastTry(String reason) {
    return 'Último intento: $reason';
  }

  @override
  String tryingFor(String time) {
    return 'Intentando desde hace $time';
  }

  @override
  String progressOf(int step, int total, String name) {
    return 'Paso $step de $total, $name';
  }

  @override
  String get activity => 'Actividad';

  @override
  String get seeAll => 'Ver todo';

  @override
  String eventStarting(String name) {
    return 'Iniciando $name';
  }

  @override
  String eventAttempt(String attempt, String total, String address) {
    return 'Intento $attempt de $total · $address';
  }

  @override
  String eventSigningIn(String user) {
    return 'Iniciando sesión como $user';
  }

  @override
  String get eventSignedIn => 'Sesión iniciada';

  @override
  String get eventWaitingSso => 'Esperando el inicio de sesión en el navegador';

  @override
  String get eventApprovePush => 'Esperando la aprobación en tu teléfono';

  @override
  String eventCodeReceived(String code) {
    return 'Código $code recibido. Verificando';
  }

  @override
  String eventConnected(String ip) {
    return 'Conectado · IP $ip';
  }

  @override
  String get eventConnectionLost => 'Se cayó la conexión';

  @override
  String get eventReconnecting => 'Reconectando';

  @override
  String get eventDisconnected => 'Desconectado';

  @override
  String checkingHost(String host) {
    return 'Verificando $host…';
  }

  @override
  String get factTunnelIp => 'IP del túnel';

  @override
  String get factGateway => 'Servidor';

  @override
  String get factRouting => 'Enrutamiento';

  @override
  String get factDns => 'DNS';

  @override
  String get factTraffic => 'Tráfico';

  @override
  String get factSignedIn => 'Sesión';

  @override
  String get routingAll => 'Todo el tráfico';

  @override
  String routingSplit(int count) {
    return 'Túnel dividido · $count rutas';
  }

  @override
  String get backupAddress => 'dirección de respaldo';

  @override
  String get signInPassword => 'contraseña';

  @override
  String get signInCode => 'código';

  @override
  String get signInPush => 'aprobación push';

  @override
  String get signInSso => 'inicio de sesión único';

  @override
  String get certPinnedMatches => 'Certificado fijado · coincide';

  @override
  String get certSystemTrusted => 'Certificado de confianza del sistema';

  @override
  String get allDetails => 'Ver detalles';

  @override
  String get detailsTitle => 'Detalles de la conexión';

  @override
  String get sectionNetwork => 'Red';

  @override
  String get sectionServer => 'Servidor';

  @override
  String get sectionSession => 'Sesión';

  @override
  String get dnsServers => 'Servidores DNS';

  @override
  String get searchDomain => 'Dominio de búsqueda';

  @override
  String get routesLabel => 'Rutas';

  @override
  String get mtuLabel => 'MTU';

  @override
  String get certificateLabel => 'Certificado';

  @override
  String get pinned => 'fijado';

  @override
  String get encryptionLabel => 'Cifrado';

  @override
  String get latencyLabel => 'Latencia';

  @override
  String get userLabel => 'Usuario';

  @override
  String get signInLabel => 'Inicio de sesión';

  @override
  String get connectedSinceLabel => 'Conectado desde';

  @override
  String get reconnectsLabel => 'Reconexiones';

  @override
  String get addressesTried => 'Direcciones probadas';

  @override
  String get copyAll => 'Copiar todo';

  @override
  String get shareWithIt => 'Compartir con TI';

  @override
  String get detailsShareSubject => 'Detalles de conexión de Blanarch';

  @override
  String get measuring => 'midiendo';

  @override
  String get notReported => 'No informado';

  @override
  String millis(int ms) {
    return '$ms ms';
  }

  @override
  String copyValue(String label) {
    return 'Copiar $label';
  }

  @override
  String get backupShort => 'respaldo';

  @override
  String get phaseWaitingNetwork => 'Esperando una red';

  @override
  String get stepWaitingNetwork => 'Esperando Wi-Fi o datos móviles';

  @override
  String get errorNetworkChanged => 'La red cambió';

  @override
  String get errorNoNetwork => 'Sin conexión a internet';

  @override
  String get errorSessionExpired => 'La sesión expiró';

  @override
  String get fixNoNetwork =>
      'Activa el Wi-Fi o los datos móviles. La app se reconecta sola cuando vuelva la red.';

  @override
  String get eventNetworkLost => 'Sin red · esperando';

  @override
  String get eventNetworkBack => 'Volvió la red';

  @override
  String get eventNetworkChanged => 'La red cambió · reconectando';

  @override
  String get eventSessionExpired =>
      'La sesión expiró · iniciando sesión de nuevo';

  @override
  String eventDnsFallback(String servers) {
    return 'El servidor no dio DNS. Usando $servers por el túnel';
  }

  @override
  String reconnectedAfter(String reason) {
    return 'Reconectado · $reason';
  }

  @override
  String get errorSslVpnOff => 'Este servidor no ofrece SSL-VPN';

  @override
  String get errorClientCertRequired =>
      'Este servidor pide un certificado de cliente';

  @override
  String get fixSslVpnOff =>
      'Puede que haya pasado a IPsec, que Blanarch soportará pronto. Pregunta a tu equipo de TI si SSL-VPN sigue disponible y en qué dirección.';

  @override
  String get fixClientCert =>
      'Blanarch aún no usa certificados de cliente. Algunos servidores lo piden sin exigirlo, así que puedes intentarlo.';

  @override
  String get ipsecAnswers =>
      'El servidor responde a IPsec (IKEv2), así que probablemente ahora usa IPsec.';

  @override
  String get unsupportedTitle => 'Puede que este servidor aún no funcione';

  @override
  String get tellIt => 'Qué preguntarle a TI';

  @override
  String tellItSslOff(String host) {
    return '¿Sigue activo el modo túnel de SSL-VPN en $host? Si nuestro FortiGate pasó a IPsec, ¿cuáles son los datos de IPsec?';
  }

  @override
  String tellItClientCert(String host) {
    return '¿$host exige un certificado de cliente para la VPN o es opcional?';
  }

  @override
  String get tryAnotherAddress => 'Probar otra dirección';

  @override
  String get continueAnyway => 'Continuar de todos modos';
}
