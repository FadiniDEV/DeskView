import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/entities/session_models.dart';
import '../../services/communication/connection_orchestrator.dart';
import '../controllers/app_controller.dart';
import '../widgets/accept_session_dialog.dart';
import '../widgets/status_badge.dart';
import '../widgets/vibrant_button.dart';
import 'home_dashboard_screen.dart';
import 'network_security_screen.dart';
import 'peripherals_hub_screen.dart';
import 'remote_session_screen.dart';

/// Shell Adaptativo Material Design 3 que organiza a navegação entre Windows Desktop
/// (NavigationRail lateral + Abas de Sessão superiores) e Android Mobile (NavigationBar inferior).
class AdaptiveShellScreen extends StatelessWidget {
  final AppController controller;

  const AdaptiveShellScreen({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool isDesktop = constraints.maxWidth >= 880;
            final IncomingConnectionRequest? incomingReq =
                controller.activeIncomingModalRequest;

            return Scaffold(
              backgroundColor: AppColors.scaffoldBackground,
              body: SafeArea(
                child: Stack(
                  children: <Widget>[
                    Column(
                      children: <Widget>[
                        _buildTopAppBar(context, isDesktop),
                        if (controller.isConnectingBannerVisible)
                          _buildConnectingBanner(context),
                        if (controller.openSessions.isNotEmpty)
                          _buildSessionTabsBar(context),
                        Expanded(
                          child: Row(
                            children: <Widget>[
                              if (isDesktop) _buildDesktopNavigationRail(context),
                              Expanded(
                                child: _buildMainContentArea(context),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (incomingReq != null)
                      Container(
                        color: Colors.black54,
                        child: AcceptSessionDialog(
                          request: incomingReq,
                          onDecision: (bool approved, SessionPermissions perms) {
                            controller.resolveIncomingSessionDecision(
                              approved: approved,
                              permissions: perms,
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              bottomNavigationBar: isDesktop ? null : _buildMobileNavigationBar(context),
            );
          },
        );
      },
    );
  }

  Widget _buildTopAppBar(BuildContext context, bool isDesktop) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 22 : 14, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.cardSurface,
        border: Border(
          bottom: BorderSide(color: AppColors.darkOutline, width: 1.8),
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.vibrantGreen,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.darkOutline, width: 1.8),
            ),
            child: const Text(
              'DV',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: AppColors.onVibrantGreen,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'DeskView',
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(width: 14),
          Flexible(
            child: StatusBadge(
              label: controller.networkStatusLabel,
              dotColor: controller.isCloudConnected
                  ? AppColors.vibrantGreen
                  : AppColors.warningAmber,
              backgroundColor: controller.isCloudConnected
                  ? AppColors.vibrantGreenSoft
                  : AppColors.warningAmberSoft,
            ),
          ),
          const Spacer(),
          if (isDesktop)
            VibrantButton(
              label: 'Acesso Desassistido',
              icon: Icons.lock_person_rounded,
              variant: VibrantButtonVariant.secondaryWhite,
              compact: true,
              onPressed: () => controller.setSelectedNavIndex(2),
            ),
        ],
      ),
    );
  }

  Widget _buildConnectingBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.vibrantGreenSoft,
        border: Border(
          bottom: BorderSide(color: AppColors.darkOutline, width: 1.6),
        ),
      ),
      child: Row(
        children: <Widget>[
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.onVibrantGreen,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              controller.connectingBannerText,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.onVibrantGreen,
              ),
            ),
          ),
          VibrantButton(
            label: 'Cancelar',
            variant: VibrantButtonVariant.dangerRed,
            compact: true,
            onPressed: controller.cancelOngoingConnection,
          ),
        ],
      ),
    );
  }

  Widget _buildSessionTabsBar(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: AppColors.secondaryBackground,
        border: Border(
          bottom: BorderSide(color: AppColors.darkOutline, width: 1.5),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: ChoiceChip(
              label: const Text(
                'Painel Principal',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              selected: controller.activeSessionTabIndex == -1,
              selectedColor: AppColors.vibrantGreen,
              backgroundColor: AppColors.cardSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: AppColors.darkOutline, width: 1.5),
              ),
              onSelected: (_) => controller.selectSessionTab(-1),
            ),
          ),
          for (int i = 0; i < controller.openSessions.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: InputChip(
                label: Text(
                  'Tela: ${controller.openSessions[i].remoteHostName}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                selected: controller.activeSessionTabIndex == i,
                selectedColor: AppColors.vibrantGreen,
                backgroundColor: AppColors.cardSurface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: AppColors.darkOutline, width: 1.5),
                ),
                onSelected: (_) => controller.selectSessionTab(i),
                onDeleted: () => controller.closeSessionTab(controller.openSessions[i]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDesktopNavigationRail(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.sidebarBackground,
        border: Border(
          right: BorderSide(color: AppColors.darkOutline, width: 1.8),
        ),
      ),
      child: NavigationRail(
        backgroundColor: Colors.transparent,
        selectedIndex: controller.selectedNavIndex,
        onDestinationSelected: controller.setSelectedNavIndex,
        labelType: NavigationRailLabelType.all,
        indicatorColor: AppColors.vibrantGreen,
        selectedIconTheme: const IconThemeData(color: AppColors.onVibrantGreen),
        unselectedIconTheme: const IconThemeData(color: AppColors.textSecondary),
        selectedLabelTextStyle: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
        unselectedLabelTextStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
        destinations: const <NavigationRailDestination>[
          NavigationRailDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: Text('Início'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.sports_esports_outlined),
            selectedIcon: Icon(Icons.sports_esports_rounded),
            label: Text('Periféricos'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.hub_outlined),
            selectedIcon: Icon(Icons.hub_rounded),
            label: Text('Rede & Seg.'),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileNavigationBar(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.darkOutline, width: 1.8),
        ),
      ),
      child: NavigationBar(
        backgroundColor: AppColors.cardSurface,
        indicatorColor: AppColors.vibrantGreen,
        selectedIndex: controller.selectedNavIndex,
        onDestinationSelected: controller.setSelectedNavIndex,
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Início',
          ),
          NavigationDestination(
            icon: Icon(Icons.sports_esports_outlined),
            selectedIcon: Icon(Icons.sports_esports_rounded),
            label: 'Periféricos',
          ),
          NavigationDestination(
            icon: Icon(Icons.hub_outlined),
            selectedIcon: Icon(Icons.hub_rounded),
            label: 'Rede & Seg.',
          ),
        ],
      ),
    );
  }

  Widget _buildMainContentArea(BuildContext context) {
    final RemoteSessionClientController? session = controller.activeSession;
    if (session != null) {
      return RemoteSessionScreen(
        session: session,
        peripheralManager: controller.peripheralManager,
        onCloseSession: () => controller.closeSessionTab(session),
      );
    }

    return switch (controller.selectedNavIndex) {
      0 => HomeDashboardScreen(controller: controller),
      1 => PeripheralsHubScreen(controller: controller),
      2 => NetworkSecurityScreen(controller: controller),
      _ => HomeDashboardScreen(controller: controller),
    };
  }
}
