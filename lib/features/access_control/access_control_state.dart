import 'package:flutter/foundation.dart';

enum GateSide { entry, exit }

class GateEquipment {
  const GateEquipment(this.id, this.name);
  final String id, name;
}

abstract interface class GateEquipmentSource {
  List<GateEquipment> get available;
}

class MockGateEquipmentSource implements GateEquipmentSource {
  const MockGateEquipmentSource();
  @override
  List<GateEquipment> get available => const [
    GateEquipment('entrada-01', 'Cancela Entrada 01'),
    GateEquipment('saida-01', 'Cancela Saída 01'),
    GateEquipment('apoio-01', 'Cancela Pátio'),
    GateEquipment('balanca-01', 'Cancela Balança'),
  ];
}

enum GateState { closed, open, moving, error }

enum TrafficLightState { red, green }

/// Simulação vinculada ao ID físico configurado em cada papel lógico.
class AccessControlState extends ChangeNotifier {
  final _equipmentBySide = {
    GateSide.entry: 'mock-entry',
    GateSide.exit: 'mock-exit',
  };
  final _gates = <String, GateState>{};
  String equipmentId(GateSide side) => _equipmentBySide[side]!;
  void bindEquipment(GateSide side, String? id) {
    _equipmentBySide[side] = id ?? 'mock-${side.name}';
    notifyListeners();
  }

  void bindEquipments(String? entryId, String? exitId) {
    _equipmentBySide[GateSide.entry] = entryId ?? 'mock-entry';
    _equipmentBySide[GateSide.exit] = exitId ?? 'mock-exit';
    notifyListeners();
  }

  GateState gateForEquipment(String id) => _gates[id] ?? GateState.closed;
  GateState gate(GateSide side) => gateForEquipment(equipmentId(side));
  TrafficLightState light(GateSide side) => gate(side) == GateState.open
      ? TrafficLightState.green
      : TrafficLightState.red;
  void simulateGate(GateSide side, GateState state) {
    _gates[equipmentId(side)] = state;
    notifyListeners();
  }
}
