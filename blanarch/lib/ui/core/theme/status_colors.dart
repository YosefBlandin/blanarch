import 'package:flutter/material.dart';

import '../../../domain/models/vpn_status.dart';
import 'theme.dart';

/// Colour that represents a connection state in the brand palette.
Color statusColor(VpnStatus status, Brand b) => switch (status.phase) {
  VpnPhase.connected => b.ok,
  VpnPhase.error => b.bad,
  VpnPhase.idle => b.accent,
  _ => b.busy,
};
