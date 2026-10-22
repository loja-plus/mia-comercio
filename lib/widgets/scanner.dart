import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Abre a câmara e devolve o primeiro código de barras lido.
Future<String?> scanBarcode(BuildContext context) {
  return Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const _ScanPage()));
}

class _ScanPage extends StatefulWidget {
  const _ScanPage();
  @override
  State<_ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<_ScanPage> {
  bool _done = false;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: MobileScanner(
        onDetect: (capture) {
          if (_done) return;
          final code = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
          if (code == null) return;
          _done = true;
          Navigator.of(context).pop(code);
        },
      ),
    );
  }
}
