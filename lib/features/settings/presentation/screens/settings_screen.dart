import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/environment.dart';
import '../../../../core/format/money.dart';
import '../../../../core/platform/file_saver.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../expenses/data/repositories/expense_repository_impl.dart';
import '../../data/account_service.dart';
import '../../domain/csv_exporter.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _exporting = false;
  bool _deleting = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.primary,
                backgroundImage:
                    user?.photoUrl != null ? NetworkImage(user!.photoUrl!) : null,
                child: user?.photoUrl == null
                    ? const Icon(Icons.person, color: Colors.white)
                    : null,
              ),
              title: Text(user?.displayNameOrEmail ?? 'Sin sesión'),
              subtitle: Text(user?.email ?? ''),
            ),
          ),
          const SizedBox(height: 24),

          _Seccion('Tus datos'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('Exportar a CSV'),
                  subtitle: const Text('Se abre con Excel o Google Sheets'),
                  trailing: _exporting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: _exporting ? null : _exportar,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          _Seccion('Cuenta'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.logout_outlined),
                  title: const Text('Cerrar sesión'),
                  onTap: _deleting
                      ? null
                      : () => ref.read(authProvider.notifier).signOut(),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_forever_outlined,
                      color: AppColors.error),
                  title: const Text('Borrar mi cuenta',
                      style: TextStyle(color: AppColors.error)),
                  subtitle: const Text('Se borran todos tus datos'),
                  trailing: _deleting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  onTap: _deleting ? null : _borrarCuenta,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          _Seccion('Información'),
          Card(
            child: Column(
              children: [
                ListTile(
                  dense: true,
                  title: const Text('Moneda'),
                  trailing: Text(
                    '${Money.currencyCode} (${Money.symbolFor(Money.currencyCode)})',
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  dense: true,
                  title: const Text('Región'),
                  trailing: Text(Environment.appLocale),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'ReceiptAI describe tus gastos, no da consejo financiero ni de '
              'inversión. Las decisiones sobre tu plata son tuyas.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Future<void> _exportar() async {
    setState(() => _exporting = true);
    try {
      final result =
          await ref.read(expenseRepositoryProvider).getAllExpenses();

      if (!mounted) return;
      await result.fold(
        (failure) async => _snack(failure.message, error: true),
        (expenses) async {
          if (expenses.isEmpty) {
            _snack('Todavía no hay gastos para exportar');
            return;
          }
          const exporter = CsvExporter();
          final ruta = await const FileSaver().save(
            fileName: exporter.fileName(DateTime.now()),
            contents: exporter.export(expenses),
          );
          if (!mounted) return;
          _snack(ruta == null
              ? '${expenses.length} gastos exportados'
              : 'Guardado en $ruta');
        },
      );
    } catch (e) {
      if (mounted) _snack('No se pudo exportar: $e', error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _borrarCuenta() async {
    // Doble confirmacion a proposito: es irreversible.
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar tu cuenta'),
        content: const Text(
          'Se borran todos tus tickets, gastos y presupuestos, y tu cuenta. '
          'No se puede deshacer.\n\n'
          'Si querés quedarte con tus datos, exportalos a CSV antes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Borrar todo'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;

    setState(() => _deleting = true);
    final service = ref.read(accountServiceProvider);
    var result = await service.deleteAccount();

    // Firebase pide sesion fresca para borrar: se reautentica y se reintenta.
    if (!mounted) return;
    final necesitaLogin = result.fold(
      (f) => f.message.contains('volvé a iniciar sesión'),
      (_) => false,
    );
    if (necesitaLogin) {
      final reauth = await service.reauthenticate();
      if (!mounted) return;
      final ok = reauth.fold((_) => false, (_) => true);
      if (ok) result = await service.deleteAccount();
    }

    if (!mounted) return;
    setState(() => _deleting = false);
    result.fold(
      (failure) => _snack(failure.message, error: true),
      // Al borrarse la cuenta cambia authState y el router manda al login solo.
      (_) => _snack('Cuenta borrada'),
    );
  }

  void _snack(String mensaje, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: error ? AppColors.error : AppColors.success,
      ),
    );
  }
}

class _Seccion extends StatelessWidget {
  final String titulo;
  const _Seccion(this.titulo);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        titulo,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: AppColors.textSecondary,
            ),
      ),
    );
  }
}
