# ENGINE ROWING - مخطط قاعدة البيانات المحلية الفعلية (SQLite)
## تقرير التدقيق الفعلي المستخرج من فحص SQLite الحي
**تاريخ الاستخراج:** نوفمبر 2026  
**طريقة الاستخراج:** اختبار برمجي مستقل (`test/extract_schema_helper_test.dart`) يفحص `sqlite_master` و `PRAGMA table_info` و `PRAGMA index_list` و `PRAGMA foreign_key_list`.  
**إصدار المخطط:** الإصدار 10 (v10) عبر مسار الإنشاء الجديد (`onCreate`) ومسار الترقية المتسلسلة من الإصدارات السابقة.

---

## 1. الملخص الإحصائي المعتمد
- **إجمالي عدد الجداول الفعلية:** **27 جدولاً** (تم تصحيح الرقم السابق البالغ 23).
- **عدد جداول المزامنة الثنائية (Local-First Synced Tables):** **20 جدولاً** (تم تصحيح الرقم السابق البالغ 19).
- **عدد جداول النظام والمحرك المحلي غير المتزامنة:** **7 جداول** (`users`, `cycles`, `daily_load`, `sync_state`, `sync_tombstones`, `sync_flag`, `sqlite_sequence`).
- **عدد التريجرات التلقائية (Triggers):** **60 تريجر** (3 تريجرات لكل جدول متزامن: `trg_insert_*`, `trg_update_*`, `trg_delete_*`).
- **قيود المفاتيح الأجنبية المحلية (Foreign Keys):** **صفر (0)** قيود مفروضة بواسطة SQLite (العلاقات منطقية فقط في منطق التطبيق بدون قيود `REFERENCES` تمنع الحذف أو تُحدث Cascade محلياً).

---

## 2. فهرس الجداول الـ 27 وتصنيفها الوظيفي

| # | اسم الجدول | الفئة | متزامن مع السحابة؟ | نوع المفتاح الأساسي | وظيفة الجدول |
|---|---|---|---|---|---|
| 1 | `players` | بيانات رياضية | نعم (1) | `id` (INTEGER PK AUTO) | سجلات اللاعبين، MHR، حالة التفعيل |
| 2 | `sessions` | خطط وتمارين | نعم (2) | `(date, idx)` مركّب | الحصص اليومية الأساسية للمدرب |
| 3 | `notes` | ملاحظات تدريبية | نعم (3) | `date` (TEXT PK) | الملاحظات العامة والفنية لليوم |
| 4 | `program_cycles` | البرامج والدورات | نعم (4) | `id` (INTEGER PK AUTO) | الدورات التدريبية المجدولة |
| 5 | `program_cycle_tests` | اختبارات البرامج | نعم (5) | `(cycle_id, test_type)` مركّب | اختبارات نهاية الدورة (2k, 6k, etc.) |
| 6 | `program_day_config` | إعدادات البرنامج | نعم (6) | `(cycle_id, cycle_type, day_of_week)` مركّب | توقيت ومكان وتفاصيل يوم الدورة |
| 7 | `program_sessions` | حصص البرامج | نعم (7) | `id` (INTEGER PK AUTO) | الحصص المنظمة داخل دورة البرنامج |
| 8 | `program_workout_items` | بنود التمارين | نعم (8) | `id` (INTEGER PK AUTO) | أجزاء الحصة (إحماء، رئيسي، تهدئة) |
| 9 | `cycle_templates` | قوالب الدورات | نعم (9) | `id` (INTEGER PK AUTO) | قوالب جاهزة للدورات التدريبية |
| 10 | `logs` | سجلات الأداء | نعم (10) | `(player_id, date, idx)` مركّب | البيانات الفسيولوجية والتنفيذية للتمرين |
| 11 | `athlete_custom_sessions` | تخصيص التمارين | نعم (11) | `id` (INTEGER PK AUTO) | حصص مخصصة من المدرب للاعب معين |
| 12 | `athlete_custom_workout_items` | بنود التخصيص | نعم (12) | `id` (INTEGER PK AUTO) | أجزاء التمارين المخصصة للاعب |
| 13 | `cp_tests` | فسيولوجيا CP | نعم (13) | `id` (INTEGER PK AUTO) | نتائج اختبارات القدرة الحرجة |
| 14 | `cp_values` | فسيولوجيا CP | نعم (14) | `(player_id, date)` مركّب | قيم CP و W' المعتمدة تاريخياً |
| 15 | `testing_dates` | مواعيد الاختبارات | نعم (15) | `id` (INTEGER PK AUTO) | مواعيد الاختبارات الرسمية للمدرب |
| 16 | `testing_date_recipients` | مستلمو الاختبارات | نعم (16) | `(testing_date_id, athlete_id)` مركّب | دعوات وحالات استلام مواعيد الاختبار |
| 17 | `coach_messages` | تواصل ومراسلة | نعم (17) | `id` (INTEGER PK AUTO) | رسائل المدرب للاعبين والمجموعات |
| 18 | `progress_baseline_config` | إعدادات التحليل | نعم (18) | `key` (TEXT PK) | معايير خط الأساس والتقارب |
| 19 | `matrix_zone_config` | إعدادات التحليل | نعم (19) | `key` (TEXT PK) | أوزان واتجاهات مؤشرات Matrix Zone |
| 20 | `coach_requests` | إدارة المدرب | نعم (20) | `id` (INTEGER PK AUTO) | طلبات انضمام اللاعبين للمدرب |
| 21 | `cycles` | إرث قديم (Legacy) | لا | `id` (INTEGER PK AUTO) | جدول الدورات القديم غير المستخدم |
| 22 | `users` | حسابات وأمان | لا (محلي فقط) | `id` (INTEGER PK AUTO) | بيانات تسجيل الدخول المحلية والتشفير |
| 23 | `daily_load` | كاش تحليلي | لا (مشتق) | `(player_id, date)` مركّب | كاش تراكمي لحسابات PMC (TSS, CTL, ATL, TSB) |
| 24 | `sync_state` | محرك المزامنة | لا (داخلي) | `table_name` (TEXT PK) | توقيت آخر سحب ناجح لكل جدول |
| 25 | `sync_tombstones` | محرك المزامنة | لا (داخلي) | `id` (INTEGER PK AUTO) | سجلات الحذف لرفعها للسحابة (Soft Delete) |
| 26 | `sync_flag` | محرك المزامنة | لا (داخلي) | `id` (INTEGER PK) | راية لمنع التكرار الدائري أثناء السحب |
| 27 | `sqlite_sequence` | محرك SQLite | لا (داخلي) | داخلي بنظام SQLite | إدارة أرقام AUTOINCREMENT التلقائية |

---

## 3. تفاصيل أعمدة الجداول الـ 27 (PRAGMA table_info)

### 3.1 جداول الأداء والفسيولوجيا
#### جدول `players` (متزامن)
- `id` INTEGER PRIMARY KEY AUTOINCREMENT
- `name` TEXT NOT NULL
- `mhr` INTEGER NOT NULL DEFAULT 190
- `active` INTEGER DEFAULT 1
- `coach_id` INTEGER
- `curves_shared` INTEGER DEFAULT 0
- `curves_shared_by` TEXT
- *أعمدة المزامنة المضافة:* `remote_id` TEXT, `updated_at` TEXT, `dirty` INTEGER DEFAULT 0

#### جدول `logs` (متزامن)
- المفتاح الأساسي: `PRIMARY KEY(player_id, date, idx)`
- الأعمدة الفسيولوجية: `player_id` INT, `date` TEXT, `idx` INT, `rhr` INT, `hrv` INT, `hr` INT, `hr_max` INT, `hr_post` INT, `hr_1min` INT, `weight` REAL, `fatigue` INT, `sleep_hours` REAL, `readiness` INT, `player_notes` TEXT
- أعمدة القدرة والأداء: `avg_power` REAL, `max_power` REAL, `duration_seconds` INT, `distance` INT, `split_500` REAL, `ef` REAL, `eupnea` REAL, `decoupling` REAL, `entered_by` TEXT, `eupnea_1` REAL, `eupnea_2` REAL, `eupnea_3` REAL, `zone` TEXT, `kind` TEXT, `zone_method` TEXT
- *أعمدة المزامنة المضافة:* `remote_id` TEXT, `updated_at` TEXT, `dirty` INTEGER DEFAULT 0

#### جدول `cp_tests` (متزامن)
- `id` INTEGER PRIMARY KEY AUTOINCREMENT, `player_id` INT, `date` TEXT, `test_type` TEXT, `duration_seconds` INT, `avg_power` REAL, `max_power` REAL, `distance` INT, `avg_hr` INT, `max_hr` INT, `split_500` REAL, `notes` TEXT
- *أعمدة المزامنة:* `remote_id`, `updated_at`, `dirty`

#### جدول `cp_values` (متزامن)
- المفتاح الأساسي: `PRIMARY KEY(player_id, date)`
- الأعمدة: `player_id` INT, `date` TEXT, `cp` REAL, `w_prime` REAL, `estimated` INT DEFAULT 0
- *أعمدة المزامنة:* `remote_id`, `updated_at`, `dirty`

### 3.2 جداول الحصص والبرامج
#### جدول `sessions` (متزامن)
- المفتاح الأساسي: `PRIMARY KEY(date, idx)`
- الأعمدة: `date` TEXT, `idx` INT, `kind` TEXT, `zone` TEXT
- *أعمدة المزامنة:* `remote_id`, `updated_at`, `dirty`

#### جدول `notes` (متزامن)
- المفتاح الأساسي: `date TEXT PRIMARY KEY`
- الأعمدة: `date` TEXT, `general` TEXT, `tech` TEXT
- *أعمدة المزامنة:* `remote_id`, `updated_at`, `dirty`

#### جدول `program_cycles` (متزامن)
- `id` INTEGER PK AUTO, `name` TEXT, `description` TEXT, `start_date` TEXT, `end_date` TEXT, `total_weeks` INT DEFAULT 4, `is_active` INT DEFAULT 0, `created_at` TEXT
- *أعمدة المزامنة:* `remote_id`, `updated_at`, `dirty`

#### جدول `program_sessions` (متزامن)
- `id` INTEGER PK AUTO, `cycle_id` INT, `cycle_type` TEXT, `day_of_week` INT, `session_idx` INT, `name` TEXT, `time` TEXT, `location` TEXT, `notes_physio` TEXT, `notes_tech` TEXT, `comment` TEXT, `created_at` TEXT
- *أعمدة المزامنة:* `remote_id`, `updated_at`, `dirty`

#### جدول `program_workout_items` (متزامن)
- `id` INTEGER PK AUTO, `session_id` INT, `section` TEXT, `item_idx` INT, `intensity` TEXT, `distance_meters` INT, `stroke_rate` INT, `duration_seconds` INT, `notes` TEXT, `created_at` TEXT
- *أعمدة المزامنة:* `remote_id`, `updated_at`, `dirty`

#### جدول `program_day_config` (متزامن)
- المفتاح الأساسي: `PRIMARY KEY(cycle_id, cycle_type, day_of_week)`
- الأعمدة: `cycle_id` INT, `cycle_type` TEXT, `day_of_week` INT, `location` TEXT, `dispatch_date` TEXT, `dispatch_time` TEXT, `comment` TEXT
- *أعمدة المزامنة:* `remote_id`, `updated_at`, `dirty`

#### جدول `program_cycle_tests` (متزامن)
- المفتاح الأساسي: `PRIMARY KEY(cycle_id, test_type)`
- الأعمدة: `cycle_id` INT, `test_type` TEXT, `scheduled_date` TEXT, `distance` INT, `duration_seconds` INT, `notes` TEXT
- *أعمدة المزامنة:* `remote_id`, `updated_at`, `dirty`

#### جدول `athlete_custom_sessions` (متزامن)
- `id` INTEGER PK AUTO, `player_id` INT, `date` TEXT, `session_idx` INT, `location` TEXT, `dispatch_time` TEXT, `notes_physio` TEXT, `notes_tech` TEXT, `coach_notes` TEXT, `coach_edited` INT DEFAULT 0, `coach_edited_at` TEXT, `is_rest_day` INT DEFAULT 0, `created_at` TEXT, `UNIQUE(player_id, date, session_idx)`
- *أعمدة المزامنة:* `remote_id`, `updated_at`, `dirty`

#### جدول `athlete_custom_workout_items` (متزامن)
- `id` INTEGER PK AUTO, `custom_session_id` INT, `section` TEXT, `item_idx` INT, `intensity` TEXT, `distance_meters` INT, `stroke_rate` INT, `duration_seconds` INT, `notes` TEXT, `created_at` TEXT
- *أعمدة المزامنة:* `remote_id`, `updated_at`, `dirty`

### 3.3 جداول التواصل والتنظيم
#### جدول `testing_dates` (متزامن)
- `id` INTEGER PK AUTO, `test_name` TEXT, `test_date` TEXT, `test_time` TEXT, `location` TEXT, `notes` TEXT, `created_at` TEXT
- *أعمدة المزامنة:* `remote_id`, `updated_at`, `dirty`

#### جدول `testing_date_recipients` (متزامن)
- المفتاح الأساسي: `PRIMARY KEY (testing_date_id, athlete_id)`
- الأعمدة: `testing_date_id` INT, `athlete_id` INT, `status` TEXT DEFAULT 'pending'
- *أعمدة المزامنة:* `remote_id`, `updated_at`, `dirty`

#### جدول `coach_messages` (متزامن)
- `id` INTEGER PK AUTO, `coach_id` INT, `recipient_type` TEXT, `recipient_id` INT, `text` TEXT, `created_at` TEXT
- *أعمدة المزامنة:* `remote_id`, `updated_at`, `dirty`

#### جدول `coach_requests` (متزامن)
- `id` INTEGER PK AUTO, `coach_id` INT, `athlete_id` INT, `status` TEXT DEFAULT 'pending', `created_at` TEXT
- *أعمدة المزامنة:* `remote_id`, `updated_at`, `dirty`

### 3.4 جداول التهيئة والتحليل
#### جدول `matrix_zone_config` (متزامن)
- `key` TEXT PRIMARY KEY, `weight` REAL, `direction` TEXT
- *أعمدة المزامنة:* `remote_id`, `updated_at`, `dirty`

#### جدول `progress_baseline_config` (متزامن)
- `key` TEXT PRIMARY KEY, `value` REAL
- *أعمدة المزامنة:* `remote_id`, `updated_at`, `dirty`

### 3.5 جداول غير متزامنة (محلية فقط)
#### جدول `users`
- `id` INTEGER PRIMARY KEY AUTOINCREMENT
- `email` TEXT NOT NULL UNIQUE
- `password_hash` TEXT NOT NULL
- `salt` TEXT NOT NULL
- `name` TEXT NOT NULL
- `role` TEXT NOT NULL
- `coach_id` INTEGER
- `subscription_active` INTEGER DEFAULT 1
- `player_id` INTEGER
- `photo_path` TEXT
- `created_at` TEXT

#### جدول `daily_load` (كاش تحليلي تراكمي)
- `PRIMARY KEY(player_id, date)`
- `player_id` INTEGER NOT NULL, `date` TEXT NOT NULL, `tss` REAL, `ctl` REAL NOT NULL, `atl` REAL NOT NULL, `tsb` REAL NOT NULL

#### جدول `sync_state`
- `table_name` TEXT PRIMARY KEY, `last_pulled_at` TEXT

#### جدول `sync_tombstones`
- `id` INTEGER PRIMARY KEY AUTOINCREMENT, `table_name` TEXT NOT NULL, `remote_key` TEXT NOT NULL, `deleted_at` TEXT NOT NULL

#### جدول `sync_flag`
- `id` INTEGER PRIMARY KEY, `active` INTEGER DEFAULT 0

#### جدول `cycles` (قديم غير مستخدم)
- `id` INTEGER PRIMARY KEY AUTOINCREMENT, `name` TEXT, `start` TEXT, `end` TEXT

---

## 4. شبكة العلاقات المنطقية (Logical Referential Network)
نظراً لعدم وجود قيود `FOREIGN KEY` مباشرة في SQLite، يعتمد التطبيق على التوافق المنطقي البرمجي التالي:

```
players (id)
 ├── logs (player_id)
 ├── cp_tests (player_id)
 ├── cp_values (player_id)
 ├── athlete_custom_sessions (player_id)
 ├── testing_date_recipients (athlete_id)
 ├── coach_requests (athlete_id)
 ├── users (player_id)
 └── daily_load (player_id)

program_cycles (id)
 ├── program_sessions (cycle_id)
 ├── program_day_config (cycle_id)
 └── program_cycle_tests (cycle_id)

program_sessions (id)
 └── program_workout_items (session_id)

athlete_custom_sessions (id)
 └── athlete_custom_workout_items (custom_session_id)

testing_dates (id)
 └── testing_date_recipients (testing_date_id)

sessions (date, idx)
 └── logs (date, idx) [ارتباط منطقي بين الحصة المنفذة وحصة الجدول]
```

---

## 5. منظومة التريجرات التلقائية للمزامنة (60 Triggers)
لكل جدول من الجداول الـ 20 المتزامنة، يتم إنشاء 3 تريجرات عند الإقلاع بواسطة `SyncEngine.ensureDatabaseSyncSchema`:
1. `trg_insert_{table}`: عند إدخال صف جديد و `sync_flag.active = 0`، يُعيّن `dirty = 1` و `updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')`.
2. `trg_update_{table}`: عند تعديل صف و `sync_flag.active = 0`، يُعيّن `dirty = 1` و `updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')`.
3. `trg_delete_{table}`: عند حذف صف و `sync_flag.active = 0`، يُسجّل المفتاح المحذوف في `sync_tombstones`.
