// Alertas no aparelho: versão nativa (Android/iOS) ou versão web (iPad pelo browser).
export 'notifications_native.dart' if (dart.library.js_interop) 'notifications_web.dart';
