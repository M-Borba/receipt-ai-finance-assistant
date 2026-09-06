import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../../data/repositories/group_repository.dart';

/// Pantalla a la que lleva el link de invitación.
///
/// No entra sola: muestra a qué grupo la están invitando y espera que la
/// persona toque el botón. Sumar a alguien a un grupo por abrir un link, sin
/// que lo confirme, es lo mismo que no preguntarle.
class JoinGroupScreen extends ConsumerStatefulWidget {
  const JoinGroupScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends ConsumerState<JoinGroupScreen> {
  String? _nombre;
  String? _error;
  bool _cargando = true;
  bool _entrando = false;

  @override
  void initState() {
    super.initState();
    _mirar();
  }

  Future<void> _mirar() async {
    final res =
        await ref.read(groupRepositoryProvider).peekInvite(widget.token);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      res.fold((f) => _error = f.message, (inv) => _nombre = inv.groupName);
    });
  }

  Future<void> _entrar() async {
    setState(() {
      _entrando = true;
      _error = null;
    });
    final res =
        await ref.read(groupRepositoryProvider).joinWithToken(widget.token);
    if (!mounted) return;
    res.fold(
      (f) => setState(() {
        _entrando = false;
        _error = f.message;
      }),
      (groupId) => context.go('/groups/$groupId'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invitación')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: _cargando
              ? const LoadingIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _error != null ? Icons.link_off : Icons.group_add,
                      size: 56,
                      color: _error != null
                          ? AppColors.textMuted
                          : AppColors.primary,
                    ),
                    const SizedBox(height: 20),
                    if (_error != null) ...[
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16, height: 1.4),
                      ),
                      const SizedBox(height: 24),
                      TextButton(
                        onPressed: () => context.go('/groups'),
                        child: const Text('Ir a mis grupos'),
                      ),
                    ] else ...[
                      Text(
                        'Te invitaron a',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 14),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _nombre ?? 'un grupo',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Vas a poder ver los gastos del grupo y cuánto debe '
                        'cada uno.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: AppColors.textMuted, height: 1.4),
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _entrando ? null : _entrar,
                          child: _entrando
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Text('Entrar al grupo'),
                        ),
                      ),
                      TextButton(
                        onPressed: () => context.go('/groups'),
                        child: const Text('Ahora no'),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}
