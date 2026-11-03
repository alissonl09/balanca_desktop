import 'package:flutter/material.dart';

import '../../core/offline/offline_models.dart';
import '../../core/offline/offline_station.dart';
import '../../core/widgets/visual_components.dart';

/// Apenas reflete o agregado ativo; não transforma a prévia antiga em captura.
class LocalWeighingNotice extends StatelessWidget {
  const LocalWeighingNotice({super.key, required this.station});
  final OfflineStation station;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: station,
    builder: (context, _) {
      final w = station.activeWeighing;
      if (w == null) {
        return const PageHeading(
          title: 'Pesagem',
          subtitle:
              'Consulte e registre as informações da operação de pesagem.',
          asset: 'balanca_icon',
        );
      }
      final message = switch (w.phase) {
        WeighingPhase.nova => 'Nova pesagem local',
        WeighingPhase.aberta => 'Pesagem aberta localmente',
        WeighingPhase.fechada => 'Pesagem fechada localmente',
        WeighingPhase.ticketPendente => 'Ticket aguardando sincronização',
        WeighingPhase.concluida => 'Operação de ticket confirmada',
      };
      final sync = switch (w.syncStatus) {
        WeighingSyncStatus.semEventos => 'sem eventos de envio',
        WeighingSyncStatus.pendente => 'aguardando sincronização',
        WeighingSyncStatus.sincronizando => 'envio em andamento',
        WeighingSyncStatus.sincronizada => 'sincronização confirmada',
        WeighingSyncStatus.erro => 'erro de sincronização',
      };
      return Tooltip(
        message:
            '${w.plate}: estado somente em memória; não há persistência definitiva.',
        child: PageHeading(
          key: const ValueKey('local-weighing-state'),
          title: 'Pesagem',
          subtitle: '$message — $sync',
          asset: 'balanca_icon',
        ),
      );
    },
  );
}
