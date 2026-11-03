import 'package:flutter/foundation.dart';

enum AppPermission {
  weigh('Pesagem', 'Realizar pesagem'),
  useManual('Pesagem', 'Utilizar Peso Manual'),
  authorizeManual('Pesagem', 'Autorizar Peso Manual'),
  editOpen('Pesagem', 'Editar dados manuais de pesagem aberta'),
  releaseDivergence('Pesagem', 'Liberar divergência/tolerância'),
  reweigh('Pesagem', 'Corrigir/repesar'),
  cancelOperation('Pesagem', 'Cancelar operação (futuro)'),
  printTicket('Tickets', 'Imprimir ticket'),
  reprintTicket('Tickets', 'Reimprimir ticket'),
  cancelTicket('Tickets', 'Cancelar ticket'),
  readRegistry('Cadastros', 'Consultar'),
  insertRegistry('Cadastros', 'Inserir'),
  editRegistry('Cadastros', 'Alterar'),
  deactivateRegistry('Cadastros', 'Inativar/Excluir logicamente'),
  readReports('Relatórios', 'Consultar'),
  printReports('Relatórios', 'Imprimir'),
  exportReports('Relatórios', 'Exportar'),
  generalSettings('Configurações', 'Gerais'),
  vehicleSettings('Configurações', 'Gestão de Veículos'),
  printSettings('Configurações', 'Impressão'),
  indicators('Configurações', 'Indicadores'),
  indicatorModels('Configurações', 'Modelos de Indicadores'),
  permissions('Configurações', 'Permissões'),
  readUsers('Usuários', 'Consultar usuários'),
  assignProfile('Usuários', 'Atribuir perfil'),
  manageProfiles('Usuários', 'Administrar perfis');

  const AppPermission(this.group, this.label);
  final String group, label;
}

class PermissionProfile {
  PermissionProfile(this.code, this.name, Set<AppPermission> permissions)
    : grants = Set.of(permissions);
  final int code;
  final String name;
  final Set<AppPermission> grants;
  bool allows(AppPermission permission) =>
      code == 0 || grants.contains(permission);
  String get label => '$code — $name';
}

class DirectoryUser {
  DirectoryUser(this.id, this.name, this.registration, this.profileCode);
  final String id, name, registration;
  int profileCode;
  String get label => '$name — $registration';
}

/// Mock tipado substituível por uma pesquisa AD; não transporta senha.
abstract interface class UserDirectory {
  List<DirectoryUser> search(String query);
}

class PermissionState extends ChangeNotifier implements UserDirectory {
  final profiles = [
    PermissionProfile(0, 'Master', AppPermission.values.toSet()),
    PermissionProfile(1, 'Administrador', AppPermission.values.toSet()),
    PermissionProfile(2, 'Supervisor de Balança', {
      AppPermission.weigh,
      AppPermission.useManual,
      AppPermission.authorizeManual,
      AppPermission.cancelTicket,
      AppPermission.releaseDivergence,
      AppPermission.reprintTicket,
      AppPermission.editOpen,
    }),
    PermissionProfile(3, 'Líder de Operação', {
      AppPermission.weigh,
      AppPermission.releaseDivergence,
      AppPermission.reprintTicket,
    }),
    PermissionProfile(4, 'Operador', {
      AppPermission.weigh,
      AppPermission.reprintTicket,
    }),
  ];
  final users = [
    DirectoryUser('master', 'Configuração inicial (mock)', 'LOCAL', 0),
    DirectoryUser('alisson', 'Alisson Rodrigues Romano', '00001', 1),
    DirectoryUser('balanca', 'Autorizador local de demonstração', 'MOCK', 2),
    DirectoryUser('carlos', 'CARLOS ALMEIDA', '12345', 4),
  ];
  String currentUserId = 'alisson';
  PermissionProfile profile(int code) =>
      profiles.firstWhere((p) => p.code == code);
  bool userAllows(String id, AppPermission permission) {
    final user = users.where((u) => u.id == id).firstOrNull;
    return user != null && profile(user.profileCode).allows(permission);
  }

  bool allows(AppPermission permission) =>
      userAllows(currentUserId, permission);
  void setGrant(int code, AppPermission permission, bool value) {
    if (!allows(AppPermission.manageProfiles) || code == 0) return;
    if (value) {
      profile(code).grants.add(permission);
    } else {
      profile(code).grants.remove(permission);
    }
    notifyListeners();
  }

  void assign(String id, int code) {
    if (!allows(AppPermission.assignProfile)) return;
    profile(code); // rejeita perfil inexistente
    users.firstWhere((u) => u.id == id).profileCode = code;
    notifyListeners();
  }

  @override
  List<DirectoryUser> search(String query) => users
      .where(
        (u) => '${u.name} ${u.registration}'.toLowerCase().contains(
          query.trim().toLowerCase(),
        ),
      )
      .toList();
}
