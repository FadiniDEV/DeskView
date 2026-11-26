import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/entities/input_commands.dart';
import '../../domain/entities/peripheral_device.dart';
import '../../services/input/peripheral_manager_service.dart';
import '../controllers/app_controller.dart';
import '../widgets/neo_card.dart';
import '../widgets/status_badge.dart';
import '../widgets/vibrant_button.dart';

/// Central de Detecção, Hotplug, Calibração e Diagnóstico em Tempo Real de
/// Mouse, Teclado (ScanCode/ExtendedKey), Controles de Videogame (XInput/HID) e Joysticks.
class PeripheralsHubScreen extends StatefulWidget {
  final AppController controller;

  const PeripheralsHubScreen({
    super.key,
    required this.controller,
  });

  @override
  State<PeripheralsHubScreen> createState() => _PeripheralsHubScreenState();
}

class _PeripheralsHubScreenState extends State<PeripheralsHubScreen> {
  PeripheralManagerService get _pm => widget.controller.peripheralManager;

  @override
  void initState() {
    super.initState();
    _pm.addListener(_onUpdated);
  }

  void _onUpdated() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pm.removeListener(_onUpdated);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool isWide = constraints.maxWidth >= 900;

        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isWide ? 28 : 16,
            vertical: 22,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildHeaderBanner(context),
              const SizedBox(height: 20),
              _buildConnectedDevicesSection(context, constraints.maxWidth),
              const SizedBox(height: 22),
              if (isWide)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(child: _buildGamepadCalibrationCard(context)),
                      const SizedBox(width: 20),
                      Expanded(child: _buildMouseKeyboardDiagnosticsCard(context)),
                    ],
                  ),
                )
              else ...<Widget>[
                _buildGamepadCalibrationCard(context),
                const SizedBox(height: 16),
                _buildMouseKeyboardDiagnosticsCard(context),
              ],
              const SizedBox(height: 20),
              _buildAndroidCompatibilityCard(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeaderBanner(BuildContext context) {
    return NeoCard(
      topAccentColor: AppColors.vibrantGreen,
      padding: const EdgeInsets.all(20),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 12,
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Periféricos & Controles de Entrada',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Detecção ativa via USB HID, XInput 1.4 e Android InputManager com preservação de ScanCode e eixos analógicos.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
          Wrap(
            spacing: 10,
            children: <Widget>[
              VibrantButton(
                label: 'Reescanear Periféricos',
                icon: Icons.refresh_rounded,
                variant: VibrantButtonVariant.secondaryWhite,
                compact: true,
                onPressed: () => _pm.refreshPeripherals(),
              ),
              VibrantButton(
                label: 'Liberar Teclas/Botões Presos',
                icon: Icons.cleaning_services_rounded,
                variant: VibrantButtonVariant.vibrantGreen,
                compact: true,
                onPressed: () {
                  _pm.releaseAllLocalHeldStates();
                  widget.controller.platformBridge.releaseAllHeldInputs();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Todas as teclas modificadoras e botões foram liberados.'),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConnectedDevicesSection(BuildContext context, double maxWidth) {
    final List<PeripheralDevice> list = _pm.devices;
    final int cols = maxWidth >= 1050 ? 2 : 1;
    const double spacing = 16;
    final double itemW = (maxWidth - (spacing * (cols - 1))) / cols;

    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: list.map((PeripheralDevice dev) {
        final IconData icon = switch (dev.category) {
          PeripheralCategory.mouse => Icons.mouse_rounded,
          PeripheralCategory.keyboard => Icons.keyboard_alt_rounded,
          PeripheralCategory.gamepad => Icons.sports_esports_rounded,
          PeripheralCategory.joystick => Icons.gamepad_rounded,
        };

        return SizedBox(
          width: cols == 1 ? double.infinity : itemW,
          child: NeoCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: dev.isConnected
                            ? AppColors.vibrantGreenSoft
                            : AppColors.dangerRedSoft,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.darkOutline, width: 1.5),
                      ),
                      child: Icon(icon, color: AppColors.textPrimary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            dev.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${dev.category.title} • Barramento: ${dev.connectionBus} • VID/PID: ${dev.vendorProductId}',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: dev.isTransmitEnabled,
                      activeThumbColor: AppColors.onVibrantGreen,
                      activeTrackColor: AppColors.vibrantGreen,
                      onChanged: (bool val) => _pm.setPeripheralTransmitEnabled(dev.id, val),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    StatusBadge(
                      label: dev.isConnected ? 'Conectado' : 'Desconectado',
                      dotColor: dev.isConnected ? AppColors.vibrantGreen : AppColors.dangerRed,
                      backgroundColor: dev.isConnected
                          ? AppColors.vibrantGreenSoft
                          : AppColors.dangerRedSoft,
                    ),
                    StatusBadge(
                      label: '${dev.buttonCount} Botões / Teclas',
                      backgroundColor: AppColors.inputSurface,
                      textColor: AppColors.textSecondary,
                    ),
                    if (dev.axisCount > 0)
                      StatusBadge(
                        label: '${dev.axisCount} Eixos Analógicos',
                        backgroundColor: AppColors.accentBlueSoft,
                        textColor: AppColors.textPrimary,
                      ),
                    TextButton.icon(
                      onPressed: () =>
                          _pm.setPeripheralConnectionState(dev.id, !dev.isConnected),
                      icon: Icon(
                        dev.isConnected ? Icons.usb_off_rounded : Icons.usb_rounded,
                        size: 16,
                      ),
                      label: Text(
                        dev.isConnected ? 'Simular Desconexão' : 'Reconectar Dispositivo',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildGamepadCalibrationCard(BuildContext context) {
    final GamepadInputCommand gp = _pm.currentGamepadState;

    return NeoCard(
      topAccentColor: AppColors.accentBlue,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Teste & Calibração de Controle / Joystick (XInput / HID)',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            'Verifique eixos analógicos (LX/LY, RX/RY), gatilhos (LT/RT) e botões antes ou durante a transmissão remota:',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: _buildStickVisualizer(
                  title: 'Analógico Esquerdo',
                  x: gp.leftStickX,
                  y: gp.leftStickY,
                  onPan: (double nx, double ny) =>
                      _pm.updateGamepadState(leftStickX: nx, leftStickY: ny),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStickVisualizer(
                  title: 'Analógico Direito',
                  x: gp.rightStickX,
                  y: gp.rightStickY,
                  onPan: (double nx, double ny) =>
                      _pm.updateGamepadState(rightStickX: nx, rightStickY: ny),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: _buildTriggerSlider(
                  label: 'Gatilho LT: ${(gp.leftTrigger * 100).round()}%',
                  value: gp.leftTrigger,
                  onChanged: (double v) => _pm.updateGamepadState(leftTrigger: v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTriggerSlider(
                  label: 'Gatilho RT: ${(gp.rightTrigger * 100).round()}%',
                  value: gp.rightTrigger,
                  onChanged: (double v) => _pm.updateGamepadState(rightTrigger: v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _buildTestButtonChip('A', GamepadButtons.buttonA),
              _buildTestButtonChip('B', GamepadButtons.buttonB),
              _buildTestButtonChip('X', GamepadButtons.buttonX),
              _buildTestButtonChip('Y', GamepadButtons.buttonY),
              _buildTestButtonChip('LB', GamepadButtons.leftShoulderLB),
              _buildTestButtonChip('RB', GamepadButtons.rightShoulderRB),
              _buildTestButtonChip('START', GamepadButtons.start),
              _buildTestButtonChip('SELECT', GamepadButtons.backSelect),
              _buildTestButtonChip('D-UP', GamepadButtons.dpadUp),
              _buildTestButtonChip('D-DOWN', GamepadButtons.dpadDown),
              _buildTestButtonChip('D-LEFT', GamepadButtons.dpadLeft),
              _buildTestButtonChip('D-RIGHT', GamepadButtons.dpadRight),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              const Text(
                'Zona Morta (Deadzone):',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              Expanded(
                child: Slider(
                  value: _pm.stickDeadzone,
                  min: 0.0,
                  max: 0.35,
                  activeColor: AppColors.vibrantGreenDark,
                  label: '${(_pm.stickDeadzone * 100).round()}%',
                  onChanged: _pm.setStickDeadzone,
                ),
              ),
              Text(
                '${(_pm.stickDeadzone * 100).round()}%',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStickVisualizer({
    required String title,
    required double x,
    required double y,
    required void Function(double nx, double ny) onPan,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.elevatedSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkOutline, width: 1.5),
      ),
      child: Column(
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onPanUpdate: (DragUpdateDetails d) {
              final double nx = ((d.localPosition.dx - 45) / 45).clamp(-1.0, 1.0);
              final double ny = ((d.localPosition.dy - 45) / 45).clamp(-1.0, 1.0);
              onPan(nx, ny);
            },
            onPanEnd: (_) => onPan(0.0, 0.0),
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: AppColors.cardSurface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.darkOutline, width: 1.6),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  Transform.translate(
                    offset: Offset(x * 32, y * 32),
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: AppColors.vibrantGreen,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.darkOutline, width: 1.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'X: ${x.toStringAsFixed(2)} | Y: ${y.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              fontFamily: 'Consolas',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTriggerSlider({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        Slider(
          value: value,
          min: 0.0,
          max: 1.0,
          activeColor: AppColors.accentBlue,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildTestButtonChip(String label, int mask) {
    final bool active = _pm.currentGamepadState.isButtonPressed(mask);
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: active ? AppColors.onVibrantGreen : AppColors.textPrimary,
        ),
      ),
      selected: active,
      selectedColor: AppColors.vibrantGreen,
      backgroundColor: AppColors.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.darkOutline, width: 1.4),
      ),
      onSelected: (bool v) {
        final int cur = _pm.currentGamepadState.buttonsMask;
        _pm.updateGamepadState(buttonsMask: v ? (cur | mask) : (cur & ~mask));
      },
    );
  }

  Widget _buildMouseKeyboardDiagnosticsCard(BuildContext context) {
    final MouseInputCommand m = _pm.lastMouseCommand;

    return NeoCard(
      topAccentColor: AppColors.vibrantGreen,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Diagnóstico de Mouse & Teclado (ScanCode Set 1)',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            'Injeção atômica via Win32 SendInput com suporte a teclas estendidas (Setas, Home, End, Insert, Delete) e 5 botões de mouse:',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.elevatedSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.darkOutline, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Último Evento de Teclado Capturado:',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  _pm.lastKeyboardEventSummary,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Consolas',
                    color: AppColors.vibrantGreenDark,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Último Comando de Mouse Normalizado:',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Action: ${m.action.name} | X: ${m.clampedX.toStringAsFixed(3)} | '
                  'Y: ${m.clampedY.toStringAsFixed(3)} | Mask: 0x${m.buttonsMask.toRadixString(16)} | Seq: #${m.sequenceNumber}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Consolas',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Disparo Rápido de Teclas Especiais para o Dispositivo Remoto:',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              VibrantButton(
                label: 'Seta Cima (EXT)',
                compact: true,
                variant: VibrantButtonVariant.secondaryWhite,
                onPressed: () {
                  _pm.emitVirtualKey(winVirtualKey: 0x26, isDown: true);
                  _pm.emitVirtualKey(winVirtualKey: 0x26, isDown: false);
                },
              ),
              VibrantButton(
                label: 'Delete (EXT)',
                compact: true,
                variant: VibrantButtonVariant.secondaryWhite,
                onPressed: () {
                  _pm.emitVirtualKey(winVirtualKey: 0x2E, isDown: true);
                  _pm.emitVirtualKey(winVirtualKey: 0x2E, isDown: false);
                },
              ),
              VibrantButton(
                label: ' Tecla Windows',
                compact: true,
                variant: VibrantButtonVariant.secondaryWhite,
                onPressed: () {
                  _pm.emitVirtualKey(winVirtualKey: 0x5B, isDown: true);
                  _pm.emitVirtualKey(winVirtualKey: 0x5B, isDown: false);
                },
              ),
              VibrantButton(
                label: 'ESC',
                compact: true,
                variant: VibrantButtonVariant.secondaryWhite,
                onPressed: () {
                  _pm.emitVirtualKey(winVirtualKey: 0x1B, isDown: true);
                  _pm.emitVirtualKey(winVirtualKey: 0x1B, isDown: false);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAndroidCompatibilityCard(BuildContext context) {
    return NeoCard(
      padding: const EdgeInsets.all(20),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 12,
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Permissões de Controle Remoto no Android (AccessibilityService & MediaProjection)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Quando este aplicativo roda em um dispositivo Android atuando como Host, o envio de gestos/toques requer a ativação do DeskViewAccessibilityService.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
          Wrap(
            spacing: 10,
            children: <Widget>[
              VibrantButton(
                label: 'Autorizar Acessibilidade Android',
                icon: Icons.accessibility_new_rounded,
                variant: VibrantButtonVariant.secondaryWhite,
                compact: true,
                onPressed: () async {
                  await widget.controller.platformBridge.requestAndroidAccessibilityPermission();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Fluxo de permissão de Acessibilidade Android verificado.'),
                    ),
                  );
                },
              ),
              VibrantButton(
                label: 'Autorizar Captura de Tela Android',
                icon: Icons.screen_share_rounded,
                variant: VibrantButtonVariant.vibrantGreen,
                compact: true,
                onPressed: () async {
                  await widget.controller.platformBridge.requestAndroidMediaProjectionPermission();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Permissão de MediaProjection solicitada com sucesso.'),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
