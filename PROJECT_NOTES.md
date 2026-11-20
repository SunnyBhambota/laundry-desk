# Laundry Desk – Project notes (Claude ke liye handoff)

## Owner ki zaroori baatein
- (20 Nov 23:57) App mein KAHIN BHI 'BrotriX' naam nahi. Credit: 'Designed by SUNNY BHAMBOTA' (AppConfig.designer). Package id com.brotrix.laundry andar ka hai (Firebase se juda) – user ko nahi dikhta, mat badlo.
- Git rule (20 Nov raat): push se pehle repo visibility check karo (`gh api repos/SunnyBhambota/laundry-desk -q .visibility`). PUBLIC = seedha push karte raho. PRIVATE = owner se poochho, permission ke baad hi push.
- HAR release ke saath install QR file (laundry-desk-install-qr.png / docs/install-qr.png) SendUserFile se bhejna – owner ka rule.
- App naam ab LaundryCase (logo owner ka, 20 Nov). Package id com.brotrix.laundry same.
- Baat Hinglish mein, English letters mein.
- Mobile app (Flutter), pehle Android, phir iOS. Web app nahi.
- India + international: multi-currency, English default + Hindi.
- Har version pehle live preview (Claude Design canvas), owner OK kare tab code.
- Owner kuch install nahi karega. Code GitHub par (`SunnyBhambota/laundry-desk`, private), APK GitHub Actions se, QR README mein.
- **Payday Budget Book (`SunnyBhambota/payday-budget-book`) bilkul alag app hai** — uski repo mein Laundry ka kuch nahi jaana chahiye, aur ulta bhi.
- Version-wise: v0.1, v0.2 …  Budget kam: free tools pehle (Firebase free, GitHub free, owner ki Hostinger hosting).
- Credit: "Designed by SUNNY BHAMBOTA" (login + PDFs). No company name anywhere.
- Business model: owner (owner (Sunny)) ye app laundry shop owners ko bechega. Free + Premium modules, subscription (Monthly / 6 Months / 1 Year).
  owner (Sunny) modules tick karke on/off karega.

## Design (canvas: "Laundry Desk v0.1 – Logo, Colours, Sign up & Admin Dashboard")
- Logo A "Drum Door" (abhi use ho raha; owner ne final nahi bola). Colours: Primary #1F5FD1, Navy #0F2340, Aqua #3CC6D8, Sun #FFC845, Mist #F4F8FC.
- Login = "Glossy + Runaway Login" (owner ne approve kiya, 18 Nov): pastel pink/blue gloss, upar animated laundry shop scene
  (rassi par kapde, washing machine, lady dry-clean machine mein kapde daalti, table par kapde + press), "Welcome" ka o = drum,
  Log in button tab tak bhaagta hai jab tak fields sahi na hon. Code: `lib/screens/auth_screen.dart`, `lib/widgets/laundry_scene.dart`.

## v0.1 (19 Nov 2026) – kya bana
- Auth: owner sign up/login (demo mode local; Firebase-ready), staff login (shop code + mobile + PIN), business setup (step 2).
- Roles: owner, manager, counter, washer, delivery — har ek ka alag tab bar (`screens/shell.dart`).
- Orders: naya order (customer search/add, service → garment grid, qty, note, express, pickup, home delivery, due, discount, advance),
  list + filters + search, detail (timeline, payments, tags, rack, agent assign, WhatsApp bill/update, call/map, cancel).
- Customers: list, udhaar filter, detail, WhatsApp reminder. Rate card (item × service, edit, add item).
- Staff: team, attendance (7 din), performance (booked/updates/deliveries/collected/days), add staff + PIN, check in/out.
- Delivery board + delivery person "My tasks" + washer "Work queue".
- Reports (today/7d/month/all, branch filter): collection, sales, orders, avg, expenses, profit, dues, by mode, daily bars,
  service mix, top customers, branches, expenses by type, WhatsApp summary. Expenses, Branches, Settings (GST, express %, due days, shop code).
- Plans & modules + app admin (version 7 tap, PIN 2468). Sample data (ids `demo_`), clear.
- Print/export: `services/export_service.dart` (pdf + printing + share_plus): roll80 bill, A5 bill, QR tags A4, report PDF, CSV.
- Security: owner app-lock PIN (`AppState.lockHash`, lock after 30 s background), roles, PIN for staff.
- Tracking: `services/tracking_service.dart` (geolocator) — delivery staff GPS every 2 min on duty + proof at handover; `ShopData.pings`; board trail sheet + Maps route.
- Data: `lib/data/shop_data.dart` (JSON in SharedPreferences per owner; Firestore `shopData/{uid}` in cloud mode).

## v0.2 (19 Nov 2026)
- Firebase project `laundry-desk-4308f`, Android app `com.brotrix.laundry` (SHA-1 = ci/debug.keystore). Owner ne Auth (Email/Password + Anonymous), Firestore (Mumbai) aur rules publish kar diye.
- `data/cloud_sync.dart`: per-record docs + snapshot listeners + canonical JSON diff (no write loops). Staff phones `admin=false`.
- Staff login cloud: anonymous → `members/{uid}` {ownerUid, code, phone10, key=sha256(CODE:phone10:pin)}; rules compare with `staffKeys/{code}.keys`.
- Issues: `data/issue_models.dart`, `screens/issue_screens.dart` (complaint stages, wrong-delivery tasks, re-open, reports, CSV).
- Payroll: `logic/payroll.dart` (rules in `ShopData.rules`), `screens/payroll_screens.dart` (leaderboard, payslip, payouts, rules, my earnings, PDF slip, CSV).
- Logo: owner ka design (assets/images/logo_mark.png), admin PIN 0000, free limits in AppConfig.

## v0.3 + v0.4 (19 Nov 2026) – done
- v0.3: `screens/v03_screens.dart` (edit order, refund, scan, printer, UPI, backup), VIP/business rates, ESC/POS.
- v0.4: `screens/v04_screens.dart` – OffersScreen (loyalty settings, coupons, package plans), CustomerExtrasCard (points, packages, sell package, save pin), StockScreen (items, in/out, suppliers, purchase → expense), RouteMapScreen (flutter_map + OSM, nearest-first stops, Google Maps directions).
- New order: coupon / points / package use, pickup slots. Bill PDF / thermal / WhatsApp show offers.
- Tracking: geolocator foreground-service stream (notification) + 2-min timer, ≥90 s gap; proof at handover also pins the customer location if missing.
- Google login: `AuthService.signInWithGoogle` (serverClientId = AppConfig.googleWebClientId); Google owners give mobile in Business setup. Needs Google provider ON in Firebase Auth.
- Modules: `loyalty`, `stock` added (premium).

## v0.5 (20 Nov 2026)
- Owner: "login dobara nahi ho raha". Fixes: V.local() (+91/0 prefix), email login via `shopCodes/mail_<sha>` → {login}, Google owners add password (setup + Settings), `ShopData.flush()` before signOut, CloudSync.lastError shown in More.
- `integration_test/app_test.dart` + `test_driver/` + `ci/e2e.sh`: CI job `e2e` (emulator, real Firebase) must pass before publish. `ci/prepare_android.sh` shared by jobs. Test account deleted at the end.
- Multi-branch: `widgets/branch_switch.dart`, BranchCompareCard/BranchRow + DayCloseScreen + OverdueScreen (reports_screen.dart), ExportService.branchCsv, branch sheet (admin_screens), staff edit (staff_screen), order move, `ShopData.agentsFor`.
- BookingQrScreen (v04_screens) + ExportService.bookingPosterPdf/bookingLink.
- Owner rule (20 Nov): paid things (Play Store, iOS, WhatsApp API, OTP) STOP. Never wait for "allow" – everything is allowed.

## v0.6 – done (local, push pending owner OK)
- `services/bio_service.dart` (local_auth), AppState.bioOn/setBio/unlockWithBio, LockScreen fingerprint button, Settings switch. CI: MainActivity → FlutterFragmentActivity, AppCompat theme + appcompat dep, USE_BIOMETRIC.
- `screens/live_map_screen.dart`: LiveMapScreen (flutter_map + OSRM route + Nominatim geocode fallback, GPS stream for delivery role, last ping for others). Used by order detail / delivery TaskCard / customer page.
- `ShopData.clearSample()` returns count, keeps own records (moves them to a real branch); `deleteSampleFlow` in dashboard_screen.dart; e2e checks cloud after delete.

## Owner ko bataya hua pending (order mein)
v0.3: order edit/refund/customer delete, QR scan, Bluetooth printer, UPI QR on bill, VIP/business rates, backup/restore file, Hindi gaps.
v0.4: loyalty/coupons/packages, background tracking, pickup slots + route + map, inventory/suppliers, Google login (OTP/reset need Blaze).
Owner decisions: WhatsApp API, Super Admin web panel (Hostinger), Play Store, customer app, iOS.

## Old ideas list (v0.2 time, mostly done now)
- Firebase project banana (owner) → cloud login, staff doosre phone se login (abhi staff login usi phone par jahan shop data hai).
- Phone OTP login, password reset.
- Bill PDF + thermal printer, barcode/QR tags print, garment photo at intake.
- Customer app / web booking link, live GPS of delivery staff, route order, proof of delivery photo.
- WhatsApp Business API auto-messages (abhi wa.me links), loyalty/coupons, customer price lists (VIP/business).
- Play billing for plans, `enforcePremium = true`, release signing key, privacy policy.
