import 'settings_models.dart';

/// Opções exclusivamente simuladas. Nenhuma descoberta de Windows/equipamentos.
const mockUnits = [
  UnitOption(4, 'JAPY'),
  UnitOption(1, 'MATRIZ'),
  UnitOption(7, 'ARMAZÉM'),
];

const mockPrinters = [
  PrinterOption(
    id: 'ticket-usb',
    name: 'Ticket USB (simulada)',
    status: PrinterStatus.online,
    format: PrinterFormat.ticket,
    connectionType: 'Local',
    connection: 'USB001',
    sizes: ['Bobina 80 mm', 'Bobina 58 mm'],
    sources: ['Bobina'],
  ),
  PrinterOption(
    id: 'ticket-rede',
    name: 'Ticket Rede (simulada)',
    status: PrinterStatus.offline,
    format: PrinterFormat.ticket,
    connectionType: 'Rede',
    connection: '192.168.1.50',
    sizes: ['Bobina 80 mm'],
    sources: ['Bobina'],
  ),
  PrinterOption(
    id: 'a4-usb',
    name: 'A4 USB (simulada)',
    status: PrinterStatus.online,
    format: PrinterFormat.a4,
    connectionType: 'Local',
    connection: 'USB002',
    sizes: ['A4', 'Carta'],
    sources: ['Bandeja 1', 'Alimentação manual'],
  ),
  PrinterOption(
    id: 'a4-rede',
    name: 'A4 Rede (simulada)',
    status: PrinterStatus.unavailable,
    format: PrinterFormat.a4,
    connectionType: 'Rede',
    connection: '192.168.1.60',
    sizes: ['A4'],
    sources: ['Bandeja 1'],
  ),
];
