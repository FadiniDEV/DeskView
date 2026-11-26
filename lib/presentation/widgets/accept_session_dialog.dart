import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/desk_id_formatter.dart';
import '../../domain/entities/session_models.dart';
import 'neo_card.dart';
import 'vibrant_button.dart';

/// Modal de Aceitação Interativa de Sessão Remota com 4 permissões granulares em tempo real.
class AcceptSessionDialog extends StatefulWidget {
  final IncomingConnectionRequest request;
  final void Function(bool approved, SessionPermissions permissions) onDecision;

  const AcceptSessionDialog({
    super.key,
    required this.request,
    required this.onDecision,
  });

  @override
  State<AcceptSessionDialog> createState() => _AcceptSessionDialogState();
}

class _AcceptSessionDialogState extends State<AcceptSessionDialog> {
  bool _allowMouseKeyboard = true;
  bool _allowGamepadJoystick = true;
  bool _allowClipboard = true;
  bool _allowFileTransfer = true;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: NeoCard(
            topAccentColor: AppColors.vibrantGreen,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.vibrantGreenSoft,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.darkOutline, width: 1.6),
                      ),
                      child: const Icon(
                        Icons.security_rounded,
                        color: AppColors.onVibrantGreen,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Solicitação de Acesso Remoto',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'O dispositivo "${widget.request.callerHostName}" '
                            '(ID: ${DeskIdFormatter.format(widget.request.callerDeskId)}) '
                            'deseja conectar.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Divider(),
                const SizedBox(height: 10),
                Text(
                  'Permissões concedidas ao operador:',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                _buildPermissionTile(
                  icon: Icons.mouse_rounded,
                  title: 'Permitir controle de Mouse e Teclado',
                  value: _allowMouseKeyboard,
                  onChanged: (bool v) => setState(() => _allowMouseKeyboard = v),
                ),
                _buildPermissionTile(
                  icon: Icons.sports_esports_rounded,
                  title: 'Permitir Controles de Videogame e Joysticks',
                  value: _allowGamepadJoystick,
                  onChanged: (bool v) => setState(() => _allowGamepadJoystick = v),
                ),
                _buildPermissionTile(
                  icon: Icons.content_paste_rounded,
                  title: 'Permitir sincronização da Área de Transferência',
                  value: _allowClipboard,
                  onChanged: (bool v) => setState(() => _allowClipboard = v),
                ),
                _buildPermissionTile(
                  icon: Icons.folder_copy_rounded,
                  title: 'Permitir envio e transferência de arquivos',
                  value: _allowFileTransfer,
                  onChanged: (bool v) => setState(() => _allowFileTransfer = v),
                ),
                const SizedBox(height: 20),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: VibrantButton(
                        label: 'ACEITAR ACESSO',
                        icon: Icons.check_circle_outline_rounded,
                        variant: VibrantButtonVariant.vibrantGreen,
                        onPressed: () {
                          widget.onDecision(
                            true,
                            SessionPermissions(
                              allowMouseAndKeyboard: _allowMouseKeyboard,
                              allowGamepadAndJoystick: _allowGamepadJoystick,
                              allowClipboardSync: _allowClipboard,
                              allowFileTransfer: _allowFileTransfer,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: VibrantButton(
                        label: 'RECUSAR',
                        icon: Icons.close_rounded,
                        variant: VibrantButtonVariant.dangerRed,
                        onPressed: () {
                          widget.onDecision(false, const SessionPermissions());
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionTile({
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.elevatedSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.darkOutline, width: 1.3),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 20, color: AppColors.textPrimary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Switch(
              value: value,
              activeThumbColor: AppColors.onVibrantGreen,
              activeTrackColor: AppColors.vibrantGreen,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
