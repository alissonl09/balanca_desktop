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
class PesagemActionScope extends StatefulWidget {
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
  State<PesagemActionScope> createState() => _PesagemActionScopeState();
}

class _PesagemActionScopeState extends State<PesagemActionScope> {
  final _focus = FocusScopeNode(debugLabel: 'Atalhos da pesagem');
  ModalRoute<dynamic>? _route;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_restoreScopeFocus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  void _restoreScopeFocus() {
    if (!mounted ||
        !widget.enabled ||
        _route?.isCurrent != true ||
        _focus.context == null ||
        _focus.hasFocus) {
      return;
    }
    final primary = FocusManager.instance.primaryFocus;
    // Ao desfocar ou fechar um diálogo, o Navigator pode focar a própria rota.
    // Recupera somente esse caso; nunca tira foco de outro controle ou modal.
    if (primary != null && _focus.ancestors.contains(primary)) {
      _focus.requestFocus();
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_restoreScopeFocus);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.enabled
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
                  widget.dispatcher.invoke(intent.action);
                  return null;
                },
              ),
            },
            // Ao desfocar um campo, o foco permanece abaixo de Shortcuts/Actions.
            // Sem este escopo, ele volta para a rota e deixa de alcançar F5–F12.
            child: FocusScope(
              node: _focus,
              autofocus: true,
              child: widget.child,
            ),
          ),
        )
      : widget.child;
}
