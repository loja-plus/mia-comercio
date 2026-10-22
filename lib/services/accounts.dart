import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Contas de utilizador — sem servidor pago (plano gratuito Spark).
///
/// Funções:  admin > owner (proprietário) > cashier (caixa)
///  - admin: tudo, e gere TODAS as contas.
///  - owner: todos os dados da loja, mas só gere contas de caixa.
///  - cashier: vende; não gere contas.
///
/// Como funciona sem servidor:
///  - A conta nova é criada numa "segunda ligação" ao Firebase, para que quem
///    está a criar (admin/proprietário) continue com a sua sessão.
///  - O perfil (nome, função, ativo) fica em users/{uid}. As regras de segurança
///    (firestore.rules) é que garantem quem pode criar/alterar o quê.
///  - Desativar = active:false. As regras bloqueiam todos os dados dessa conta
///    e a app termina a sessão.
///  - Palavra-passe esquecida: o Firebase envia um email para a pessoa criar uma nova.
/// Estas ações precisam de internet.
class Accounts {
  Accounts._();
  static final Accounts I = Accounts._();

  final _fs = FirebaseFirestore.instance;
  DocumentReference<Map<String, dynamic>> get _setup => _fs.collection('config').doc('setup');

  static bool canManage(String callerRole, String targetRole) =>
      callerRole == 'admin' || (callerRole == 'owner' && targetRole == 'cashier');

  /// Já existe administrador? (decide se o botão de primeira configuração aparece)
  Future<bool> adminExists() async {
    final d = await _setup.get(const GetOptions(source: Source.server));
    return d.exists && d.data()?['adminCreated'] == true;
  }

  /// Segunda ligação ao Firebase, usada para criar contas sem mexer na sessão principal.
  Future<FirebaseApp> _secondApp() async => Firebase.apps.any((a) => a.name == 'accountCreator')
      ? Firebase.app('accountCreator')
      : await Firebase.initializeApp(name: 'accountCreator', options: Firebase.app().options);

  /// Primeira conta da app: o administrador. Só funciona uma vez (garantido pelas regras).
  /// Tudo é feito na segunda ligação; depois o ecrã de entrada faz o login normal.
  Future<void> setupAdmin({required String name, required String email, required String password}) async {
    _check(name, email, password);
    final app2 = await _secondApp();
    final auth2 = FirebaseAuth.instanceFor(app: app2);
    UserCredential cred;
    try {
      cred = await auth2.createUserWithEmailAndPassword(email: email.trim(), password: password);
    } on FirebaseAuthException catch (e) {
      // Se uma tentativa anterior criou a conta mas falhou a seguir, entra e continua.
      if (e.code != 'email-already-in-use') rethrow;
      cred = await auth2.signInWithEmailAndPassword(email: email.trim(), password: password);
    }
    final uid = cred.user!.uid;
    final fs2 = FirebaseFirestore.instanceFor(app: app2);
    final batch = fs2.batch();
    batch.set(fs2.collection('config').doc('setup'), {'adminCreated': true, 'uid': uid, 'at': FieldValue.serverTimestamp()});
    batch.set(fs2.collection('users').doc(uid), _profile(name, email, 'admin'));
    try {
      await batch.commit();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') throw AccountError('errOwnerExists');
      rethrow;
    } finally {
      await auth2.signOut();
    }
  }

  /// Admin cria qualquer conta; proprietário cria só caixas.
  Future<void> createStaff({
    required String name,
    required String email,
    required String password,
    required String role,
  }) async {
    _check(name, email, password);
    final auth2 = FirebaseAuth.instanceFor(app: await _secondApp());
    final cred = await auth2.createUserWithEmailAndPassword(email: email.trim(), password: password);
    final uid = cred.user!.uid;
    await auth2.signOut();
    // O perfil é escrito por quem está a criar (admin/proprietário) — as regras verificam a permissão.
    await _fs.collection('users').doc(uid).set(_profile(name, email, role));
  }

  Future<void> setActive(String uid, bool active) => _fs.collection('users').doc(uid).update({'active': active});

  Future<void> setRole(String uid, String role) => _fs.collection('users').doc(uid).update({'role': role});

  /// Envia à pessoa um email com um link para criar uma nova palavra-passe.
  Future<void> sendPasswordReset(String email) => FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());

  Stream<List<StaffMember>> staff() => _fs
      .collection('users')
      .snapshots()
      .map((s) => s.docs.map(StaffMember.fromDoc).toList()..sort((a, b) => a.name.compareTo(b.name)));

  Map<String, dynamic> _profile(String name, String email, String role) => {
        'name': name.trim(),
        'email': email.trim().toLowerCase(),
        'role': role,
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
      };

  void _check(String name, String email, String password) {
    if (name.trim().isEmpty) throw AccountError('errName');
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim())) throw AccountError('errEmail');
    if (password.length < 6) throw AccountError('errPassword');
  }
}

class AccountError implements Exception {
  AccountError(this.key);
  final String key;
}

class StaffMember {
  StaffMember({required this.uid, required this.name, required this.email, required this.role, required this.active});
  final String uid, name, email, role;
  final bool active;

  static bool canManage(String callerRole, String targetRole) => Accounts.canManage(callerRole, targetRole);

  factory StaffMember.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return StaffMember(
      uid: d.id,
      name: m['name'] ?? '',
      email: m['email'] ?? '',
      role: m['role'] ?? 'cashier',
      active: m['active'] ?? true,
    );
  }
}

/// Converte um erro numa chave de texto da app (lib/l10n/strings.dart).
String accountErrorKey(Object e) {
  if (e is AccountError) return e.key;
  if (e is FirebaseAuthException) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'errEmailExists';
      case 'weak-password':
        return 'errPassword';
      case 'invalid-email':
        return 'errEmail';
      case 'network-request-failed':
        return 'errNeedInternet';
      case 'user-not-found':
      case 'invalid-credential':
        return 'loginError';
    }
  }
  if (e is FirebaseException) {
    if (e.code == 'permission-denied') return 'errNotAllowed';
    if (e.code == 'unavailable') return 'errNeedInternet';
  }
  return 'errGeneric';
}
