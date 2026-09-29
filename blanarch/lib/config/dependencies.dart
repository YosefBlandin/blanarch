import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../data/repositories/profile_repository.dart';
import '../data/repositories/vpn_repository.dart';
import '../data/services/vpn_platform.dart';
import '../ui/app/app_view_model.dart';

/// The composition root. Tests call this with a fake [VpnPlatform].
List<SingleChildWidget> providers(VpnPlatform platform) => [
  Provider<VpnPlatform>.value(value: platform),
  Provider<VpnRepository>(create: (c) => VpnRepository(c.read()), dispose: (_, r) => r.dispose()),
  Provider<ProfileRepository>(create: (c) => ProfileRepository(c.read()), dispose: (_, r) => r.dispose()),
  Provider<SettingsRepository>(create: (c) => SettingsRepository(c.read())),
  ChangeNotifierProvider<AppViewModel>(
    create: (c) => AppViewModel(settings: c.read(), profiles: c.read(), vpn: c.read())..load(),
  ),
];
