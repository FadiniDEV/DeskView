enum PeripheralCategory {
  mouse('Mouse', 'Apontador e Scroll'),
  keyboard('Teclado', 'Teclas Físicas / ScanCode'),
  gamepad('Controle de Videogame', 'XInput / Gamepad Analógico'),
  joystick('Joystick / FlightStick', 'HID Multi-Eixo');

  final String title;
  final String subtitle;
  const PeripheralCategory(this.title, this.subtitle);
}

/// Representa um periférico de entrada conectado localmente ou sincronizado na sessão.
class PeripheralDevice {
  final String id;
  final String name;
  final PeripheralCategory category;
  final String vendorProductId;
  final bool isConnected;
  final bool isTransmitEnabled;
  final int buttonCount;
  final int axisCount;
  final DateTime lastActivity;
  final String connectionBus; // USB, Bluetooth, XInput, Sistema, Virtual

  const PeripheralDevice({
    required this.id,
    required this.name,
    required this.category,
    this.vendorProductId = '0000:0000',
    this.isConnected = true,
    this.isTransmitEnabled = true,
    this.buttonCount = 0,
    this.axisCount = 0,
    required this.lastActivity,
    this.connectionBus = 'Sistema',
  });

  PeripheralDevice copyWith({
    String? id,
    String? name,
    PeripheralCategory? category,
    String? vendorProductId,
    bool? isConnected,
    bool? isTransmitEnabled,
    int? buttonCount,
    int? axisCount,
    DateTime? lastActivity,
    String? connectionBus,
  }) {
    return PeripheralDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      vendorProductId: vendorProductId ?? this.vendorProductId,
      isConnected: isConnected ?? this.isConnected,
      isTransmitEnabled: isTransmitEnabled ?? this.isTransmitEnabled,
      buttonCount: buttonCount ?? this.buttonCount,
      axisCount: axisCount ?? this.axisCount,
      lastActivity: lastActivity ?? this.lastActivity,
      connectionBus: connectionBus ?? this.connectionBus,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'name': name,
        'category': category.name,
        'vendorProductId': vendorProductId,
        'isConnected': isConnected,
        'isTransmitEnabled': isTransmitEnabled,
        'buttonCount': buttonCount,
        'axisCount': axisCount,
        'connectionBus': connectionBus,
      };

  factory PeripheralDevice.fromMap(Map<String, dynamic> map) {
    final String catStr = (map['category'] as String?) ?? 'mouse';
    final PeripheralCategory cat = PeripheralCategory.values.firstWhere(
      (PeripheralCategory e) => e.name == catStr,
      orElse: () => PeripheralCategory.mouse,
    );
    return PeripheralDevice(
      id: (map['id'] as String?) ?? 'dev_0',
      name: (map['name'] as String?) ?? 'Dispositivo de Entrada',
      category: cat,
      vendorProductId: (map['vendorProductId'] as String?) ?? '0000:0000',
      isConnected: (map['isConnected'] as bool?) ?? true,
      isTransmitEnabled: (map['isTransmitEnabled'] as bool?) ?? true,
      buttonCount: (map['buttonCount'] as int?) ?? 0,
      axisCount: (map['axisCount'] as int?) ?? 0,
      lastActivity: DateTime.now(),
      connectionBus: (map['connectionBus'] as String?) ?? 'Sistema',
    );
  }
}
