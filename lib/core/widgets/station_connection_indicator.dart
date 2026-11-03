import 'package:flutter/material.dart';

import '../offline/offline_models.dart';
import '../offline/offline_station.dart';

/// Visível no cabeçalho de todas as páginas, com texto além da cor.
class StationConnectionIndicator extends StatelessWidget {
  const StationConnectionIndicator({super.key, required this.station});
  final OfflineStation station;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: station,
    builder: (context, _) {
      final (icon, color, label) = switch (station.connection) {
        StationConnection.online => (
          Icons.circle,
          const Color(0xff126632),
          'Online${station.pendingCount == 0 ? '' : ' · ${station.pendingCount} pendências'}',
        ),
        StationConnection.offline => (
          Icons.circle,
          const Color(0xff9a4600),
          'Offline · ${station.pendingCount} pendências',
        ),
        StationConnection.sincronizando => (
          Icons.sync,
          const Color(0xff1a4f99),
          'Sincronizando · ${station.syncCompleted}/${station.syncTotal}',
        ),
      };
      return Tooltip(
        message: 'Estado da estação controlado localmente nesta etapa; sem sondagem de rede.',
        child: Semantics(
          liveRegion: true,
          child: Container(
            key: const ValueKey('station-connectivity'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 15),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
