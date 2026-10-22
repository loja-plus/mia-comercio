import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../client_config.dart';
import '../services/accounts.dart';
import '../state/app_state.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _showSetup = false;

  @override
  void initState() {
    super.initState();
    // Mostra o botão de primeira configuração só se ainda não houver administrador.
    Accounts.I.adminExists().then((v) {
      if (mounted) setState(() => _showSetup = !v);
    }).catchError((_) {});
  }

  Future<void> _setupOwner() async {
    final s = context.read<AppState>().s;
    final name = TextEditingController(), email = TextEditingController(), pass = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(s.t('createOwner')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: InputDecoration(labelText: s.t('name'))),
          const SizedBox(height: 10),
          TextField(
              controller: email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: s.t('email'))),
          const SizedBox(height: 10),
          TextField(
              controller: pass,
              obscureText: true,
              decoration: InputDecoration(labelText: s.t('password'), helperText: s.t('pwHint'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(s.t('save'))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Accounts.I.setupAdmin(name: name.text.trim(), email: email.text.trim(), password: pass.text);
      _email.text = email.text.trim();
      _pass.text = pass.text;
      await _signIn();
      if (mounted) setState(() => _showSetup = false);
    } catch (e) {
      if (mounted) setState(() => _error = s.t(accountErrorKey(e)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final s = context.read<AppState>().s;
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = s.t('typeEmailFirst'));
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) setState(() => _error = s.t('resetSent'));
    } catch (e) {
      if (mounted) setState(() => _error = s.t(accountErrorKey(e)));
    }
  }

  Future<void> _signIn() async {
    final s = context.read<AppState>().s;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: _email.text.trim(), password: _pass.text);
    } on FirebaseAuthException {
      setState(() => _error = s.t('loginError'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.s;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(ClientConfig.shopName,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(ClientConfig.appName,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 32),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: InputDecoration(labelText: s.t('email')),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pass,
                  obscureText: true,
                  onSubmitted: (_) => _signIn(),
                  decoration: InputDecoration(labelText: s.t('password')),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                const SizedBox(height: 20),
                FilledButton(onPressed: _busy ? null : _signIn, child: Text(s.t('signIn'))),
                TextButton(onPressed: _busy ? null : _forgot, child: Text(s.t('forgotPassword'))),
                if (_showSetup)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextButton(onPressed: _busy ? null : _setupOwner, child: Text(s.t('firstSetup'))),
                  ),
                const SizedBox(height: 16),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'pt', label: Text('Português')),
                    ButtonSegment(value: 'en', label: Text('English')),
                  ],
                  selected: {app.lang},
                  onSelectionChanged: (v) => app.setLang(v.first),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
