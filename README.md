# Loja+ — app de gestão para lojas (plano gratuito)

This copy is set up for the shop **Mia Comercio** (`lib/client_config.dart`).

One app for iPad (main device), phones and computers. Portuguese and English, prices in Kwanza.
**Running cost: 0.** Everything uses free plans: Firebase Spark, GitHub Pages and GitHub Actions.

| Area | Features |
|---|---|
| Painel / Dashboard | Today's sales and estimated profit, stock value, money to receive (and overdue), money to pay in 7 days, 7-day sales chart, "needs attention" list |
| Vendas / Sales | Search or barcode scan, cash / Multicaixa / transfer / credit, stock deducted automatically, credit sales with due date **and hour**, WhatsApp receipt |
| Stock | Quantities, minimum stock, cost and price, expiry dates with colour warnings |
| Contas / Accounts | To receive, to pay, received, paid, partial payments |
| Clientes / Customers | WhatsApp number, email, credit limit, message consent |
| Lembretes / Reminders | The app tells you when to remind each customer (3 days before, on the day, 2 days after; editable). One tap opens WhatsApp or email with the message ready |
| Novidades / New arrivals | Email all customers in one tap (Bcc); WhatsApp one by one or via a WhatsApp broadcast list |
| Definições / Settings | Language, daily cash close, suggested reorder, reminder times and text, **Excel backup**, staff accounts |

**Accounts:** the first account created in the app is the **Admin**. Admin creates owners, cashiers and other admins inside the app. Owners can create cashiers. Disabling an account blocks it immediately. Forgotten passwords: reset link by email.

**Offline:** every device keeps a full copy of the data. Without internet you can sell, add products and customers and record payments. A bar shows "working offline" and how many changes are waiting. Everything syncs by itself when the network returns. The web app also opens without internet after the first visit.

---

## How it fits together

```
iPad / phones / computer  ──  web app (GitHub Pages, free)      ← built automatically by GitHub Actions
Android phones (optional) ──  .apk file (GitHub Actions, free)
            │  live sync, works offline
            ▼
   Firebase Spark (free): login + Firestore database + security rules
```

## What the free plan does NOT do (and the workaround)

| Not included | What the app does instead |
|---|---|
| Fully automatic WhatsApp/email to customers (needs a paid server + Meta fees) | Reminder list with a badge + one tap to send from your own WhatsApp/email |
| Alerts on iPad when the app is closed (browsers don't allow it) | Alerts appear on the Dashboard and Reminders whenever the app is opened. The Android .apk does give alerts with the app closed |
| Daily server backups | Data is stored by Google; plus a weekly **Excel** download from Settings |

Upgrade later is possible without losing data.

---

## Setup (no installs on your computer)

### 1. Firebase (done in the browser)
1. https://console.firebase.google.com → project **mia-comercio** (Spark plan).
2. Authentication → Sign-in method → **Email/Password: Enabled**.
3. Firestore Database → created in **europe-west1**, production mode.
4. Firestore → **Rules** tab → delete everything → paste the whole of `firestore.rules` → **Publish**.
5. Project Overview → **Add app → Web (</>)** → nickname "Mia Comercio web" → Register. Copy the `firebaseConfig` values into the `web` section of `lib/firebase_options.dart`.

### 2. GitHub (builds and publishes the app for free)
1. GitHub account: **loja-plus**.
2. New repository **mia-comercio**, **Public** (GitHub Pages is free for public repositories; the code has no business data — data lives in Firebase, protected by the rules).
3. Upload all project files (Add file → Upload files → drag the contents of this folder, including `.github`).
4. Settings → **Pages** → Source: **GitHub Actions**.
5. Actions tab → "Publicar app web" runs automatically (about 5–10 minutes). When green, the app is at `https://loja-plus.github.io/mia-comercio/`.

### 3. Allow the web address to log in
Firebase → Authentication → **Settings → Authorized domains → Add domain** → `loja-plus.github.io`.

### 4. Install on devices
* **iPad / iPhone:** open the address in **Safari** → Share button → **Add to Home Screen**. Open it from the new icon.
* **Android:** open in **Chrome** → menu ⋮ → **Add to Home screen / Install app**.
* **Computer:** open in Chrome/Edge (optional: Install icon in the address bar).

### 5. First account
Open the app → **"Primeira vez? Criar conta de administrador"** → name, email, password. Then Settings → Funcionários → add the owner (Proprietário) and cashiers (Caixa).

### 6. (Optional) Android .apk with alerts when the app is closed
1. Firebase → Project Overview → Add app → **Android**, package name `ao.lojaplus.loja_plus` → Register (skip the google-services.json and SDK steps). Copy apiKey / appId / messagingSenderId / storageBucket into the `android` section of `lib/firebase_options.dart`.
2. GitHub → Actions → **"Construir app Android"** → Run workflow.
3. When green: repository → **Releases** → download `app-release.apk` on the phone → install (allow "unknown sources").

---

## New client (another shop buying Loja+)
Each shop gets its own Firebase project (its data stays separate, and each has its own free quota) and its own GitHub repository under **loja-plus**.
1. Firebase: new project (e.g. `loja-<shop>`), steps 1.1–1.5 above.
2. Copy this project; in `lib/client_config.dart` set `shopName`; in `lib/firebase_options.dart` paste the new web keys.
3. GitHub: new public repository named after the shop (e.g. `padaria-luanda`), upload, Settings → Pages → GitHub Actions.
4. Firebase → Authentication → Authorized domains: `loja-plus.github.io` (once per Firebase project).
5. Send the client `https://loja-plus.github.io/<repository>/`. The client creates the first (admin) account — or you create it and add the client as owner.

## Updating the app
Change a file on GitHub (or upload a new version) → the web app rebuilds automatically. On devices, close and reopen the app twice to get the new version.

## Project files
```
lib/
  client_config.dart           app name (Loja+) and this client's shop name
  main.dart                    app start, theme, language, offline cache
  firebase_options.dart        Firebase keys (fill in, step 1.5)
  l10n/strings.dart            all texts in PT and EN
  models/models.dart           Product, Customer, Sale, Bill, OutMessage
  services/db.dart             database: sales, payments, message history
  services/accounts.dart       admin / owner / cashier accounts (no server)
  services/messaging.dart      opens WhatsApp / email with the message ready
  services/export.dart         Excel backup
  services/notifications*.dart device alerts (Android) / none on web
  state/app_state.dart         live data, dashboard numbers, reminder schedule
  screens/                     one file per screen
web/                           web app page, icons, offline support (mia_sw.js)
firestore.rules                who can see and change what (paste into Firebase)
.github/workflows/             automatic build: web.yml (web app), android.yml (.apk)
tools/patch_android.py         Android settings used by android.yml
```
