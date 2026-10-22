import 'package:intl/intl.dart';

String _loc(String lang) => lang == 'pt' ? 'pt_PT' : 'en_GB';

/// 125000 -> "125 000 Kz"
String kz(num v) => '${NumberFormat.decimalPattern('pt_PT').format(v.round())} Kz';

String fmtDate(DateTime d, String lang) => DateFormat('d MMM yyyy', _loc(lang)).format(d);
String fmtDateTime(DateTime d, String lang) => DateFormat('d MMM · HH:mm', _loc(lang)).format(d);
String fmtTime(DateTime d) => DateFormat('HH:mm').format(d);
String fmtWeekday(DateTime d, String lang) => DateFormat.E(_loc(lang)).format(d);

int daysFromToday(DateTime d) {
  final n = DateTime.now();
  return DateTime(d.year, d.month, d.day).difference(DateTime(n.year, n.month, n.day)).inDays;
}

DateTime startOfDay([DateTime? d]) {
  final x = d ?? DateTime.now();
  return DateTime(x.year, x.month, x.day);
}

/// Remove espaços e sinais; devolve o número em formato internacional para wa.me
String waNumber(String phone) {
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length == 9) return '244$digits'; // número angolano sem indicativo
  return digits;
}
