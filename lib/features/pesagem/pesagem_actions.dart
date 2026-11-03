import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

/// Definição única dos rótulos e teclas da barra de ações.
enum PesagemAction {
  imprimir('Impr. Pesagem', 'imprimir-pesagem', 'F5', LogicalKeyboardKey.f5),
  nova('Nova Pesagem', '', 'F6', LogicalKeyboardKey.f6),
  salvar('Salvar Pesagem', 'salvar-pesagem', 'F10', LogicalKeyboardKey.f10),
  manual('Peso Manual', 'truck', 'F11', LogicalKeyboardKey.f11),
  pesar('Pesagem', 'truck', 'F12', LogicalKeyboardKey.f12);

  const PesagemAction(this.label, this.asset, this.shortcut, this.key);
  final String label, asset, shortcut;
  final LogicalKeyboardKey? key;
}

class PesagemActionIntent extends Intent {
  const PesagemActionIntent(this.action);
  final PesagemAction action;
}

/// Encaminha os atalhos do shell à mesma ação usada pelo clique na página ativa.
/// Não contém regras operacionais: validação e proteção de modais ficam na página.
class PesagemActionDispatcher {
  Future<void> Function(PesagemAction)? _handler;

  void bind(Future<void> Function(PesagemAction) handler) => _handler = handler;

  void unbind(Future<void> Function(PesagemAction) handler) {
    if (_handler == handler) _handler = null;
  }

  void invoke(PesagemAction action) => _handler?.call(action);
}

/// Envolve o shell inteiro enquanto Pesagem está ativa, inclusive cabeçalho/menu.
/// Em uso isolado, a própria página instala este mesmo escopo.
class PesagemActionScope extends StatelessWidget {
  const PesagemActionScope({
    super.key,
    required this.dispatcher,
    required this.child,
    this.enabled = true,
  });

  final PesagemActionDispatcher dispatcher;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) => enabled
      ? Shortcuts(
          shortcuts: {
            for (final action in PesagemAction.values)
              if (action.key != null)
                SingleActivator(action.key!, includeRepeats: false):
                    PesagemActionIntent(action),
          },
          child: Actions(
            actions: {
              PesagemActionIntent: CallbackAction<PesagemActionIntent>(
                onInvoke: (intent) {
                  dispatcher.invoke(intent.action);
                  return null;
                },
              ),
            },
            child: child,
          ),
        )
      : child;
}
