import 'package:flutter/material.dart';

import '../../core/permissions/permission_models.dart';
import 'settings_widgets.dart';

class PermissionsSettings extends StatefulWidget {
  const PermissionsSettings({super.key, required this.permissions});
  final PermissionState permissions;
  @override
  State<PermissionsSettings> createState() => _PermissionsSettingsState();
}

class _PermissionsSettingsState extends State<PermissionsSettings> {
  int _profile = 2;
  String _query = '';
  String? _userId;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.permissions,
    builder: (context, _) {
      final state = widget.permissions;
      final profile = state.profile(_profile);
      final user = state.users.where((u) => u.id == _userId).firstOrNull;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsSection(
            title: 'Perfis',
            description: 'Defaults iniciais parametrizáveis. Master mantém permissão total.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<int>(
                  key: const ValueKey('permission-profile'),
                  initialValue: _profile,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Perfil'),
                  items: [
                    for (final p in state.profiles)
                      DropdownMenuItem(value: p.code, child: Text(p.label)),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _profile = v);
                  },
                ),
                const SizedBox(height: 12),
                for (final group
                    in AppPermission.values.map((p) => p.group).toSet()) ...[
                  Text(
                    group,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  for (final permission in AppPermission.values.where(
                    (p) => p.group == group,
                  ))
                    CheckboxListTile(
                      key: ValueKey('grant-${permission.name}'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(permission.label),
                      value: profile.allows(permission),
                      onChanged:
                          profile.code == 0 ||
                              !state.allows(AppPermission.manageProfiles)
                          ? null
                          : (v) => state.setGrant(
                              profile.code,
                              permission,
                              v ?? false,
                            ),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          SettingsSection(
            title: 'Usuários',
            description: 'Diretório de demonstração. Sem AD, senha ou autenticação corporativa.',
            child: !state.allows(AppPermission.readUsers)
                ? const Text('Perfil sem permissão para consultar usuários.')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        key: const ValueKey('permission-user-search'),
                        decoration: const InputDecoration(
                          labelText: 'Usuário',
                          hintText: 'Pesquisar por nome ou matrícula',
                        ),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                      for (final result in state.search(_query))
                        ListTile(
                          key: ValueKey('directory-user-${result.id}'),
                          title: Text(result.label),
                          subtitle: const Text('Usuário simulado'),
                          selected: result.id == _userId,
                          onTap: () => setState(() => _userId = result.id),
                        ),
                      if (user != null) ...[
                        Text(
                          'Nome: ${user.name} · Matrícula: ${user.registration}',
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          key: ValueKey(
                            'user-profile-${user.id}-${user.profileCode}',
                          ),
                          initialValue: user.profileCode,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Perfil do usuário',
                          ),
                          items: [
                            for (final p in state.profiles)
                              DropdownMenuItem(
                                value: p.code,
                                child: Text(p.label),
                              ),
                          ],
                          onChanged: !state.allows(AppPermission.assignProfile)
                              ? null
                              : (v) {
                                  if (v != null) state.assign(user.id, v);
                                },
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      );
    },
  );
}
