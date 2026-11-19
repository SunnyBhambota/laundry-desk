# Laundry Desk – Android app (v0.1, testing build)

Laundry shop management by **BrotriX Technologies**. Flutter (Android first, iOS later from the same code).

## Phone par install (QR scan)
<img src="docs/install-qr.png" width="200" alt="APK download QR">

QR scan karo → latest APK download → install. Link hamesha naye build par jaata hai:
https://github.com/SunnyBhambota/laundry-desk/releases/latest/download/laundry-desk.apk

- Repo private hai, isliye phone ke Chrome mein **ek baar github.com par login** karna hoga.
- Har `main` push par GitHub Actions APK banata hai, emulator par khol kar check karta hai, phir **Releases** mein daalta hai.
  App khulte hi band ho jaye to release nahi banta.
- Pehli baar Android "unknown apps" ki permission maangega: Chrome ko allow karo.

## App kaise chalaye (pehli baar)
1. **Sign up** (neeche "Sign up"): naam, mobile, password (8+), Terms ✓. Button tab tak **bhaagta** hai jab tak sab sahi na ho.
2. **Business setup**: shop ka naam, services, branches, team, country/currency, GST, pickup/delivery.
   "Sample data" ✓ rakhoge to 3 branches, 6 staff, 18 customers, ~90 orders, expenses — sab screens bhari dikhengi.
   Baad mein More → Shop settings → **Clear sample data**.
3. **Staff login** (Login screen → "Staff login"): shop code (More → Shop settings), staff ka mobile, PIN.
   Sample staff PINs: Sunita (manager) 1111, Imran (counter) 2222, Ravi (washing) 3333, Arjun (delivery) 4444,
   Deepak (delivery) 5555, Neha (counter) 6666 — mobile 98200 11111 … 98200 66666.
4. **BrotriX admin** (sirf owner): More → Version par 7 baar tap → PIN `2468` (`AppConfig.superAdminPin`, launch se pehle badlo).
   Yahan se is shop ke modules on/off aur plan set hote hain.

## Roles
| Role | Kya dikhta hai |
|---|---|
| Owner (admin) | Sab: dashboard, sab branches, orders, staff tracking, delivery, reports, expenses, rate card, plans |
| Manager | Apni branch: dashboard, orders, staff, delivery, reports, expenses |
| Counter | Dashboard, orders, naya order, customers, payment, rate card |
| Washing & ironing | Work queue: Received → Washing → Ready |
| Delivery | My tasks: pickups, deliveries, call, map, payment collect, check-in |

## Order flow
Pickup booked → Received → Washing → Ready → Out for delivery → Delivered (ya Cancelled).
Har piece ka tag (`LD-0012 · 3/7`), rack number, express (+50%), discount, GST, advance, udhaar, WhatsApp bill/update.

## Print, export, security, tracking
- **Bill:** Order → 🖨 (80 mm thermal roll PDF, QR code ke saath) · ⋮ → A5 bill print, PDF share (WhatsApp/email), QR tags print (har piece ka tag).
- **Reports:** 🖨 report PDF · ⋮ → PDF share, orders CSV, customers CSV (Excel mein khulta hai), WhatsApp summary.
- **App lock:** More → Shop settings → Security → 4-digit PIN. App khulne par aur 30 s se zyada background ke baad PIN; 5 galat try par 30 s rukna.
  Passwords salted SHA-256; staff ka access role ke hisaab se; staff hatane par turant login band.
- **Delivery tracking:** delivery staff duty par ho to har 2 min GPS point; pickup/delivery par location "proof" order par save.
  Owner: Delivery board → agent card → aaj ka route (points + Google Maps route). Doosre phone se live dekhna cloud mode (Firebase) ke baad.

## Free vs Premium (suggested, owner approve kare)
| Module | Free | Premium |
|---|---|---|
| Orders, Customers, Bills, Basic reports | ✓ | ✓ |
| WhatsApp alerts, Staff tracking, Delivery & pickup, Barcode tags, Multi-branch, Advanced reports | – | ✓ |

Naye shop ko **14 din Premium trial**. Prices `lib/config/app_config.dart` → `planPrices`:
Pro ₹499 / ₹2,499 / ₹4,499 · Business ₹999 / ₹4,999 / ₹8,999 (Monthly / 6 months / 1 year).
Testing mein `AppConfig.enforcePremium = false` (sab khula). Launch se pehle `true`.

## Data
- **Demo mode (abhi):** account aur shop data sirf phone par (SharedPreferences, password salted SHA-256).
- **Cloud mode:** Firebase set karte hi login Firebase Auth se aur data Firestore mein (`owners`, `shops`, `shopData`, `shopCodes`).

### Firebase chalu karna (ek baar, owner)
1. console.firebase.google.com → **Add project** → naam `laundry-desk`.
2. Project → Android app add: package `com.brotrix.laundry_desk`, SHA-1:
   `8B:68:1A:EE:E8:A3:D5:38:4D:9A:88:7C:68:73:52:34:11:5F:D1:E0` (repo ki `ci/debug.keystore`).
3. **Authentication** → Sign-in method → **Email/Password** on.
4. **Firestore Database** → Create (asia-south1 Mumbai, production) → Rules mein `firestore.rules` paste → Publish.
5. Project settings se `apiKey`, `appId`, `messagingSenderId`, `projectId` Claude ko bhejo → `AppConfig` mein jayenge.

## Build
GitHub Actions (`.github/workflows/build-apk.yml`): flutter create (android) → icon → analyze → tests → APK → emulator check → Release (sirf `main`).
`dev` branch par push = sirf build check, release nahi.
