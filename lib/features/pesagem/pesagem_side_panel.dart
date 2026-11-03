import 'package:flutter/material.dart';

import 'pesagem_layout.dart';
import 'operation_preview.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/visual_components.dart';

class PesagemSidePanel extends StatefulWidget {
  const PesagemSidePanel({
    super.key,
    required this.layout,
    this.integratedSgv = false,
    this.accessControl,
    this.vehicles = operationQueuePreview,
    this.yardVehicles = yardQueuePreview,
  });
  final PesagemLayout layout;
  final bool integratedSgv;
  final Widget? accessControl;
  final List<({String plate, String? trailer, String time})> vehicles;
  final List<({String plate, String? trailer, String time})> yardVehicles;

  @override
  State<PesagemSidePanel> createState() => _PesagemSidePanelState();
}

class _PesagemSidePanelState extends State<PesagemSidePanel> {
  final _search = TextEditingController();
  final _operationScroll = ScrollController();
  String _filter = '';
  bool _showYard = false;
  PesagemLayout get layout => widget.layout;

  @override
  void initState() {
    super.initState();
    _showYard = widget.integratedSgv;
  }

  @override
  void didUpdateWidget(covariant PesagemSidePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.integratedSgv != widget.integratedSgv) {
      _showYard = widget.integratedSgv;
      _search.clear();
      _filter = '';
    }
  }

  void _selectQueue(bool yard) {
    if (_showYard == yard) return;
    setState(() {
      _showYard = yard;
      _search.clear();
      _filter = '';
      if (_operationScroll.hasClients) _operationScroll.jumpTo(0);
    });
  }

  void _filterOperations() =>
      setState(() => _filter = normalizePlate(_search.text));

  @override
  void dispose() {
    _search.dispose();
    _operationScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const ValueKey('pesagem-side-panel'),
    child: Column(
      children: [
        _queue(),
        if (widget.accessControl != null) ...[
          SizedBox(height: layout.gap),
          VisualCard(
            key: const ValueKey('access-control-card'),
            padding: EdgeInsets.all(layout.panelPadding),
            child: widget.accessControl!,
          ),
        ],
      ],
    ),
  );

  Widget _queue() {
    final yard = widget.integratedSgv && _showYard;
    final vehicles = (yard ? widget.yardVehicles : widget.vehicles)
        .where(
          (operation) =>
              operation.plate.contains(_filter) ||
              (operation.trailer ?? '').contains(_filter),
        )
        .toList();
    return VisualCard(
      padding: EdgeInsets.all(layout.spacious ? 16 : 10),
      child: Column(
        children: [
          Row(
            children: [
              const AppAsset('truck', size: 23),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  widget.integratedSgv ? 'Veículos' : 'Veículos em Operação',
                  style: const TextStyle(
                    color: AppColors.green,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                key: const ValueKey('queue-count'),
                width: 27,
                height: 27,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.paleGreen,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${vehicles.length}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.green,
                  ),
                ),
              ),
            ],
          ),
          if (widget.integratedSgv) ...[
            SizedBox(height: layout.spacious ? 12 : 7),
            Row(
              children: [
                Expanded(child: _queueTab('Veículos no Pátio', true)),
                const SizedBox(width: 5),
                Expanded(child: _queueTab('Veículos em Operação', false)),
              ],
            ),
          ],
          SizedBox(height: layout.spacious ? 14 : 8),
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 190,
              height: layout.fieldHeight,
              child: FocusTraversalOrder(
                order: const NumericFocusOrder(30),
                child: TextField(
                  key: const ValueKey('operation-search'),
                  controller: _search,
                  maxLength: 8,
                  style: const TextStyle(fontSize: 14),
                  onChanged: (_) => _filterOperations(),
                  onSubmitted: (_) => _filterOperations(),
                  decoration: InputDecoration(
                    hintText: 'Pesquisar placa',
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    suffixIconConstraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 32,
                    ),
                    suffixIcon: IconButton(
                      tooltip: yard
                          ? 'Pesquisar no pátio'
                          : 'Pesquisar em operação',
                      iconSize: 20,
                      color: AppColors.green,
                      onPressed: _filterOperations,
                      icon: const Icon(Icons.search),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              SizedBox(
                width: 70,
                child: Text(
                  'Cavalo',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
              SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Carreta',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
              SizedBox(width: 7),
              SizedBox(
                width: 42,
                child: Text(
                  yard ? 'Entrada' : 'Horário',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
            ],
          ),
          SizedBox(
            key: const ValueKey('operation-list-area'),
            height: layout.queueRowHeight * 5,
            child: vehicles.isEmpty
                ? Center(
                    child: Text(
                      yard
                          ? 'Nenhum veículo no pátio encontrado.'
                          : 'Nenhuma operação encontrada.',
                      style: TextStyle(fontSize: 13),
                    ),
                  )
                : Scrollbar(
                    controller: _operationScroll,
                    thumbVisibility: vehicles.length > 5,
                    thickness: 4,
                    radius: const Radius.circular(4),
                    child: ListView.builder(
                      key: const ValueKey('operation-list'),
                      controller: _operationScroll,
                      primary: false,
                      padding: const EdgeInsets.only(right: 8),
                      itemExtent: layout.queueRowHeight,
                      itemCount: vehicles.length,
                      itemBuilder: (context, index) {
                        final vehicle = vehicles[index];
                        return Container(
                          key: ValueKey('queue-row-${vehicle.plate}-$index'),
                          decoration: BoxDecoration(
                            border: index == vehicles.length - 1
                                ? null
                                : const Border(
                                    bottom: BorderSide(
                                      color: Color(0xffedf0f1),
                                    ),
                                  ),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 70,
                                child: Text(
                                  vehicle.plate,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  _trailerLabel(vehicle.trailer),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xff495057),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 7),
                              SizedBox(
                                width: 42,
                                child: Text(
                                  vehicle.time,
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xff495057),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _trailerLabel(String? trailer) =>
      trailer?.trim().isNotEmpty == true ? trailer!.trim() : '-';

  Widget _queueTab(String label, bool yard) {
    final selected = _showYard == yard;
    return TextButton(
      key: ValueKey(yard ? 'queue-tab-yard' : 'queue-tab-operation'),
      onPressed: () => _selectQueue(yard),
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
        foregroundColor: selected ? Colors.white : AppColors.green,
        backgroundColor: selected ? AppColors.green : AppColors.paleGreen,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          maxLines: 1,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
