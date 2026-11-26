import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../services/communication/stun_client_service.dart';
import '../controllers/app_controller.dart';
import '../widgets/neo_card.dart';
import '../widgets/status_badge.dart';
import '../widgets/vibrant_button.dart';

/// Tela de Diagnóstico de Rede Multi-Rota (LAN, STUN RFC 5389, CGNAT Relay) e Segurança Desassistida.
class NetworkSecurityScreen extends StatefulWidget {
  final AppController controller;

  const NetworkSecurityScreen({
    super.key,
    required this.controller,
  });

  @override
  State<NetworkSecurityScreen> createState() => _NetworkSecurityScreenState();
}

class _NetworkSecurityScreenState extends State<NetworkSecurityScreen> {
  final TextEditingController _unattendedPasswordCtrl = TextEditingController();

  @override
  void dispose() {
    _unattendedPasswordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final NetworkEndpointsSnapshot snap = widget.controller.networkSnapshot;

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
              if (isWide)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(child: _buildNetworkTopologyCard(context, snap)),
                      const SizedBox(width: 20),
                      Expanded(child: _buildSecurityConfigCard(context)),
                    ],
                  ),
                )
              else ...<Widget>[
                _buildNetworkTopologyCard(context, snap),
                const SizedBox(height: 16),
                _buildSecurityConfigCard(context),
              ],
              const SizedBox(height: 20),
              _buildDiagnosticLogCard(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNetworkTopologyCard(BuildContext context, NetworkEndpointsSnapshot snap) {
    return NeoCard(
      topAccentColor: AppColors.vibrantGreen,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Diagnóstico de Comunicação Entre Redes',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              VibrantButton(
                label: 'Testar STUN / Rotas',
                icon: Icons.radar_rounded,
                variant: VibrantButtonVariant.secondaryWhite,
                compact: true,
                onPressed: () => widget.controller.refreshNetworkDiagnostics(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Arquitetura híbrida que combina Descoberta LAN UDP, STUN RFC 5389 P2P e Túnel Relay Criptografado para travessia automática de NAT Simétrico e CGNAT.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          _buildInfoRow(
            'Topologia NAT Detectada',
            snap.natTopology.description,
            highlight: true,
          ),
          _buildInfoRow(
            'Endpoint Público (STUN/WAN)',
            snap.formattedPublicEndpoint,
          ),
          _buildInfoRow(
            'Endereços Locais (LAN IPv4)',
            '${snap.allLocalIps.join(", ")} (Porta TCP: ${widget.controller.identity.listenPort})',
          ),
          _buildInfoRow(
            'Descoberta Local (UDP Broadcast)',
            'Ativa na porta 50001 (Protocolo DESKVIEW_V1)',
          ),
          _buildInfoRow(
            'Sinalização Global & Relay CGNAT',
            '${widget.controller.globalSignaling.activeBrokerHost}:1883 '
            '(${widget.controller.isCloudConnected ? "Conectado" : "Reconectando"})',
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: highlight ? AppColors.vibrantGreenSoft : AppColors.elevatedSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.darkOutline, width: 1.4),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              flex: 2,
              child: Text(
                label,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Consolas',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityConfigCard(BuildContext context) {
    final bool hasPwd = widget.controller.identity.hasUnattendedPassword;

    return NeoCard(
      topAccentColor: AppColors.accentBlue,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Segurança & Acesso Desassistido',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              StatusBadge(
                label: hasPwd ? 'Senha Ativa' : 'Somente Aprovação Manual',
                dotColor: hasPwd ? AppColors.vibrantGreen : AppColors.warningAmber,
                backgroundColor:
                    hasPwd ? AppColors.vibrantGreenSoft : AppColors.warningAmberSoft,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Defina uma senha para permitir que você acesse este dispositivo de outra rede sem precisar clicar em Aceitar na tela:',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('unattended_password_field'),
            controller: _unattendedPasswordCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              hintText: 'Nova senha desassistida (deixe vazio para desativar)',
              prefixIcon: Icon(Icons.lock_rounded),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: VibrantButton(
                  key: const Key('btn_save_unattended_password'),
                  label: 'Salvar Senha Desassistida',
                  icon: Icons.save_rounded,
                  variant: VibrantButtonVariant.vibrantGreen,
                  onPressed: () async {
                    await widget.controller.updateUnattendedPassword(
                      _unattendedPasswordCtrl.text,
                    );
                    _unattendedPasswordCtrl.clear();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Configuração de senha desassistida atualizada!'),
                      ),
                    );
                  },
                ),
              ),
              if (hasPwd) ...<Widget>[
                const SizedBox(width: 10),
                VibrantButton(
                  label: 'Desativar',
                  variant: VibrantButtonVariant.dangerRed,
                  compact: true,
                  onPressed: () => widget.controller.updateUnattendedPassword(''),
                ),
              ],
            ],
          ),
          const SizedBox(height: 18),
          const Divider(),
          const SizedBox(height: 8),
          const Text(
            'Fingerprint Criptográfico SHA-256 deste Dispositivo:',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          SelectableText(
            widget.controller.identity.fingerprint,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              fontFamily: 'Consolas',
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticLogCard(BuildContext context) {
    return NeoCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Log de Eventos de Rede, Sinalização & Auditoria de Sessão',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Container(
            height: 210,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.canvasDarkBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.darkOutline, width: 1.6),
            ),
            child: widget.controller.diagnosticLogs.isEmpty
                ? const Center(
                    child: Text(
                      'Aguardando eventos de rede...',
                      style: TextStyle(color: Colors.white70, fontFamily: 'Consolas'),
                    ),
                  )
                : ListView.builder(
                    itemCount: widget.controller.diagnosticLogs.length,
                    itemBuilder: (BuildContext context, int index) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          widget.controller.diagnosticLogs[index],
                          style: const TextStyle(
                            color: AppColors.vibrantGreen,
                            fontSize: 12.5,
                            fontFamily: 'Consolas',
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
