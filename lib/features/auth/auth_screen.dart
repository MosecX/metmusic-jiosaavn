import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/account_service.dart';
import '../../core/theme/app_theme.dart';
import '../shared/player_shell.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _identifierController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isRegister = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && context.read<AccountService>().isApproved) {
        Navigator.pop(context, true);
      }
    });
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final account = context.read<AccountService>();
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    bool ok;
    if (_isRegister) {
      ok = await account.register(
        username: _identifierController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } else {
      ok = await account.login(
        identifier: _identifierController.text.trim(),
        password: _passwordController.text,
      );
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = account.error;
    });
    if (ok) {
      await account.loadFavorites();
      if (mounted) Navigator.pop(context, true);
    }
  }

  Future<void> _logout() async {
    await context.read<AccountService>().logout();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final account = context.watch<AccountService>();
    final blocked = account.isLoggedIn && !account.isApproved;

    return PlayerShell(
      child: Scaffold(
        backgroundColor: AppTheme.pageBackground,
        body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(Icons.music_note, color: cs.onPrimary, size: 40),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'MetMusic',
                    textAlign: TextAlign.center,
                    style: text.displayMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isRegister
                        ? 'Crea tu cuenta para desbloquear la música'
                        : 'Inicia sesión para reproducir en calidad Hi-Fi',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 28),

                  if (blocked) ...[
                    _buildStatusNotice(account),
                    const SizedBox(height: 20),
                    OutlinedButton(
                      onPressed: _logout,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: BorderSide(color: Colors.red.withValues(alpha: 0.5)),
                      ),
                      child: const Text('Cerrar sesión'),
                    ),
                  ] else ...[
                    _buildTabToggle(),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _identifierController,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Usuario o email',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (_isRegister) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _emailController,
                        textInputAction: TextInputAction.next,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: Icon(Icons.lock_outline),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        _error!,
                        style: TextStyle(color: cs.error, fontSize: 13),
                      ),
                    ],
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cs.primary,
                        foregroundColor: cs.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _loading
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: cs.onPrimary,
                                strokeWidth: 2.5,
                              ),
                            )
                          : Text(
                              _isRegister ? 'Crear cuenta' : 'Iniciar sesión',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _isRegister
                          ? 'Tu cuenta queda pendiente de aprobación por un administrador.'
                          : 'Solo usuarios aprobados pueden reproducir.',
                      textAlign: TextAlign.center,
                      style: text.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildStatusNotice(AccountService account) {
    final cs = Theme.of(context).colorScheme;
    final isPending = account.isPending;
    final color = isPending ? Colors.amber : Colors.redAccent;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(isPending ? Icons.hourglass_top : Icons.block, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isPending
                  ? 'Tu cuenta está pendiente de aprobación. Espera a que un administrador la active.'
                  : 'Tu cuenta fue rechazada. Contacta al administrador.',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabToggle() {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _tabButton('Iniciar sesión', !_isRegister),
          ),
          Expanded(
            child: _tabButton('Registrarse', _isRegister),
          ),
        ],
      ),
    );
  }

  Widget _tabButton(String label, bool active) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() {
        _isRegister = label == 'Registrarse';
        _error = null;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? cs.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: active ? cs.onPrimary : cs.onSurfaceVariant,
            fontWeight: active ? FontWeight.bold : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
