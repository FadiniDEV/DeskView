import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:deskview_flutter/app.dart';
import 'package:deskview_flutter/core/crypto/session_cipher.dart';
import 'package:deskview_flutter/core/utils/desk_id_formatter.dart';
import 'package:deskview_flutter/data/repositories/local_identity_repository.dart';
import 'package:deskview_flutter/domain/entities/connection_candidate.dart';
import 'package:deskview_flutter/domain/entities/desk_identity.dart';
import 'package:deskview_flutter/domain/entities/input_commands.dart';
import 'package:deskview_flutter/domain/entities/peer_device.dart';
import 'package:deskview_flutter/domain/entities/peripheral_device.dart';
import 'package:deskview_flutter/domain/entities/session_models.dart';
import 'package:deskview_flutter/platform/native_platform_bridge.dart';
import 'package:deskview_flutter/presentation/controllers/app_controller.dart';
import 'package:deskview_flutter/services/codec/desk_rt_tile_codec.dart';
import 'package:deskview_flutter/services/communication/connection_orchestrator.dart';
import 'package:deskview_flutter/services/communication/host_session_server.dart';
import 'package:deskview_flutter/services/communication/lan_discovery_service.dart';
import 'package:deskview_flutter/services/communication/packet_frame_io.dart';
import 'package:deskview_flutter/services/communication/session_transport.dart';
import 'package:deskview_flutter/services/communication/stun_client_service.dart';
import 'package:deskview_flutter/services/input/key_mapping_table.dart';
import 'package:deskview_flutter/services/input/peripheral_manager_service.dart';

void main() {
  group('1. Identidade, Criptografia SHA-256/HMAC e Sanitização de Arquivos', () {
    test('Gera DeskID de 9 dígitos determinístico e formata no padrão 000 000 000', () {
      final String id1 = SessionCipher.generateDeterministicDeskId('HOST-A|USER-1|windows');
      final String id2 = SessionCipher.generateDeterministicDeskId('HOST-A|USER-1|windows');
      expect(id1.length, 9);
      expect(id1, equals(id2));
      expect(DeskIdFormatter.isValidDeskId(id1), isTrue);
      expect(DeskIdFormatter.format('482910375'), equals('482 910 375'));
    });

    test('Assinatura HMAC-SHA256 valida mensagens legítimas e rejeita adulterações', () {
      const String body = 'REQ|482910375|PC-CASA|179.135.207.135:7070|192.168.1.10:7070|63800000000';
      final String sig = SessionCipher.signSignalPayload(body);
      expect(sig.length, 16);
      expect(SessionCipher.verifySignalSignature(sig, body), isTrue);
      expect(SessionCipher.verifySignalSignature(sig, '$body|SPOOF'), isFalse);
    });

    test('Cifragem autenticada de pacotes (sealPacket / openPacket) bloqueia pacotes corrompidos', () {
      final Uint8List plain = Uint8List.fromList(<int>[1, 2, 3, 4, 5, 99, 255]);
      final Uint8List sealed = SessionCipher.sealPacket(plain, 'chave_secreta_sessao');
      expect(sealed.length, greaterThan(plain.length));

      final Uint8List? opened = SessionCipher.openPacket(sealed, 'chave_secreta_sessao');
      expect(opened, isNotNull);
      expect(opened, equals(plain));

      // Adultera 1 byte do ciphertext
      sealed[14] ^= 0xff;
      expect(SessionCipher.openPacket(sealed, 'chave_secreta_sessao'), isNull);
    });

    test('Sanitiza nomes de arquivos contra Path Traversal e dispositivos reservados do Windows', () {
      expect(DeskIdFormatter.sanitizeFileName(r'..\..\Windows\System32\cmd.exe'), equals('cmd.exe'));
      expect(DeskIdFormatter.sanitizeFileName('CON.txt'), equals('_CON.txt'));
      expect(DeskIdFormatter.sanitizeFileName('LPT1.doc'), equals('_LPT1.doc'));
    });
  });

  group('2. Comunicação Entre Redes: LAN Discovery, STUN RFC 5389 e Framing Binário', () {
    test('Constrói e decodifica pacote de descoberta LAN DESKVIEW_V1 corretamente', () {
      final String pkt = LanDiscoveryService.buildDiscoveryPacket(
        deskId: '482910375',
        machineName: 'DESKTOP-LUCAS',
        userName: 'Lucas',
        localIp: '192.168.15.20',
        listenPort: 7070,
        monitorCount: 2,
      );
      final PeerDevice? parsed = LanDiscoveryService.parseDiscoveryPacket(pkt);
      expect(parsed, isNotNull);
      expect(parsed!.deskId, equals('482910375'));
      expect(parsed.hostName, equals('DESKTOP-LUCAS'));
      expect(parsed.ipAddress, equals('192.168.15.20'));
      expect(parsed.port, equals(7070));
      expect(parsed.monitorCount, equals(2));
    });

    test('Codifica STUN Binding Request e decodifica XOR-MAPPED-ADDRESS (RFC 5389)', () {
      final List<int> txId = List<int>.generate(12, (int i) => i + 1);
      final Uint8List req = StunClientService.buildStunBindingRequest(txId);
      expect(req.length, 20);

      // Simula um STUN Binding Response (0x0101) com XOR-MAPPED-ADDRESS (0x0020)
      // para o IP 179.135.207.135 e porta externa 54321
      const int cookie = 0x2112A442;
      const int rawPort = 54321;
      const int rawIp = (179 << 24) | (135 << 16) | (207 << 8) | 135;
      final int xorPort = rawPort ^ ((cookie >>> 16) & 0xffff);
      final int xorIp = rawIp ^ cookie;

      final Uint8List resp = Uint8List(32);
      final ByteData bd = ByteData.sublistView(resp);
      bd.setUint16(0, 0x0101, Endian.big); // Binding Success Response
      bd.setUint16(2, 12, Endian.big); // Message Length = 12 bytes
      bd.setUint32(4, cookie, Endian.big);
      bd.setUint16(20, 0x0020, Endian.big); // XOR-MAPPED-ADDRESS
      bd.setUint16(22, 8, Endian.big); // Attr Length = 8
      resp[24] = 0x00;
      resp[25] = 0x01; // IPv4
      bd.setUint16(26, xorPort, Endian.big);
      bd.setUint32(28, xorIp, Endian.big);

      final ({String ip, int port})? mapped = StunClientService.parseStunBindingResponse(resp);
      expect(mapped, isNotNull);
      expect(mapped!.ip, equals('179.135.207.135'));
      expect(mapped.port, equals(54321));
    });

    test('PacketStreamDecoder reconstrói múltiplos pacotes fragmentados e autenticados', () {
      const String key = 'sess_key_999';
      final Uint8List f1 = PacketFrameIO.encodeFrame(
        PacketType.chatMessage,
        <int>[65, 66, 67],
        encryptionKey: key,
      );
      final Uint8List f2 = PacketFrameIO.encodeFrame(
        PacketType.ping,
        <int>[1, 2, 3, 4],
        encryptionKey: key,
      );

      final Uint8List combined = Uint8List.fromList(<int>[...f1, ...f2]);
      final PacketStreamDecoder decoder = PacketStreamDecoder(encryptionKey: key);

      // Envia em duas metades cortadas no meio do frame
      final List<DecodedPacketFrame> part1 = decoder.addChunk(combined.sublist(0, 10));
      expect(part1, isEmpty);
      final List<DecodedPacketFrame> part2 = decoder.addChunk(combined.sublist(10));
      expect(part2.length, 2);
      expect(part2[0].type, equals(PacketType.chatMessage));
      expect(part2[0].payload, equals(<int>[65, 66, 67]));
      expect(part2[1].type, equals(PacketType.ping));
    });
  });

  group('3. Detecção e Transmissão de Mouse, Teclado (ScanCode) e Controles (Gamepad/Joystick)', () {
    test('Serializa e deserializa comandos de Mouse (5 botões + scroll vertical/horizontal)', () {
      const MouseInputCommand cmd = MouseInputCommand(
        action: MouseActionType.xButton1Down,
        normX: 0.25,
        normY: 0.75,
        wheelDeltaY: 120,
        wheelDeltaX: -60,
        buttonsMask: 0x09,
        sequenceNumber: 42,
      );
      final Uint8List bytes = cmd.toBytes();
      expect(bytes.length, 19);

      final MouseInputCommand decoded = MouseInputCommand.fromBytes(bytes);
      expect(decoded.action, equals(MouseActionType.xButton1Down));
      expect(decoded.normX, closeTo(0.25, 0.0001));
      expect(decoded.normY, closeTo(0.75, 0.0001));
      expect(decoded.wheelDeltaY, equals(120));
      expect(decoded.wheelDeltaX, equals(-60));
      expect(decoded.buttonsMask, equals(0x09));
      expect(decoded.sequenceNumber, equals(42));
    });

    test('Mapeia teclas de navegação como ExtendedKey com ScanCode Set 1 e serializa em 12 bytes', () {
      final MappedKeyDescriptor upArrow = KeyMappingTable.fromWinVirtualKey(0x26);
      expect(upArrow.winVirtualKey, equals(0x26));
      expect(upArrow.hardwareScanCode, equals(0x48));
      expect(upArrow.isExtendedKey, isTrue);

      final KeyInputCommand keyCmd = KeyInputCommand(
        winVirtualKey: upArrow.winVirtualKey,
        isDown: true,
        hardwareScanCode: upArrow.hardwareScanCode,
        isExtendedKey: upArrow.isExtendedKey,
        usbHidUsageId: upArrow.usbHidUsageId,
        modifiersMask: 0x02,
        sequenceNumber: 7,
      );
      final Uint8List bytes = keyCmd.toBytes();
      expect(bytes.length, 12);

      final KeyInputCommand restored = KeyInputCommand.fromBytes(bytes);
      expect(restored.winVirtualKey, equals(0x26));
      expect(restored.hardwareScanCode, equals(0x48));
      expect(restored.isExtendedKey, isTrue);
      expect(restored.isDown, isTrue);
      expect(restored.modifiersMask, equals(0x02));
    });

    test('Serializa e deserializa estado completo de Controle / Gamepad / Joystick (20 bytes)', () {
      const GamepadInputCommand gp = GamepadInputCommand(
        controllerIndex: 1,
        isConnected: true,
        buttonsMask: GamepadButtons.buttonA | GamepadButtons.rightShoulderRB | GamepadButtons.dpadUp,
        leftTrigger: 0.5,
        rightTrigger: 1.0,
        leftStickX: -0.75,
        leftStickY: 0.5,
        rightStickX: 0.25,
        rightStickY: -0.5,
        rudderAxisZ: 0.8,
        sequenceNumber: 99,
      );
      final Uint8List bytes = gp.toBytes();
      expect(bytes.length, 20);

      final GamepadInputCommand decoded = GamepadInputCommand.fromBytes(bytes);
      expect(decoded.controllerIndex, equals(1));
      expect(decoded.isConnected, isTrue);
      expect(decoded.isButtonPressed(GamepadButtons.buttonA), isTrue);
      expect(decoded.isButtonPressed(GamepadButtons.rightShoulderRB), isTrue);
      expect(decoded.isButtonPressed(GamepadButtons.dpadUp), isTrue);
      expect(decoded.isButtonPressed(GamepadButtons.buttonB), isFalse);
      expect(decoded.leftTrigger, closeTo(0.5, 0.01));
      expect(decoded.rightTrigger, closeTo(1.0, 0.01));
      expect(decoded.leftStickX, closeTo(-0.75, 0.01));
      expect(decoded.rightStickY, closeTo(-0.5, 0.01));
      expect(decoded.rudderAxisZ, closeTo(0.8, 0.01));
    });

    test('Desconexão de periférico (hotplug) libera automaticamente teclas retidas', () async {
      final PeripheralManagerService pm = PeripheralManagerService(NativePlatformBridge());
      await pm.refreshPeripherals();
      expect(pm.devices.length, greaterThanOrEqualTo(4));

      // Pressiona tecla Ctrl (0x11) e botão A do controle
      pm.emitVirtualKey(winVirtualKey: 0x11, isDown: true);
      expect(pm.pressedVirtualKeys.contains(0x11), isTrue);

      // Simula desconexão física do teclado
      final String kbdId = pm.devices
          .firstWhere((PeripheralDevice d) => d.category == PeripheralCategory.keyboard)
          .id;
      pm.setPeripheralConnectionState(kbdId, false);

      // Verifica que a tecla Ctrl foi liberada automaticamente para não travar o Host
      expect(pm.pressedVirtualKeys, isEmpty);
      pm.dispose();
    });
  });

  group('4. Sessão Completa Fim-a-Fim: Autorização, Bloqueio de Acesso e Codec DeskRT', () {
    test('Bloqueia conexão não autorizada quando a senha está incorreta e o usuário recusa', () async {
      final LocalIdentityRepository repo = LocalIdentityRepository(inMemoryOnly: true);
      DeskIdentity hostId = await repo.loadOrCreateIdentity();
      hostId = await repo.updateUnattendedPassword(hostId, 'SenhaCorreta#2026');

      final HostSessionServer server = HostSessionServer(
        identityRepository: repo,
        platformBridge: NativePlatformBridge(),
      );
      server.onAuthorizeSessionRequest = ({
        required String clientDeskId,
        required String clientHostName,
        required String remoteAddress,
      }) async {
        return (approved: false, permissions: const SessionPermissions());
      };

      final ({InMemoryLoopbackTransport client, InMemoryLoopbackTransport host}) pair =
          InMemoryLoopbackTransport.createPair(
        simulatedRoute: TransportRouteType.encryptedRelay,
      );
      server.acceptTransportConnection(pair.host);

      final RemoteSessionClientController clientSession = RemoteSessionClientController(
        sessionId: 'test_unauth',
        targetTitle: 'Host Protegido',
        targetDeskId: hostId.deskId,
        password: 'SenhaInvalida123',
        localIdentity: hostId.copyWith(localLoopbackNonce: 'outro_processo'),
        transport: pair.client,
      );

      final bool connected = await clientSession.startHandshakeAndSession();
      expect(connected, isFalse);
      expect(clientSession.statusMessage, contains('Acesso negado'));
      await server.dispose();
    });

    test('Estabelece sessão criptografada, transmite vídeo DeskRT, Chat e encerra com segurança', () async {
      final LocalIdentityRepository repo = LocalIdentityRepository(inMemoryOnly: true);
      DeskIdentity hostId = await repo.loadOrCreateIdentity();
      hostId = await repo.updateUnattendedPassword(hostId, 'Acesso123');

      final HostSessionServer server = HostSessionServer(
        identityRepository: repo,
        platformBridge: NativePlatformBridge(),
      );
      await server.start(hostId);

      final ({InMemoryLoopbackTransport client, InMemoryLoopbackTransport host}) pair =
          InMemoryLoopbackTransport.createPair(
        simulatedRoute: TransportRouteType.encryptedRelay,
      );
      server.acceptTransportConnection(pair.host);

      final RemoteSessionClientController clientSession = RemoteSessionClientController(
        sessionId: 'test_ok',
        targetTitle: 'Host Remoto WAN',
        targetDeskId: hostId.deskId,
        password: 'Acesso123',
        localIdentity: hostId,
        transport: pair.client,
      );

      final bool connected = await clientSession.startHandshakeAndSession();
      expect(connected, isTrue);
      expect(clientSession.isConnected, isTrue);

      // Aguarda recepção de Dirty Tiles do loop de captura do Host
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(clientSession.activeTiles, isNotEmpty);

      // Envia mensagem de chat e comando de gamepad
      clientSession.sendChatMessage('Olá via Túnel Relay!');
      clientSession.sendGamepadCommand(
        const GamepadInputCommand(buttonsMask: GamepadButtons.buttonA),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Encerra sessão com segurança
      await clientSession.disconnect();
      expect(clientSession.isConnected, isFalse);
      await server.dispose();
    });

    test('Codec DeskRT-Tile detecta apenas os blocos que mudaram entre quadros consecutivos', () {
      final DeskRtTileCodec codec = DeskRtTileCodec();
      const int w = 320, h = 180;
      final Uint8List frame1 = Uint8List(w * h * 4)..fillRange(0, w * h * 4, 40);

      // Quadro 1 (KeyFrame inicial): todos os 48 blocos (8x6) são transmitidos
      final Uint8List? encoded1 = codec.encodeDirtyTiles(
        rgbaBuffer: frame1,
        width: w,
        height: h,
        quality: 70,
      );
      expect(encoded1, isNotNull);
      final DirtyTileFrame? decoded1 = DeskRtTileCodec.unpackDirtyTileFrame(encoded1!);
      expect(decoded1!.tiles.length, equals(48));

      // Quadro 2 idêntico: nenhum bloco mudou -> retorna null (0 kbps gastos)
      final Uint8List? encoded2 = codec.encodeDirtyTiles(
        rgbaBuffer: frame1,
        width: w,
        height: h,
        quality: 70,
      );
      expect(encoded2, isNull);
    });
  });

  group('5. Interface Material Design 3 e Responsividade (Windows Desktop & Android Mobile)', () {
    testWidgets('Renderiza layout Desktop (NavigationRail) e Mobile (NavigationBar) sem erros',
        (WidgetTester tester) async {
      final LocalIdentityRepository repo = LocalIdentityRepository(inMemoryOnly: true);
      final AppController controller = AppController(
        identityRepository: repo,
        platformBridge: NativePlatformBridge(),
      );
      await controller.initialize(enableNetworkSockets: false);

      // 1. Modo Windows Desktop (1280x800)
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(DeskViewApp(controller: controller));
      await tester.pumpAndSettle();

      expect(find.text('Esta área de trabalho'), findsOneWidget);
      expect(find.text('Outra área de trabalho'), findsOneWidget);
      expect(find.byType(NavigationRail), findsOneWidget);

      // Navega para a aba de Periféricos
      controller.setSelectedNavIndex(1);
      await tester.pumpAndSettle();
      expect(find.text('Periféricos & Controles de Entrada'), findsOneWidget);

      // 2. Modo Android Mobile (412x915)
      tester.view.physicalSize = const Size(412, 915);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        controller.dispose();
      });
    });
  });
}
