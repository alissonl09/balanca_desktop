import 'offline_models.dart';

/// Uma gravação deve ser atômica: dados físicos e eventos no mesmo agregado.
/// Um adaptador de banco poderá cumprir este contrato sem mudar a tela.
abstract interface class LocalPesagemStore {
  Future<List<LocalWeighing>> loadAll();
  Future<void> save(LocalWeighing weighing);
}

/// Somente memória: reiniciar o processo perde dados e IDs desta demonstração.
class MemoryLocalPesagemStore implements LocalPesagemStore {
  final _items = <String, LocalWeighing>{};

  @override
  Future<List<LocalWeighing>> loadAll() async =>
      List.unmodifiable(_items.values);

  @override
  Future<void> save(LocalWeighing weighing) async {
    _items[weighing.idLocal] = weighing;
  }
}
