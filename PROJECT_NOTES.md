# Laundry Desk – Project notes (Claude ke liye handoff)

## Owner ki zaroori baatein
- Baat Hinglish mein, English letters mein.
- Mobile app (Flutter), pehle Android, phir iOS. Web app nahi.
- India + international: multi-currency, English default + Hindi.
- Har version pehle live preview (Claude Design canvas), owner OK kare tab code.
- Owner kuch install nahi karega. Code GitHub par (`SunnyBhambota/laundry-desk`, private), APK GitHub Actions se, QR README mein.
- **Payday Budget Book (`SunnyBhambota/payday-budget-book`) bilkul alag app hai** — uski repo mein Laundry ka kuch nahi jaana chahiye, aur ulta bhi.
- Version-wise: v0.1, v0.2 …  Budget kam: free tools pehle (Firebase free, GitHub free, owner ki Hostinger hosting).
- Company: BrotriX Technologies ("Designed by BrotriX Technologies" login par). Play Store BrotriX org account se.
- Business model: owner (BrotriX) ye app laundry shop owners ko bechega. Free + Premium modules, subscription (Monthly / 6 Months / 1 Year).
  BrotriX modules tick karke on/off karega.

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
- Plans & modules + BrotriX admin (version 7 tap, PIN 2468). Sample data (ids `demo_`), clear.
- Print/export: `services/export_service.dart` (pdf + printing + share_plus): roll80 bill, A5 bill, QR tags A4, report PDF, CSV.
- Security: owner app-lock PIN (`AppState.lockHash`, lock after 30 s background), roles, PIN for staff.
- Tracking: `services/tracking_service.dart` (geolocator) — delivery staff GPS every 2 min on duty + proof at handover; `ShopData.pings`; board trail sheet + Maps route.
- Data: `lib/data/shop_data.dart` (JSON in SharedPreferences per owner; Firestore `shopData/{uid}` in cloud mode).

## NEXT (v0.2 ideas)
- Firebase project banana (owner) → cloud login, staff doosre phone se login (abhi staff login usi phone par jahan shop data hai).
- Phone OTP login, password reset.
- Bill PDF + thermal printer, barcode/QR tags print, garment photo at intake.
- Customer app / web booking link, live GPS of delivery staff, route order, proof of delivery photo.
- WhatsApp Business API auto-messages (abhi wa.me links), loyalty/coupons, customer price lists (VIP/business).
- Play billing for plans, `enforcePremium = true`, release signing key, privacy policy.
