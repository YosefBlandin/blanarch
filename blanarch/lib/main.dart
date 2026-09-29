import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config/dependencies.dart';
import 'data/services/vpn_platform.dart';
import 'ui/app/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MultiProvider(providers: providers(PigeonVpnPlatform()), child: const BlanarchApp()));
}
