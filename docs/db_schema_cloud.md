# ENGINE ROWING - مخطط قاعدة البيانات السحابية ومطابقة الحقول (Supabase Cloud Schema & Diff)
## مستخرج من ملف الترحيل الأولي السحابي `supabase/migrations/0001_init.sql`

---

## 1. الملخص العام لمخطط السحابة (PostgreSQL / Supabase)
- **إجمالي الجداول السحابية:** **23 جدولاً**.
- **عدد الـ Views السحابية:** **1 View** (`public.shared_curve_data` مع خيار `security_invoker = true`).
- **نظام المعرفات:** جميع الجداول السحابية تعتمد معرفات `UUID` افتراضية (`gen_random_uuid()`)، مع حفظ المعرف المحلي في عمود `local_id` عند الحاجة.
- **سياسات الأمان على مستوى الصف (RLS):** مفعلة على كافة الجداول الـ 23 بنسبة 100% مع سياسات صارمة تفصل بين المدرب واللاعب والمسؤول.

---

## 2. فهرس الجداول السحابية وعلاقات المفاتيح الأجنبية الفعلية (Foreign Keys)

على عكس المخطط المحلي (الذي لا يحتوي قيود مفاتيح أجنبية)، يفرض المخطط السحابي قيود سلامة مرجعية صارمة على مستوى محرك PostgreSQL:

| اسم الجدول السحابي | المفتاح الأساسي | المفاتيح الأجنبية والارتباطات (Foreign Keys) | سياسة الحذف (ON DELETE) |
|---|---|---|---|
| `profiles` | `id UUID` | `id -> auth.users(id)`<br>`coach_id -> public.profiles(id)` | `CASCADE`<br>`NO ACTION` |
| `subscriptions` | `id UUID` | `user_id -> public.profiles(id)`<br>`by_admin -> public.profiles(id)` | `CASCADE`<br>`NO ACTION` |
| `subscription_log` | `id UUID` | `subscription_id -> public.subscriptions(id)`<br>`user_id -> public.profiles(id)`<br>`changed_by -> public.profiles(id)` | `CASCADE`<br>`CASCADE`<br>`NO ACTION` |
| `coach_requests` | `id UUID` | `athlete_id -> public.profiles(id)`<br>`coach_id -> public.profiles(id)` | `CASCADE`<br>`CASCADE` |
| `players` | `id UUID` | `coach_id -> public.profiles(id)`<br>`athlete_user_id -> public.profiles(id)` | `SET NULL`<br>`SET NULL` |
| `logs` | `id UUID` | `coach_id -> public.profiles(id)`<br>`athlete_user_id -> public.profiles(id)` | `SET NULL`<br>`SET NULL` |
| `sessions` | `id UUID` | `coach_id -> public.profiles(id)` | `SET NULL` |
| `notes` | `id UUID` | `coach_id -> public.profiles(id)` | `SET NULL` |
| `program_cycles` | `id UUID` | `coach_id -> public.profiles(id)` | `SET NULL` |
| `program_cycle_tests`| `id UUID` | `coach_id -> public.profiles(id)` | `SET NULL` |
| `program_day_config` | `id UUID` | `coach_id -> public.profiles(id)` | `SET NULL` |
| `program_sessions` | `id UUID` | `coach_id -> public.profiles(id)` | `SET NULL` |
| `program_workout_items`| `id UUID` | `coach_id -> public.profiles(id)` | `SET NULL` |
| `cycle_templates` | `id UUID` | `coach_id -> public.profiles(id)` | `SET NULL` |
| `athlete_custom_sessions` | `id UUID` | `coach_id -> public.profiles(id)`<br>`athlete_user_id -> public.profiles(id)` | `SET NULL`<br>`SET NULL` |
| `athlete_custom_workout_items` | `id UUID` | `coach_id -> public.profiles(id)` | `SET NULL` |
| `cp_tests` | `id UUID` | `coach_id -> public.profiles(id)`<br>`athlete_user_id -> public.profiles(id)` | `SET NULL`<br>`SET NULL` |
| `cp_values` | `id UUID` | `coach_id -> public.profiles(id)`<br>`athlete_user_id -> public.profiles(id)` | `SET NULL`<br>`SET NULL` |
| `testing_dates` | `id UUID` | `coach_id -> public.profiles(id)` | `SET NULL` |
| `testing_date_recipients` | `id UUID` | `testing_date_id -> public.testing_dates(id)`<br>`coach_id -> public.profiles(id)`<br>`athlete_user_id -> public.profiles(id)` | `CASCADE`<br>`SET NULL`<br>`SET NULL` |
| `coach_messages` | `id UUID` | `coach_id -> public.profiles(id)` | `SET NULL` |
| `progress_baseline_config` | `id UUID` | `coach_id -> public.profiles(id)` | `SET NULL` |
| `matrix_zone_config` | `id UUID` | `coach_id -> public.profiles(id)` | `SET NULL` |

---

## 3. جدول المطابقة والفروق بين المخطط المحلي والمخطط السحابي (Schema Diff)

يوضح الجدول التالي الأعمدة الموجودة في طرف واحد فقط، وكيفية معالجتها في محرك المزامنة Local-First:

| اسم الجدول | الأعمدة الموجودة محلياً فقط (SQLite Only) | الأعمدة الموجودة سحابياً فقط (Cloud Supabase Only) | سبب الاختلاف وتأثير المزامنة |
|---|---|---|---|
| **players** | `dirty` (راية مزامنة محلية) | `athlete_user_id` (UUID), `coach_id` (UUID كمرجع للملف الشخصي السحابي) | محلياً `coach_id` رقمي INT، وسحابياً UUID يرتبط بـ `profiles`. |
| **logs** | `dirty` (راية مزامنة محلية) | `athlete_user_id` (UUID), `coach_id` (UUID) | تُستخدم في السحابة لفرض سياسات RLS وقفل منتصف الليل. |
| **sessions** | `dirty` (راية مزامنة محلية) | `id` (UUID), `coach_id` (UUID) | محلياً المفتاح الأساسي مركب `(date, idx)`، وسحابياً يوجد `id UUID`. |
| **notes** | `dirty` (راية مزامنة محلية) | `id` (UUID), `coach_id` (UUID) | محلياً المفتاح `date`، وسحابياً يوجد `id UUID`. |
| **program_day_config** | `dirty` (راية مزامنة محلية) | `id` (UUID), `coach_id` (UUID) | محلياً المفتاح ثلاثي مركب، وسحابياً `id UUID`. |
| **program_cycle_tests**| `dirty` (راية مزامنة محلية) | `id` (UUID), `coach_id` (UUID) | محلياً المفتاح ثنائي مركب، وسحابياً `id UUID`. |
| **cp_values** | `dirty` (راية مزامنة محلية) | `id` (UUID), `coach_id` (UUID), `athlete_user_id` (UUID) | محلياً المفتاح ثنائي `(player_id, date)`، وسحابياً `id UUID`. |
| **testing_date_recipients** | `dirty` (راية مزامنة محلية) | `id` (UUID), `coach_id` (UUID), `athlete_user_id` (UUID) | محلياً المفتاح ثنائي مركب، وسحابياً `id UUID`. |
| **users vs profiles** | `users` جدول محلي كامل (`salt`, `password_hash`) | `profiles`, `subscriptions`, `subscription_log` | إدارة الهوية في السحابة تتم عبر `auth.users` و `profiles` المنفصلة عن الاشتراكات. |
| **daily_load** | موجود محلياً فقط | غير موجود في السحابة | جدول كاش واشتقاق محلي لتسريع رسومات PMC، لا يحتاج مزامنة. |
| **sync_state / sync_tombstones / sync_flag** | موجودة محلياً فقط | غير موجودة في السحابة | جداول تتبع المزامنة وإدارة الحذف الناعم ومكافحة الحلقات اللانهائية. |

---

## 4. سياسات الأمان RLS المطبقة على السحابة
1. **المدرب (Coach):**
   - صلاحية قراءة وكتابة كاملة على جميع جداول البرامج والحصص والملاحظات ولاعبيه التابعين له.
2. **اللاعب (Athlete):**
   - صلاحية قراءة الحصص العامة للمدرب والبرامج المخصصة له.
   - صلاحية إدخال وتعديل سجلات `logs` الخاصة به فقط قبل منتصف الليل (قفل السيرفر التلقائي `Server Midnight Lock`).
   - ممنوع من رؤية سجلات اللاعبين الآخرين إلا إذا شارك اللاعب منحنياته (`curves_shared = 1`).
3. **المسؤول (Admin):**
   - إدارة الاشتراكات في `subscriptions` و `subscription_log` وتفعيل وتعطيل الحسابات.
