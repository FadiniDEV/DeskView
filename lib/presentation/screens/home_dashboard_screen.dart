import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/entities/peer_device.dart';
import '../../domain/entities/session_models.dart';
import '../controllers/app_controller.dart';
import '../widgets/neo_card.dart';
import '../widgets/status_badge.dart';
import '../widgets/vibrant_button.dart';

/// Tela Principal (Painel de Controle e Conexão) com design Material 3 estruturado.
class HomeDashboardScreen extends StatefulWidget {
  final AppController controller;

  const HomeDashboardScreen({
    super.key,
    required this.controller,
  });

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  final TextEditingController _targetController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _hostChatInputController = TextEditingController();
  int _peerFilterIndex = 0; // 0 = Todos, 1 = Favoritos, 2 = Online na Rede

  @override
  void dispose() {
    _targetController.dispose();
    _passwordController.dispose();
    _hostChatInputController.dispose();
    super.dispose();
  }

  Future<void> _triggerConnect(String rawTarget, String password) async {
    final String? error = await widget.controller.initiateConnection(rawTarget, password);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool isWideDesktop = constraints.maxWidth >= 860;

        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isWideDesktop ? 28 : 16,
            vertical: 22,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (isWideDesktop)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(child: _buildThisWorkstationCard(context)),
                      const SizedBox(width: 20),
                      Expanded(child: _buildRemoteConnectCard(context)),
                    ],
                  ),
                )
              else ...<Widget>[
                _buildThisWorkstationCard(context),
                const SizedBox(height: 16),
                _buildRemoteConnectCard(context),
              ],
              if (widget.controller.activeHostClientCount > 0 ||
                  widget.controller.hostChatMessages.isNotEmpty) ...<Widget>[
                const SizedBox(height: 20),
                _buildHostActiveChatCard(context),
              ],
              const SizedBox(height: 26),
              _buildPeersHeader(context),
              const SizedBox(height: 14),
              _buildPeersGrid(context, constraints.maxWidth),
            ],
          ),
        );
      },
    );
  }

  Widget _buildThisWorkstationCard(BuildContext context) {
    final String formattedId = widget.controller.identity.formattedDeskId;

    return NeoCard(
      topAccentColor: AppColors.vibrantGreen,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.vibrantGreenSoft,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.darkOutline, width: 1.5),
                ),
                child: const Icon(
                  Icons.desktop_windows_rounded,
                  color: AppColors.onVibrantGreen,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Esta área de trabalho',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              StatusBadge(
                label: widget.controller.activeHostClientCount > 0
                    ? '${widget.controller.activeHostClientCount} Operador(es)'
                    : 'Pronto',
                dotColor: AppColors.vibrantGreen,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Compartilhe este código de 9 dígitos para permitir acesso autorizado a este dispositivo:',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.elevatedSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.darkOutline, width: 1.6),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 10,
              children: <Widget>[
                SelectableText(
                  formattedId,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: AppColors.textPrimary,
                    fontFamily: 'Consolas',
                  ),
                ),
                VibrantButton(
                  label: 'Copiar ID',
                  icon: Icons.copy_rounded,
                  variant: VibrantButtonVariant.secondaryWhite,
                  compact: true,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: widget.controller.identity.deskId));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Código DeskView copiado: $formattedId')),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              StatusBadge(
                label: 'LAN: ${widget.controller.networkSnapshot.primaryLocalIp}:${widget.controller.identity.listenPort}',
                backgroundColor: AppColors.inputSurface,
                textColor: AppColors.textPrimary,
                icon: Icons.lan_rounded,
              ),
              StatusBadge(
                label: 'WAN: ${widget.controller.networkSnapshot.formattedPublicEndpoint}',
                backgroundColor: AppColors.accentBlueSoft,
                textColor: AppColors.textPrimary,
                icon: Icons.public_rounded,
              ),
            ],
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: () => widget.controller.setSelectedNavIndex(2),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    widget.controller.identity.hasUnattendedPassword
                        ? Icons.verified_user_rounded
                        : Icons.lock_open_rounded,
                    size: 17,
                    color: AppColors.accentBlue,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      widget.controller.identity.hasUnattendedPassword
                          ? 'Senha de acesso desassistido ativa (Gerenciar...)'
                          : 'Configurar senha de acesso não supervisionado...',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accentBlue,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRemoteConnectCard(BuildContext context) {
    return NeoCard(
      topAccentColor: AppColors.accentBlue,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.accentBlueSoft,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.darkOutline, width: 1.5),
                ),
                child: const Icon(
                  Icons.cast_connected_rounded,
                  color: AppColors.textPrimary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Outra área de trabalho',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const StatusBadge(
                label: 'LAN • P2P STUN • Relay',
                backgroundColor: AppColors.vibrantGreenSoft,
                textColor: AppColors.onVibrantGreen,
                icon: Icons.hub_rounded,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Insira o código DeskView de 9 dígitos ou IP:Porta do dispositivo que deseja controlar:',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: const Key('connect_target_input'),
                  controller: _targetController,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Consolas',
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Ex: 482 910 375 ou IP:7070',
                    prefixIcon: Icon(Icons.tag_rounded, color: AppColors.textPrimary),
                  ),
                  onSubmitted: (_) =>
                      _triggerConnect(_targetController.text, _passwordController.text),
                ),
              ),
              const SizedBox(width: 12),
              VibrantButton(
                key: const Key('btn_connect_now'),
                label: 'CONECTAR',
                icon: Icons.bolt_rounded,
                variant: VibrantButtonVariant.vibrantGreen,
                onPressed: () =>
                    _triggerConnect(_targetController.text, _passwordController.text),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Senha de Acesso Desassistido (Opcional — deixe vazio para solicitar aprovação na tela):',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12.5),
          ),
          const SizedBox(height: 6),
          TextField(
            key: const Key('connect_password_input'),
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              hintText: 'Senha opcional do computador remoto',
              prefixIcon: Icon(Icons.key_rounded, size: 18),
            ),
            onSubmitted: (_) =>
                _triggerConnect(_targetController.text, _passwordController.text),
          ),
        ],
      ),
    );
  }

  Widget _buildHostActiveChatCard(BuildContext context) {
    return NeoCard(
      topAccentColor: AppColors.warningAmber,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.forum_rounded, color: AppColors.textPrimary),
              const SizedBox(width: 8),
              Text(
                'Chat em Tempo Real com Operadores Conectados (${widget.controller.activeHostClientCount})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            constraints: const BoxConstraints(maxHeight: 110),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.inputSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.darkOutline, width: 1.3),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.controller.hostChatMessages.length,
              itemBuilder: (BuildContext context, int i) {
                final SessionChatMessage msg = widget.controller.hostChatMessages[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '[${msg.formattedTime}] ${msg.senderName}: ${msg.text}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Consolas',
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _hostChatInputController,
                  decoration: const InputDecoration(
                    hintText: 'Responder aos operadores conectados...',
                  ),
                  onSubmitted: (String v) {
                    widget.controller.sendHostChatReply(v);
                    _hostChatInputController.clear();
                  },
                ),
              ),
              const SizedBox(width: 10),
              VibrantButton(
                label: 'Enviar',
                icon: Icons.send_rounded,
                compact: true,
                onPressed: () {
                  widget.controller.sendHostChatReply(_hostChatInputController.text);
                  _hostChatInputController.clear();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPeersHeader(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 10,
      children: <Widget>[
        Text(
          'Sessões Recentes, Favoritos & Dispositivos na Rede',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 19),
        ),
        Wrap(
          spacing: 8,
          children: <Widget>[
            _buildFilterChip('Todos', 0),
            _buildFilterChip('Favoritos', 1),
            _buildFilterChip('Descobertos Online', 2),
          ],
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, int index) {
    final bool selected = _peerFilterIndex == index;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: selected ? AppColors.onVibrantGreen : AppColors.textPrimary,
        ),
      ),
      selected: selected,
      selectedColor: AppColors.vibrantGreen,
      backgroundColor: AppColors.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.darkOutline, width: 1.5),
      ),
      onSelected: (_) => setState(() => _peerFilterIndex = index),
    );
  }

  Widget _buildPeersGrid(BuildContext context, double availableWidth) {
    final List<PeerDevice> allPeers = widget.controller.combinedPeers.where((PeerDevice p) {
      if (_peerFilterIndex == 1) return p.isFavorite;
      if (_peerFilterIndex == 2) return p.isOnline;
      return true;
    }).toList();

    if (allPeers.isEmpty) {
      return NeoCard(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            'Nenhum dispositivo encontrado neste filtro.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      );
    }

    final int columns = availableWidth >= 1100 ? 3 : (availableWidth >= 680 ? 2 : 1);
    const double spacing = 16;
    final double cardWidth = (availableWidth - (spacing * (columns - 1))) / columns;

    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: allPeers.map((PeerDevice peer) {
        return SizedBox(
          width: columns == 1 ? double.infinity : cardWidth.clamp(260.0, 520.0),
          child: _buildPeerCard(context, peer),
        );
      }).toList(),
    );
  }

  Widget _buildPeerCard(BuildContext context, PeerDevice peer) {
    final String badgeText = switch (peer.source) {
      PeerDiscoverySource.localLan => 'LAN Direta',
      PeerDiscoverySource.globalSignaling => 'Rede Global',
      PeerDiscoverySource.loopback => 'Loopback',
      PeerDiscoverySource.savedHistory => 'Salvo',
    };

    return NeoCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: peer.isOnline ? AppColors.vibrantGreenSoft : AppColors.inputSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.darkOutline, width: 1.5),
                ),
                child: const Icon(
                  Icons.computer_rounded,
                  color: AppColors.textPrimary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      peer.hostName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      peer.formattedId,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                        fontFamily: 'Consolas',
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: peer.isFavorite ? 'Remover dos Favoritos' : 'Favoritar',
                onPressed: () => widget.controller.toggleFavoritePeer(peer.key),
                icon: Icon(
                  peer.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                  color: peer.isFavorite ? AppColors.warningAmber : AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              StatusBadge(
                label: badgeText,
                dotColor: peer.isOnline ? AppColors.vibrantGreen : AppColors.subtleOutline,
                backgroundColor:
                    peer.isOnline ? AppColors.vibrantGreenSoft : AppColors.inputSurface,
              ),
              const SizedBox(width: 8),
              StatusBadge(
                label: '${peer.monitorCount} Monitor(es)',
                backgroundColor: AppColors.inputSurface,
                textColor: AppColors.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: VibrantButton(
                  label: 'Conectar',
                  icon: Icons.bolt_rounded,
                  compact: true,
                  onPressed: () => _triggerConnect(
                    peer.deskId.isNotEmpty ? peer.deskId : peer.endpoint,
                    peer.savedPassword,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Remover do Histórico',
                onPressed: () => widget.controller.removeSavedPeer(peer.key),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.inputSurface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: const BorderSide(color: AppColors.darkOutline, width: 1.4),
                  ),
                ),
                icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textPrimary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
