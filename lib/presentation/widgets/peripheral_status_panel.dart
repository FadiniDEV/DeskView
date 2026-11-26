import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/entities/peripheral_device.dart';
import 'neo_card.dart';
import 'status_badge.dart';

/// Painel compacto reutilizável que resume o estado dos periféricos conectados.
class PeripheralStatusPanel extends StatelessWidget {
  final List<PeripheralDevice> devices;
  final VoidCallback? onOpenHub;

  const PeripheralStatusPanel({
    super.key,
    required this.devices,
    this.onOpenHub,
  });

  @override
  Widget build(BuildContext context) {
    final int activeCount =
        devices.where((PeripheralDevice d) => d.isConnected && d.isTransmitEnabled).length;

    return NeoCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      onTap: onOpenHub,
      child: Row(
        children: <Widget>[
          const Icon(Icons.sports_esports_rounded, color: AppColors.textPrimary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$activeCount/${devices.length} Periféricos Ativos (Mouse, Teclado, Gamepad, Joystick)',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ),
          const StatusBadge(
            label: 'ScanCode & XInput Ativos',
            dotColor: AppColors.vibrantGreen,
          ),
        ],
      ),
    );
  }
}
