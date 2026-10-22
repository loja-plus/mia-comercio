import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'format.dart';

/// Envio gratuito: abre o WhatsApp ou o email do próprio aparelho com a
/// mensagem já escrita. A pessoa só tem de carregar em "Enviar".
class Messaging {
  /// Abre a conversa do WhatsApp com este número e o texto preenchido.
  static Future<bool> whatsapp(String phone, String text) => launchUrl(
        Uri.parse('https://wa.me/${waNumber(phone)}?text=${Uri.encodeComponent(text)}'),
        mode: LaunchMode.externalApplication,
      );

  /// Abre o WhatsApp só com o texto: a pessoa escolhe o contacto ou a lista de difusão.
  static Future<bool> whatsappPickContact(String text) => launchUrl(
        Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'),
        mode: LaunchMode.externalApplication,
      );

  /// Abre a app de email. Vários destinatários vão em "Bcc" (não se veem uns aos outros).
  static Future<bool> email({List<String> to = const [], List<String> bcc = const [], required String subject, required String body}) {
    final params = <String>[
      'subject=${Uri.encodeComponent(subject)}',
      'body=${Uri.encodeComponent(body)}',
      if (bcc.isNotEmpty) 'bcc=${bcc.map(Uri.encodeComponent).join(',')}',
    ];
    return launchUrl(Uri.parse('mailto:${to.map(Uri.encodeComponent).join(',')}?${params.join('&')}'));
  }

  static Future<void> copy(String text) => Clipboard.setData(ClipboardData(text: text));
}
