{{flutter_js}}
{{flutter_build_config}}

// Sem o service worker do Flutter: usamos o nosso (mia_sw.js), que guarda
// também as letras e o motor gráfico para a app abrir sem internet.
_flutter.loader.load();
