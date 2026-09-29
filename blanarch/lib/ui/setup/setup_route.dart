import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/models/setup_link.dart';
import 'setup_screen.dart';
import 'setup_view_model.dart';

/// Opens the add-connection flow (without the welcome and permission steps).
/// Completes with the new profile id, or null if the user backed out.
Future<String?> openAddConnection(BuildContext context, {SetupLink? link}) => Navigator.of(context).push<String>(
  MaterialPageRoute(
    builder: (_) => ChangeNotifierProvider(
      create: (c) => SetupViewModel(profiles: c.read(), settings: c.read(), vpn: c.read(), firstRun: false, link: link),
      child: Builder(
        builder: (c) => SetupScreen(
          viewModel: c.read(),
          onDone: (id) => Navigator.of(c).pop(id),
          onCancel: () => Navigator.of(c).pop(),
        ),
      ),
    ),
  ),
);
