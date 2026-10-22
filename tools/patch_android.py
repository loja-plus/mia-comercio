"""Ajusta o projeto Android gerado pelo `flutter create` (usado pelo GitHub Actions).
- minSdk 23 (exigido pelo Firebase)
- desugaring (exigido pelos alertas agendados)
- permissões: notificações, alarmes exatos, câmara
- recetores para os alertas voltarem depois de reiniciar o telemóvel
"""
import pathlib
import re

app = pathlib.Path("android/app")
gradle = app / "build.gradle.kts"
if gradle.exists():
    g = gradle.read_text()
    g = re.sub(r"minSdk\s*=\s*[^\n]+", "minSdk = 23", g)
    if "isCoreLibraryDesugaringEnabled" not in g:
        g = g.replace("compileOptions {", "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", 1)
    if "desugar_jdk_libs" not in g:
        g += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    gradle.write_text(g)
else:
    gradle = app / "build.gradle"
    g = gradle.read_text()
    g = re.sub(r"minSdk(Version)?\s*=?\s*[^\n]+", "minSdkVersion 23", g, count=1)
    if "coreLibraryDesugaringEnabled" not in g:
        g = g.replace("compileOptions {", "compileOptions {\n        coreLibraryDesugaringEnabled true", 1)
    if "desugar_jdk_libs" not in g:
        g += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
    gradle.write_text(g)

manifest = app / "src/main/AndroidManifest.xml"
m = manifest.read_text()
perms = """    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.CAMERA"/>
"""
if "POST_NOTIFICATIONS" not in m:
    m = re.sub(r"(<manifest[^>]*>\n)", r"\1" + perms, m, count=1)
receivers = """        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
            </intent-filter>
        </receiver>
"""
if "ScheduledNotificationReceiver" not in m:
    m = m.replace("</application>", receivers + "    </application>", 1)
m = m.replace('android:label="loja_plus"', 'android:label="Loja+"')
# WhatsApp / email: permitir abrir estes links (Android 11+)
queries = """    <queries>
        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent>
        <intent><action android:name="android.intent.action.SENDTO"/><data android:scheme="mailto"/></intent>
    </queries>
"""
if "android:scheme=\"mailto\"" not in m:
    m = m.replace("</manifest>", queries + "</manifest>", 1)
manifest.write_text(m)
print("Android ajustado.")
