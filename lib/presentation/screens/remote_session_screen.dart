import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/protocol_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/entities/input_commands.dart';
import '../../domain/entities/session_models.dart';
import '../../services/communication/connection_orchestrator.dart';
import '../../services/input/peripheral_manager_service.dart';
import '../widgets/neo_card.dart';
import '../widgets/status_badge.dart';
import '../widgets/vibrant_button.dart';

/// Visualizador de Sessão Remota com renderizador DeskRT-Tile, captura completa de Mouse,
/// Teclado (ScanCode/HID), Controle de Videogame (Gamepad Físico + HUD Virtual),
/// Chat bidirecional, Clipboard e Transferência de Arquivos.
class RemoteSessionScreen extends StatefulWidget {
  final RemoteSessionClientController session;
  final PeripheralManagerService peripheralManager;
  final VoidCallback onCloseSession;

  const RemoteSessionScreen({
    super.key,
    required this.session,
    required this.peripheralManager,
    required this.onCloseSession,
  });

  @override
  State<RemoteSessionScreen> createState() => _RemoteSessionScreenState();
}

class _RemoteSessionScreenState extends State<RemoteSessionScreen> {
  final FocusNode _canvasFocusNode = FocusNode();
  final TextEditingController _chatInputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSessionUpdated);
  }

  @override
  void didUpdateWidget(covariant RemoteSessionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeListener(_onSessionUpdated);
      widget.session.addListener(_onSessionUpdated);
    }
  }

  void _onSessionUpdated() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionUpdated);
    _canvasFocusNode.dispose();
    _chatInputController.dispose();
    super.dispose();
  }

  Rect _computeDestRect(Size viewportSize) {
    final double srcW = max(1.0, widget.session.screenMeta.width.toDouble());
    final double srcH = max(1.0, widget.session.screenMeta.height.toDouble());
    final double dstW = max(1.0, viewportSize.width);
    final double dstH = max(1.0, viewportSize.height);

    if (widget.session.stretchToWindow) {
      final double scale = min(dstW / srcW, dstH / srcH);
      final double w = srcW * scale;
      final double h = srcH * scale;
      final double x = (dstW - w) / 2.0;
      final double y = (dstH - h) / 2.0;
      return Rect.fromLTWH(x, y, w, h);
    }
    return Rect.fromLTWH(0, 0, min(dstW, srcW), min(dstH, srcH));
  }

  ({double normX, double normY})? _normalizePointer(Offset localPos, Size viewportSize) {
    final Rect rect = _computeDestRect(viewportSize);
    if (rect.width <= 0 || rect.height <= 0) return null;
    final double nx = (localPos.dx - rect.left) / rect.width;
    final double ny = (localPos.dy - rect.top) / rect.height;
    if (nx < 0.0 || nx > 1.0 || ny < 0.0 || ny > 1.0) return null;
    return (normX: nx, normY: ny);
  }

  void _handlePointerMoveOrHover(Offset localPos, Size viewportSize) {
    if (!widget.session.controlInputEnabled) return;
    final ({double normX, double normY})? norm = _normalizePointer(localPos, viewportSize);
    if (norm == null) return;
    widget.peripheralManager.handleLocalMouseEvent(
      action: MouseActionType.move,
      normX: norm.normX,
      normY: norm.normY,
    );
  }

  void _handlePointerDown(PointerDownEvent event, Size viewportSize) {
    _canvasFocusNode.requestFocus();
    if (!widget.session.controlInputEnabled) return;
    final ({double normX, double normY})? norm =
        _normalizePointer(event.localPosition, viewportSize);
    if (norm == null) return;

    MouseActionType action = MouseActionType.leftDown;
    if ((event.buttons & kSecondaryMouseButton) != 0) {
      action = MouseActionType.rightDown;
    } else if ((event.buttons & kMiddleMouseButton) != 0) {
      action = MouseActionType.middleDown;
    } else if ((event.buttons & kBackMouseButton) != 0) {
      action = MouseActionType.xButton1Down;
    } else if ((event.buttons & kForwardMouseButton) != 0) {
      action = MouseActionType.xButton2Down;
    }

    widget.peripheralManager.handleLocalMouseEvent(
      action: action,
      normX: norm.normX,
      normY: norm.normY,
    );
  }

  void _handlePointerUp(PointerUpEvent event, Size viewportSize) {
    if (!widget.session.controlInputEnabled) return;
    final ({double normX, double normY})? norm =
        _normalizePointer(event.localPosition, viewportSize);
    if (norm == null) return;

    widget.peripheralManager.handleLocalMouseEvent(
      action: MouseActionType.leftUp,
      normX: norm.normX,
      normY: norm.normY,
    );
  }

  void _handlePointerSignal(PointerSignalEvent event, Size viewportSize) {
    if (!widget.session.controlInputEnabled) return;
    if (event is PointerScrollEvent) {
      final ({double normX, double normY})? norm =
          _normalizePointer(event.localPosition, viewportSize);
      if (norm == null) return;

      if (event.scrollDelta.dy != 0) {
        widget.peripheralManager.handleLocalMouseEvent(
          action: MouseActionType.wheelVertical,
          normX: norm.normX,
          normY: norm.normY,
          wheelDeltaY: (-event.scrollDelta.dy).round(),
        );
      }
      if (event.scrollDelta.dx != 0) {
        widget.peripheralManager.handleLocalMouseEvent(
          action: MouseActionType.wheelHorizontal,
          normX: norm.normX,
          normY: norm.normY,
          wheelDeltaX: event.scrollDelta.dx.round(),
        );
      }
    }
  }

  Future<void> _syncLocalClipboardToRemote() async {
    try {
      final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text != null && data!.text!.isNotEmpty) {
        widget.session.sendClipboardText(data.text!);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Área de transferência enviada ao dispositivo remoto.')),
        );
      }
    } catch (_) {}
  }

  Future<void> _showSendFileDialog() async {
    final TextEditingController fileNameCtrl =
        TextEditingController(text: 'relatorio_deskview.txt');
    final TextEditingController contentCtrl = TextEditingController(
      text: 'Arquivo transferido com segurança via DeskView v3 Flutter.',
    );

    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Transferência Segura de Arquivo'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: fileNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nome do Arquivo',
                    prefixIcon: Icon(Icons.insert_drive_file_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contentCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Conteúdo do Arquivo (Salvo em DeskView_Recebidos no Host)',
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            VibrantButton(
              label: 'Enviar Arquivo',
              icon: Icons.upload_file_rounded,
              compact: true,
              onPressed: () {
                final Uint8List bytes = Uint8List.fromList(utf8.encode(contentCtrl.text));
                widget.session.sendFileBytes(
                  fileName: fileNameCtrl.text,
                  bytes: bytes,
                );
                Navigator.of(ctx).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _buildSessionToolbar(context),
        Expanded(
          child: Row(
            children: <Widget>[
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.canvasDarkBackground,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.darkOutline, width: 2.0),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(
                        children: <Widget>[
                          Positioned.fill(
                            child: LayoutBuilder(
                              builder: (BuildContext context, BoxConstraints box) {
                                final Size viewportSize = Size(box.maxWidth, box.maxHeight);
                                return Focus(
                                  focusNode: _canvasFocusNode,
                                  autofocus: true,
                                  onKeyEvent: (FocusNode node, KeyEvent event) {
                                    if (!widget.session.controlInputEnabled) {
                                      return KeyEventResult.ignored;
                                    }
                                    widget.peripheralManager.handleFlutterKeyEvent(event);
                                    return KeyEventResult.handled;
                                  },
                                  child: Listener(
                                    behavior: HitTestBehavior.opaque,
                                    onPointerHover: (PointerHoverEvent e) =>
                                        _handlePointerMoveOrHover(e.localPosition, viewportSize),
                                    onPointerMove: (PointerMoveEvent e) =>
                                        _handlePointerMoveOrHover(e.localPosition, viewportSize),
                                    onPointerDown: (PointerDownEvent e) =>
                                        _handlePointerDown(e, viewportSize),
                                    onPointerUp: (PointerUpEvent e) =>
                                        _handlePointerUp(e, viewportSize),
                                    onPointerSignal: (PointerSignalEvent e) =>
                                        _handlePointerSignal(e, viewportSize),
                                    child: CustomPaint(
                                      painter: _DeskRtViewportPainter(
                                        session: widget.session,
                                        destRect: _computeDestRect(viewportSize),
                                      ),
                                      child: const SizedBox.expand(),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          if (widget.session.virtualGamepadVisible)
                            Positioned(
                              left: 16,
                              right: 16,
                              bottom: 16,
                              child: _buildVirtualGamepadOverlay(context),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.session.chatPanelVisible) _buildSideChatPanel(context),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSessionToolbar(BuildContext context) {
    final int monCount = widget.session.screenMeta.monitorCount;
    final List<DropdownMenuItem<int>> monitorItems = <DropdownMenuItem<int>>[
      const DropdownMenuItem<int>(value: 0, child: Text('Monitor Principal')),
      const DropdownMenuItem<int>(value: 1, child: Text('Todos os Monitores')),
      for (int i = 0; i < monCount; i++)
        DropdownMenuItem<int>(value: i + 2, child: Text('Monitor ${i + 1}')),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.cardSurface,
        border: Border(
          bottom: BorderSide(color: AppColors.darkOutline, width: 1.8),
        ),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              StatusBadge(
                label: widget.session.transport.routeType.label,
                dotColor: AppColors.vibrantGreen,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  widget.session.statusMessage,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              // Seletor de Monitor
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: AppColors.inputSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.darkOutline, width: 1.4),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: widget.session.selectedMonitorOption
                        .clamp(0, monitorItems.length - 1),
                    isDense: true,
                    items: monitorItems,
                    onChanged: (int? v) {
                      if (v != null) widget.session.selectMonitorOption(v);
                    },
                  ),
                ),
              ),
              // Seletor de Qualidade DeskRT
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: AppColors.inputSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.darkOutline, width: 1.4),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: widget.session.selectedQuality,
                    isDense: true,
                    items: const <DropdownMenuItem<int>>[
                      DropdownMenuItem<int>(
                        value: ProtocolConstants.qualityUltra,
                        child: Text('Ultra (90%)'),
                      ),
                      DropdownMenuItem<int>(
                        value: ProtocolConstants.qualityBalanced,
                        child: Text('Balanceado (70%)'),
                      ),
                      DropdownMenuItem<int>(
                        value: ProtocolConstants.qualityHighSpeed,
                        child: Text('Rápido (45%)'),
                      ),
                    ],
                    onChanged: (int? q) {
                      if (q != null) widget.session.selectQuality(q);
                    },
                  ),
                ),
              ),
              FilterChip(
                label: const Text('Controlar Entrada'),
                selected: widget.session.controlInputEnabled,
                selectedColor: AppColors.vibrantGreenSoft,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: AppColors.darkOutline, width: 1.4),
                ),
                onSelected: widget.session.setControlInputEnabled,
              ),
              FilterChip(
                label: const Text('Ajustar à Janela'),
                selected: widget.session.stretchToWindow,
                selectedColor: AppColors.vibrantGreenSoft,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: AppColors.darkOutline, width: 1.4),
                ),
                onSelected: widget.session.setStretchToWindow,
              ),
              VibrantButton(
                label: 'Gamepad HUD',
                icon: Icons.sports_esports_rounded,
                variant: widget.session.virtualGamepadVisible
                    ? VibrantButtonVariant.vibrantGreen
                    : VibrantButtonVariant.secondaryWhite,
                compact: true,
                onPressed: widget.session.toggleVirtualGamepad,
              ),
              VibrantButton(
                label: 'Clipboard',
                icon: Icons.content_paste_rounded,
                variant: VibrantButtonVariant.secondaryWhite,
                compact: true,
                onPressed: _syncLocalClipboardToRemote,
              ),
              VibrantButton(
                label: 'Arquivo',
                icon: Icons.upload_file_rounded,
                variant: VibrantButtonVariant.secondaryWhite,
                compact: true,
                onPressed: _showSendFileDialog,
              ),
              VibrantButton(
                label: 'Chat (${widget.session.chatMessages.length})',
                icon: Icons.chat_bubble_outline_rounded,
                variant: widget.session.chatPanelVisible
                    ? VibrantButtonVariant.accentBlue
                    : VibrantButtonVariant.secondaryWhite,
                compact: true,
                onPressed: widget.session.toggleChatPanel,
              ),
              VibrantButton(
                label: 'Encerrar',
                icon: Icons.close_rounded,
                variant: VibrantButtonVariant.dangerRed,
                compact: true,
                onPressed: widget.onCloseSession,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVirtualGamepadOverlay(BuildContext context) {
    final GamepadInputCommand gp = widget.peripheralManager.currentGamepadState;

    void toggleBtn(int mask, bool down) {
      final int nextMask = down ? (gp.buttonsMask | mask) : (gp.buttonsMask & ~mask);
      widget.peripheralManager.updateGamepadState(buttonsMask: nextMask);
    }

    return NeoCard(
      backgroundColor: AppColors.cardSurface.withValues(alpha: 0.94),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 12,
        children: <Widget>[
          // D-Pad + Analógico Esquerdo
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _buildGamepadHoldButton('◀', GamepadButtons.dpadLeft, toggleBtn),
              const SizedBox(width: 6),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _buildGamepadHoldButton('▲', GamepadButtons.dpadUp, toggleBtn),
                  const SizedBox(height: 6),
                  _buildGamepadHoldButton('▼', GamepadButtons.dpadDown, toggleBtn),
                ],
              ),
              const SizedBox(width: 6),
              _buildGamepadHoldButton('▶', GamepadButtons.dpadRight, toggleBtn),
            ],
          ),
          // Botões Centrais LB / LT / Start / Select / RB / RT
          Wrap(
            spacing: 8,
            children: <Widget>[
              _buildGamepadHoldButton('LB', GamepadButtons.leftShoulderLB, toggleBtn),
              _buildGamepadHoldButton('SELECT', GamepadButtons.backSelect, toggleBtn),
              _buildGamepadHoldButton('START', GamepadButtons.start, toggleBtn),
              _buildGamepadHoldButton('RB', GamepadButtons.rightShoulderRB, toggleBtn),
            ],
          ),
          // Botões de Ação A / B / X / Y
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _buildGamepadHoldButton('X', GamepadButtons.buttonX, toggleBtn),
              const SizedBox(width: 8),
              _buildGamepadHoldButton('Y', GamepadButtons.buttonY, toggleBtn),
              const SizedBox(width: 8),
              _buildGamepadHoldButton('A', GamepadButtons.buttonA, toggleBtn),
              const SizedBox(width: 8),
              _buildGamepadHoldButton('B', GamepadButtons.buttonB, toggleBtn),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGamepadHoldButton(
    String label,
    int mask,
    void Function(int mask, bool isDown) onToggle,
  ) {
    final bool pressed = widget.peripheralManager.currentGamepadState.isButtonPressed(mask);
    return GestureDetector(
      onTapDown: (_) => onToggle(mask, true),
      onTapUp: (_) => onToggle(mask, false),
      onTapCancel: () => onToggle(mask, false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: pressed ? AppColors.vibrantGreen : AppColors.elevatedSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.darkOutline, width: 1.6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: pressed ? AppColors.onVibrantGreen : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildSideChatPanel(BuildContext context) {
    return Container(
      width: 310,
      margin: const EdgeInsets.only(top: 12, right: 12, bottom: 12),
      child: NeoCard(
        topAccentColor: AppColors.accentBlue,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Chat & Log da Sessão',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.inputSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.darkOutline, width: 1.4),
                ),
                child: ListView.builder(
                  itemCount: widget.session.chatMessages.length,
                  itemBuilder: (BuildContext context, int i) {
                    final SessionChatMessage m = widget.session.chatMessages[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(
                        '[${m.formattedTime}] ${m.senderName}: ${m.text}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: m.isSystemLog
                              ? AppColors.vibrantGreenDark
                              : AppColors.textPrimary,
                          fontFamily: 'Consolas',
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _chatInputController,
                    decoration: const InputDecoration(
                      hintText: 'Enviar mensagem...',
                    ),
                    onSubmitted: (String v) {
                      widget.session.sendChatMessage(v);
                      _chatInputController.clear();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    widget.session.sendChatMessage(_chatInputController.text);
                    _chatInputController.clear();
                  },
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.vibrantGreen,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: AppColors.darkOutline, width: 1.5),
                    ),
                  ),
                  icon: const Icon(Icons.send_rounded, size: 18, color: AppColors.onVibrantGreen),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DeskRtViewportPainter extends CustomPainter {
  final RemoteSessionClientController session;
  final Rect destRect;

  _DeskRtViewportPainter({
    required this.session,
    required this.destRect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint bgPaint = Paint()..color = const Color(0xFF0B1120);
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Moldura da área de trabalho remota
    final Paint deskBgPaint = Paint()..color = const Color(0xFF172033);
    canvas.drawRRect(
      RRect.fromRectAndRadius(destRect, const Radius.circular(8)),
      deskBgPaint,
    );

    final double scaleX = destRect.width / max(1, session.screenMeta.width);
    final double scaleY = destRect.height / max(1, session.screenMeta.height);

    // Desenha os Dirty Tiles decodificados pelo Codec DeskRT
    for (final DirtyTileBlock tile in session.activeTiles) {
      Color tileColor = const Color(0xFF1E293B);
      if (tile.encodedBytes.length >= 7 &&
          tile.encodedBytes[0] == 0x44 &&
          tile.encodedBytes[1] == 0x56) {
        tileColor = Color.fromARGB(
          255,
          tile.encodedBytes[4],
          tile.encodedBytes[5],
          tile.encodedBytes[6],
        );
      }

      final Rect r = Rect.fromLTWH(
        destRect.left + tile.x * scaleX,
        destRect.top + tile.y * scaleY,
        tile.width * scaleX,
        tile.height * scaleY,
      );
      canvas.drawRect(r, Paint()..color = tileColor);
    }

    // Desenha o cursor remoto sincronizado pelo canal rápido
    final double cx = destRect.left + (session.cursorX * scaleX);
    final double cy = destRect.top + (session.cursorY * scaleY);
    if (destRect.contains(Offset(cx, cy))) {
      final Path cursorPath = Path()
        ..moveTo(cx, cy)
        ..lineTo(cx, cy + 16)
        ..lineTo(cx + 5, cy + 12)
        ..lineTo(cx + 12, cy + 12)
        ..close();

      canvas.drawPath(cursorPath, Paint()..color = AppColors.vibrantGreen);
      canvas.drawPath(
        cursorPath,
        Paint()
          ..color = AppColors.darkOutline
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DeskRtViewportPainter oldDelegate) => true;
}
