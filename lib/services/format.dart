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

/// 3 → "3"; 2.5 → "2,5"; com unidade 'kg' → "18,4 kg".
String fmtQty(double q, [String unit = 'un']) {
  final txt = NumberFormat('#,##0.###', 'pt_PT').format(q);
  return unit == 'kg' ? '$txt kg' : txt;
}

/// Lê números escritos com vírgula ou ponto ("18,4" ou "18.4").
double? parseNum(String s) {
  final t = s.replaceAll(RegExp(r'[\s\u00A0\u202F]'), '').replaceAll(',', '.');
  return double.tryParse(t);
}

/// Número para pôr num campo de texto (sem separador de milhares): 1500 → "1500", 2.5 → "2,5".
String plainNum(double q) => q == q.roundToDouble() ? q.toInt().toString() : q.toString().replaceAll('.', ',');
