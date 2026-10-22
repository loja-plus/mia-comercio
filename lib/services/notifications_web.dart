import '../l10n/strings.dart';
import '../models/models.dart';
import '../state/app_state.dart' show ReminderItem;

/// Versão web (iPad/telemóvel pelo browser): o browser não permite alertas
/// agendados com a app fechada. Os mesmos avisos aparecem no Painel e em
/// Lembretes sempre que a app é aberta.
class Notifier {
  Notifier._();
  static final Notifier I = Notifier._();

  Future<void> init() async {}

  Future<void> rescheduleAll({
    required List<Product> products,
    required List<Bill> bills,
    required List<ReminderItem> reminders,
    required S s,
  }) async {}
}
