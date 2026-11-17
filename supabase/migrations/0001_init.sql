-- ============================================================================
-- 0001_init.sql: ترحيل قاعدة بيانات سحابة Supabase لتطبيق Engine Rowing
-- يحتوي على كافة الجداول، العلاقات، الفهارس، صلاحيات الأمان RLS، ودوال التحقق
-- ============================================================================

-- تفعيل ملحقات توليد المعرفات الفريدة
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- 1. جدول الملفات الشخصية (profiles)
-- يرتبط مباشرة بـ auth.users
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('coach', 'athlete', 'admin')),
    name TEXT NOT NULL DEFAULT '',
    email TEXT NOT NULL DEFAULT '',
    coach_id UUID REFERENCES public.profiles(id),
    player_id BIGINT,
    photo_path TEXT,
    timezone TEXT NOT NULL DEFAULT 'Africa/Cairo',
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_profiles_role ON public.profiles(role);
CREATE INDEX IF NOT EXISTS idx_profiles_coach ON public.profiles(coach_id);
CREATE INDEX IF NOT EXISTS idx_profiles_player ON public.profiles(player_id);

-- ============================================================================
-- 2. جدول الاشتراكات (subscriptions)
-- مفصول عن profiles - لا يكتب فيه إلا الأدمن فقط
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE REFERENCES public.profiles(id) ON DELETE CASCADE,
    active BOOLEAN NOT NULL DEFAULT false,
    activated_at TIMESTAMPTZ,
    note TEXT DEFAULT '',
    by_admin UUID REFERENCES public.profiles(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_subscriptions_user ON public.subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_active ON public.subscriptions(active);

-- ============================================================================
-- 3. سجل تدقيق الاشتراكات (subscription_log)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.subscription_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_id UUID NOT NULL REFERENCES public.subscriptions(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    action TEXT NOT NULL, -- 'created', 'activated', 'deactivated', 'note_updated'
    changed_by UUID REFERENCES public.profiles(id),
    note TEXT DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_sub_log_sub ON public.subscription_log(subscription_id);
CREATE INDEX IF NOT EXISTS idx_sub_log_user ON public.subscription_log(user_id);

-- ============================================================================
-- 4. جدول طلبات انضمام اللاعبين للمدرب (coach_requests)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.coach_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    athlete_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    coach_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ,
    UNIQUE(athlete_id, coach_id)
);

CREATE INDEX IF NOT EXISTS idx_coach_requests_coach ON public.coach_requests(coach_id);
CREATE INDEX IF NOT EXISTS idx_coach_requests_athlete ON public.coach_requests(athlete_id);

-- ============================================================================
-- 5. جدول اللاعبين (players)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.players (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    local_id BIGINT,
    coach_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    athlete_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    name TEXT NOT NULL,
    mhr INTEGER NOT NULL DEFAULT 190,
    active INTEGER NOT NULL DEFAULT 1,
    curves_shared INTEGER DEFAULT 0,
    curves_shared_by TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_players_coach ON public.players(coach_id);
CREATE INDEX IF NOT EXISTS idx_players_athlete ON public.players(athlete_user_id);

-- ============================================================================
-- 6. جدول سجلات التمارين اليومية (logs)
-- المفتاح الطبيعي: player_id + date + idx
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id BIGINT NOT NULL,
    athlete_user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    coach_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    date TEXT NOT NULL,
    idx INTEGER NOT NULL,
    rhr INTEGER,
    hrv INTEGER,
    hr INTEGER,
    hr_max INTEGER,
    hr_post INTEGER,
    hr_1min INTEGER,
    weight REAL,
    fatigue INTEGER,
    sleep_hours REAL,
    readiness INTEGER,
    player_notes TEXT,
    avg_power REAL,
    max_power REAL,
    duration_seconds INTEGER,
    distance INTEGER,
    split_500 REAL,
    ef REAL,
    decoupling REAL,
    eupnea_1 REAL,
    eupnea_2 REAL,
    eupnea_3 REAL,
    entered_by TEXT,
    zone TEXT,
    kind TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ,
    UNIQUE(player_id, date, idx)
);

CREATE INDEX IF NOT EXISTS idx_logs_player_date ON public.logs(player_id, date);
CREATE INDEX IF NOT EXISTS idx_logs_athlete_date ON public.logs(athlete_user_id, date);
CREATE INDEX IF NOT EXISTS idx_logs_coach ON public.logs(coach_id);

-- ============================================================================
-- 7. جدول الحصص التدريبية المخططة (sessions)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    coach_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    date TEXT NOT NULL,
    idx INTEGER NOT NULL,
    kind TEXT,
    zone TEXT,
    time TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ,
    UNIQUE(coach_id, date, idx)
);

CREATE INDEX IF NOT EXISTS idx_sessions_coach_date ON public.sessions(coach_id, date);

-- ============================================================================
-- 8. جدول الملاحظات اليومية العامة والفنية (notes)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    coach_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    date TEXT NOT NULL,
    general TEXT,
    tech TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ,
    UNIQUE(coach_id, date)
);

-- ============================================================================
-- 9. جدول الدورات المرحلية للبرنامج (program_cycles)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.program_cycles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    local_id BIGINT,
    coach_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    start_date TEXT NOT NULL,
    end_date TEXT NOT NULL,
    location TEXT DEFAULT '',
    basic_reps INTEGER DEFAULT 3,
    secondary_reps INTEGER DEFAULT 1,
    notes_physio TEXT DEFAULT '',
    notes_tech TEXT DEFAULT '',
    comment TEXT DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_program_cycles_coach ON public.program_cycles(coach_id);

-- ============================================================================
-- 10. جدول اختبارات الدورة المرحلية (program_cycle_tests)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.program_cycle_tests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cycle_id UUID NOT NULL REFERENCES public.program_cycles(id) ON DELETE CASCADE,
    coach_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    test_type TEXT NOT NULL,
    test_date TEXT DEFAULT '',
    target_value TEXT DEFAULT '',
    is_completed INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ,
    UNIQUE(cycle_id, test_type)
);

-- ============================================================================
-- 11. جدول إعدادات أيام الأسبوع (program_day_config)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.program_day_config (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cycle_id UUID NOT NULL REFERENCES public.program_cycles(id) ON DELETE CASCADE,
    coach_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    cycle_type TEXT NOT NULL,
    day_of_week INTEGER NOT NULL,
    location TEXT DEFAULT '',
    dispatch_date TEXT DEFAULT '',
    dispatch_time TEXT DEFAULT '',
    comment TEXT DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ,
    UNIQUE(cycle_id, cycle_type, day_of_week)
);

-- ============================================================================
-- 12. جدول الحصص في البرنامج (program_sessions)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.program_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cycle_id UUID NOT NULL REFERENCES public.program_cycles(id) ON DELETE CASCADE,
    coach_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    cycle_type TEXT NOT NULL,
    day_of_week INTEGER NOT NULL,
    session_idx INTEGER NOT NULL,
    name TEXT NOT NULL,
    time TEXT NOT NULL,
    notes_physio TEXT DEFAULT '',
    notes_tech TEXT DEFAULT '',
    comment TEXT DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_program_sessions_cycle ON public.program_sessions(cycle_id);

-- ============================================================================
-- 13. جدول تفاصيل تمارين الحصة (program_workout_items)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.program_workout_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES public.program_sessions(id) ON DELETE CASCADE,
    coach_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    section TEXT NOT NULL,
    item_idx INTEGER NOT NULL,
    time TEXT DEFAULT '',
    duration_minutes INTEGER DEFAULT 0,
    duration_seconds INTEGER DEFAULT 0,
    hr_percent INTEGER DEFAULT 0,
    hr_range TEXT DEFAULT '',
    distance_meters INTEGER DEFAULT 0,
    reps INTEGER DEFAULT 1,
    kind TEXT DEFAULT 'Erg',
    zone TEXT DEFAULT 'Z2',
    details TEXT DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_pwi_session ON public.program_workout_items(session_id);

-- ============================================================================
-- 14. جدول قوالب الدورة التدريبية (cycle_templates)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.cycle_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    coach_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    cycle_id UUID REFERENCES public.program_cycles(id) ON DELETE CASCADE,
    day_of_week INTEGER NOT NULL,
    slot_idx INTEGER NOT NULL,
    name TEXT DEFAULT '',
    time TEXT DEFAULT '',
    kind TEXT DEFAULT 'Erg',
    zone TEXT DEFAULT 'Z2',
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ
);

-- ============================================================================
-- 15. جدول حصص اللاعب المخصصة (athlete_custom_sessions)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.athlete_custom_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id BIGINT NOT NULL,
    athlete_user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    coach_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    date TEXT NOT NULL,
    session_idx INTEGER NOT NULL,
    name TEXT,
    time TEXT,
    notes_physio TEXT,
    notes_tech TEXT,
    comment TEXT,
    edited_by TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ,
    UNIQUE(player_id, date, session_idx)
);

CREATE INDEX IF NOT EXISTS idx_acs_player_date ON public.athlete_custom_sessions(player_id, date);

-- ============================================================================
-- 16. جدول تفاصيل تمارين الحصة المخصصة (athlete_custom_workout_items)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.athlete_custom_workout_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    custom_session_id UUID NOT NULL REFERENCES public.athlete_custom_sessions(id) ON DELETE CASCADE,
    athlete_user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    coach_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    section TEXT NOT NULL,
    item_idx INTEGER NOT NULL,
    time TEXT,
    duration_minutes INTEGER,
    duration_seconds INTEGER,
    hr_percent REAL,
    hr_range TEXT,
    distance_meters INTEGER,
    reps INTEGER,
    kind TEXT,
    zone TEXT,
    details TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ,
    UNIQUE(custom_session_id, section, item_idx)
);

CREATE INDEX IF NOT EXISTS idx_acwi_custom_session ON public.athlete_custom_workout_items(custom_session_id);

-- ============================================================================
-- 17. جدول اختبارات القدرة الحرجة (cp_tests)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.cp_tests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id BIGINT NOT NULL,
    athlete_user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    coach_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    date TEXT NOT NULL,
    test_type TEXT,
    duration_seconds INTEGER,
    avg_power REAL,
    max_power REAL,
    distance INTEGER,
    avg_hr INTEGER,
    max_hr INTEGER,
    split_500 REAL,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_cp_tests_player ON public.cp_tests(player_id);

-- ============================================================================
-- 18. جدول قيم القدرة الحرجة المحسوبة (cp_values)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.cp_values (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id BIGINT NOT NULL,
    athlete_user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    coach_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    date TEXT NOT NULL,
    cp REAL,
    w_prime REAL,
    method TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ,
    UNIQUE(player_id, date)
);

-- ============================================================================
-- 19. جدول مواعيد الاختبارات المقررة (testing_dates)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.testing_dates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    coach_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    test_name TEXT NOT NULL,
    test_date TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ
);

-- ============================================================================
-- 20. جدول مستلمي مواعيد الاختبارات (testing_date_recipients)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.testing_date_recipients (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    testing_date_id UUID NOT NULL REFERENCES public.testing_dates(id) ON DELETE CASCADE,
    athlete_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ,
    UNIQUE(testing_date_id, athlete_id)
);

-- ============================================================================
-- 21. جدول رسائل المدرب للاعبين (coach_messages)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.coach_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    coach_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    athlete_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    message TEXT NOT NULL,
    date TEXT NOT NULL,
    is_read INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_coach_msg_athlete ON public.coach_messages(athlete_id);

-- ============================================================================
-- 22. جدول إعدادات خط الأساس للتقدم (progress_baseline_config)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.progress_baseline_config (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    key TEXT NOT NULL,
    value REAL NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ,
    UNIQUE(owner_id, key)
);

-- ============================================================================
-- 23. جدول إعدادات مصفوفة مناطق التدريب (matrix_zone_config)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.matrix_zone_config (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    coach_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    key TEXT NOT NULL,
    value TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ,
    UNIQUE(coach_id, key)
);

-- ============================================================================
-- الدوال المساعدة (Security Helper Functions) للأمان والـ RLS
-- ============================================================================

-- جلب دور المستخدم الحالي
CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT role FROM public.profiles WHERE id = auth.uid() LIMIT 1;
$$;

-- التحقق هل المستخدم مسؤول (Admin)
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role = 'admin' AND deleted_at IS NULL
    );
$$;

-- التحقق هل المستخدم مدرب (Coach)
CREATE OR REPLACE FUNCTION public.is_coach()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role = 'coach' AND deleted_at IS NULL
    );
$$;

-- التحقق هل المستخدم مشترك ومفعّل حسابه (Active Subscription)
CREATE OR REPLACE FUNCTION public.is_active_subscriber(check_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.subscriptions
        WHERE user_id = check_user_id AND active = true AND deleted_at IS NULL
    );
$$;

-- جلب معرّف مدرب اللاعب الحالي
CREATE OR REPLACE FUNCTION public.get_my_coach_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT coach_id FROM public.profiles WHERE id = auth.uid() LIMIT 1;
$$;

-- ============================================================================
-- المشغلات التلقائية (Triggers): منع تسجيل الأدمن تلقائياً ومزامنة الاشتراكات
-- ============================================================================

-- منع التسجيل كمسؤول أثناء إنشاء الحساب، وإنشاء سجل Profile واشتراك غير مفعّل تلقائياً
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    req_role TEXT;
    req_name TEXT;
BEGIN
    -- قراءة الدور والاسم من بيانات الميتا المرسلة مع التسجيل
    req_role := LOWER(COALESCE(NEW.raw_user_meta_data->>'role', 'athlete'));
    req_name := COALESCE(NEW.raw_user_meta_data->>'name', '');

    -- منع تسجيل دور المسؤول نهائياً عند إنشاء الحساب
    IF req_role = 'admin' THEN
        req_role := 'athlete';
    END IF;

    IF req_role NOT IN ('coach', 'athlete') THEN
        req_role := 'athlete';
    END IF;

    -- إنشاء صف الملف الشخصي
    INSERT INTO public.profiles (id, role, name, email, timezone)
    VALUES (NEW.id, req_role, req_name, NEW.email, 'Africa/Cairo')
    ON CONFLICT (id) DO UPDATE SET
        name = EXCLUDED.name,
        email = EXCLUDED.email;

    -- إنشاء صف الاشتراك كـ غير مفعّل (active = false)
    INSERT INTO public.subscriptions (user_id, active, note)
    VALUES (NEW.id, false, 'حساب جديد في انتظار تفعيل الإدارة')
    ON CONFLICT (user_id) DO NOTHING;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- حظر ترقية المستخدم لدور admin عبر واجهة المستخدم المباشرة في جدول profiles
CREATE OR REPLACE FUNCTION public.prevent_direct_admin_promotion()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF (NEW.role = 'admin' AND (OLD.role IS NULL OR OLD.role <> 'admin')) THEN
        -- لا يسمح بالترقية لدور admin إلا من قبل مستخدم مسؤول مسبقاً أو عبر أوامر SQL من الخادم
        IF NOT public.is_admin() THEN
            RAISE EXCEPTION 'غير مصرح بتعيين دور مسؤول إلا من قبل الإدارة';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_direct_admin ON public.profiles;
CREATE TRIGGER trg_prevent_direct_admin
    BEFORE INSERT OR UPDATE OF role ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.prevent_direct_admin_promotion();

-- ============================================================================
-- قفل الحصص على الخادم (Midnight 12:00 AM Lock Trigger)
-- يمنع اللاعب من إدخال أو تعديل سجل تاريخه قبل بداية اليوم الحالي بتوقيته
-- المدرب مستثنى دائماً
-- ============================================================================
CREATE OR REPLACE FUNCTION public.enforce_logs_midnight_lock()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    user_tz TEXT;
    today_in_tz DATE;
    session_dt DATE;
    user_r TEXT;
BEGIN
    user_r := public.current_user_role();

    -- المدرب والمسؤول مستثنيان من قفل منتصف الليل
    IF user_r IN ('coach', 'admin') THEN
        RETURN NEW;
    END IF;

    -- جلب المنطقة الزمنية للاعب (الافتراضي Africa/Cairo)
    SELECT COALESCE(timezone, 'Africa/Cairo') INTO user_tz
    FROM public.profiles
    WHERE id = auth.uid();

    IF user_tz IS NULL THEN
        user_tz := 'Africa/Cairo';
    END IF;

    -- حساب تاريخ اليوم في المنطقة الزمنية للاعب
    today_in_tz := (timezone(user_tz, now()))::date;

    BEGIN
        session_dt := NEW.date::date;
    EXCEPTION WHEN OTHERS THEN
        RETURN NEW;
    END;

    -- إذا كان تاريخ الحصة يسبق تاريخ اليوم -> قفل صارم
    IF session_dt < today_in_tz THEN
        RAISE EXCEPTION 'هذه الحصة مقفولة تلقائياً بعد منتصف الليل (12:00 AM). يرجى مراجعة المدرب.';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_logs_midnight_lock ON public.logs;
CREATE TRIGGER trg_logs_midnight_lock
    BEFORE INSERT OR UPDATE ON public.logs
    FOR EACH ROW EXECUTE FUNCTION public.enforce_logs_midnight_lock();

-- مشغل تسجيل حركات تعديل الاشتراكات (subscription_log)
CREATE OR REPLACE FUNCTION public.log_subscription_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF (TG_OP = 'UPDATE') THEN
        IF (OLD.active <> NEW.active) THEN
            INSERT INTO public.subscription_log(subscription_id, user_id, action, changed_by, note)
            VALUES (
                NEW.id,
                NEW.user_id,
                CASE WHEN NEW.active THEN 'activated' ELSE 'deactivated' END,
                auth.uid(),
                NEW.note
            );
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_log_subscription_changes ON public.subscriptions;
CREATE TRIGGER trg_log_subscription_changes
    AFTER UPDATE ON public.subscriptions
    FOR EACH ROW EXECUTE FUNCTION public.log_subscription_changes();

-- ============================================================================
-- تفعيل أمان مستوى الصفوف (Row Level Security - RLS) على كل جدول بدون استثناء
-- ============================================================================
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coach_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.players ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.program_cycles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.program_cycle_tests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.program_day_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.program_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.program_workout_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cycle_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.athlete_custom_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.athlete_custom_workout_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cp_tests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cp_values ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.testing_dates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.testing_date_recipients ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coach_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.progress_baseline_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.matrix_zone_config ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- سياسات RLS: جدول profiles
-- ============================================================================
-- قراءة الملف الشخصي: يقرأ المستخدم ملفه الخاص، والمدرب يقرأ ملفات لاعبيه، واللاعب يقرأ مدربه وزملاءه بنفس المدرب، والمسؤول يقرأ الكل
DROP POLICY IF EXISTS "profiles_select_policy" ON public.profiles;
CREATE POLICY "profiles_select_policy" ON public.profiles
    FOR SELECT USING (
        auth.uid() = id
        OR public.is_admin()
        OR (public.is_coach() AND coach_id = auth.uid())
        OR (coach_id IS NOT NULL AND coach_id = (SELECT p.coach_id FROM public.profiles p WHERE p.id = auth.uid()))
        OR (id = (SELECT p.coach_id FROM public.profiles p WHERE p.id = auth.uid()))
    );

DROP POLICY IF EXISTS "profiles_update_policy" ON public.profiles;
CREATE POLICY "profiles_update_policy" ON public.profiles
    FOR UPDATE USING (
        auth.uid() = id OR public.is_admin()
    ) WITH CHECK (
        auth.uid() = id OR public.is_admin()
    );

-- ============================================================================
-- سياسات RLS: جدول subscriptions
-- الحساب غير المفعّل يسمح له بقراءة اشتراكه الخاص فقط لمعرفة الحالة
-- المسؤول يملك الصلاحية الكاملة للكتابة والتعديل
-- ============================================================================
DROP POLICY IF EXISTS "subscriptions_select_policy" ON public.subscriptions;
CREATE POLICY "subscriptions_select_policy" ON public.subscriptions
    FOR SELECT USING (
        auth.uid() = user_id OR public.is_admin()
    );

DROP POLICY IF EXISTS "subscriptions_admin_modify_policy" ON public.subscriptions;
CREATE POLICY "subscriptions_admin_modify_policy" ON public.subscriptions
    FOR ALL USING (
        public.is_admin()
    );

-- سياسات subscription_log: المسؤول فقط
DROP POLICY IF EXISTS "sub_log_admin_policy" ON public.subscription_log;
CREATE POLICY "sub_log_admin_policy" ON public.subscription_log
    FOR ALL USING (
        public.is_admin()
    );

-- ============================================================================
-- سياسات RLS: جدول coach_requests
-- ============================================================================
DROP POLICY IF EXISTS "coach_requests_select" ON public.coach_requests;
CREATE POLICY "coach_requests_select" ON public.coach_requests
    FOR SELECT USING (
        (auth.uid() = athlete_id OR auth.uid() = coach_id)
        AND public.is_active_subscriber()
    );

DROP POLICY IF EXISTS "coach_requests_insert" ON public.coach_requests;
CREATE POLICY "coach_requests_insert" ON public.coach_requests
    FOR INSERT WITH CHECK (
        auth.uid() = athlete_id
        AND public.is_active_subscriber()
        AND public.is_active_subscriber(coach_id) -- المدرب غير المفعل لا يقبل طلبات
    );

DROP POLICY IF EXISTS "coach_requests_update" ON public.coach_requests;
CREATE POLICY "coach_requests_update" ON public.coach_requests
    FOR UPDATE USING (
        auth.uid() = coach_id
        AND public.is_active_subscriber()
    );

-- ============================================================================
-- سياسات RLS: جدول players
-- الأدمن مستثنى وممنوع من رؤية بيانات التمارين والصحة
-- ============================================================================
DROP POLICY IF EXISTS "players_coach_all" ON public.players;
CREATE POLICY "players_coach_all" ON public.players
    FOR ALL USING (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND (coach_id = auth.uid() OR athlete_user_id = auth.uid())
    );

DROP POLICY IF EXISTS "players_teammate_read" ON public.players;
CREATE POLICY "players_teammate_read" ON public.players
    FOR SELECT USING (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND coach_id = public.get_my_coach_id()
    );

-- ============================================================================
-- سياسات RLS: جدول logs
-- اللاعب: يقرأ ويكتب صفوفه هو فقط
-- المدرب: يقرأ ويكتب بيانات لاعبيه فقط
-- الأدمن: محظور من بيانات التمارين والصحة
-- ============================================================================
DROP POLICY IF EXISTS "logs_athlete_policy" ON public.logs;
CREATE POLICY "logs_athlete_policy" ON public.logs
    FOR ALL USING (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND athlete_user_id = auth.uid()
    ) WITH CHECK (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND athlete_user_id = auth.uid()
    );

DROP POLICY IF EXISTS "logs_coach_policy" ON public.logs;
CREATE POLICY "logs_coach_policy" ON public.logs
    FOR ALL USING (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND (
            coach_id = auth.uid()
            OR player_id IN (SELECT local_id FROM public.players WHERE coach_id = auth.uid())
            OR athlete_user_id IN (SELECT id FROM public.profiles WHERE coach_id = auth.uid())
        )
    ) WITH CHECK (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND (
            coach_id = auth.uid()
            OR player_id IN (SELECT local_id FROM public.players WHERE coach_id = auth.uid())
            OR athlete_user_id IN (SELECT id FROM public.profiles WHERE coach_id = auth.uid())
        )
    );

-- ============================================================================
-- سياسات RLS: جدول sessions & notes
-- ============================================================================
DROP POLICY IF EXISTS "sessions_all_policy" ON public.sessions;
CREATE POLICY "sessions_all_policy" ON public.sessions
    FOR ALL USING (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND (coach_id = auth.uid() OR coach_id = public.get_my_coach_id())
    ) WITH CHECK (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND coach_id = auth.uid()
    );

DROP POLICY IF EXISTS "notes_all_policy" ON public.notes;
CREATE POLICY "notes_all_policy" ON public.notes
    FOR ALL USING (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND (coach_id = auth.uid() OR coach_id = public.get_my_coach_id())
    ) WITH CHECK (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND coach_id = auth.uid()
    );

-- ============================================================================
-- سياسات RLS: جداول البرنامج التدريبي (program_cycles, tests, sessions, workout_items)
-- المدرب يملك برنامجه (قراءة وكتابة)، واللاعب يقرأ برنامج مدربه فقط
-- ============================================================================
DROP POLICY IF EXISTS "program_cycles_policy" ON public.program_cycles;
CREATE POLICY "program_cycles_policy" ON public.program_cycles
    FOR ALL USING (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND (coach_id = auth.uid() OR coach_id = public.get_my_coach_id())
    ) WITH CHECK (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND coach_id = auth.uid()
    );

DROP POLICY IF EXISTS "program_cycle_tests_policy" ON public.program_cycle_tests;
CREATE POLICY "program_cycle_tests_policy" ON public.program_cycle_tests
    FOR ALL USING (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND (coach_id = auth.uid() OR coach_id = public.get_my_coach_id())
    ) WITH CHECK (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND coach_id = auth.uid()
    );

DROP POLICY IF EXISTS "program_day_config_policy" ON public.program_day_config;
CREATE POLICY "program_day_config_policy" ON public.program_day_config
    FOR ALL USING (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND (coach_id = auth.uid() OR coach_id = public.get_my_coach_id())
    ) WITH CHECK (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND coach_id = auth.uid()
    );

DROP POLICY IF EXISTS "program_sessions_policy" ON public.program_sessions;
CREATE POLICY "program_sessions_policy" ON public.program_sessions
    FOR ALL USING (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND (coach_id = auth.uid() OR coach_id = public.get_my_coach_id())
    ) WITH CHECK (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND coach_id = auth.uid()
    );

DROP POLICY IF EXISTS "program_workout_items_policy" ON public.program_workout_items;
CREATE POLICY "program_workout_items_policy" ON public.program_workout_items
    FOR ALL USING (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND (coach_id = auth.uid() OR coach_id = public.get_my_coach_id())
    ) WITH CHECK (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND coach_id = auth.uid()
    );

DROP POLICY IF EXISTS "cycle_templates_policy" ON public.cycle_templates;
CREATE POLICY "cycle_templates_policy" ON public.cycle_templates
    FOR ALL USING (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND (coach_id = auth.uid() OR coach_id = public.get_my_coach_id())
    ) WITH CHECK (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND coach_id = auth.uid()
    );

-- ============================================================================
-- سياسات RLS: جداول الحصص المخصصة للاعب (athlete_custom_sessions & items)
-- ============================================================================
DROP POLICY IF EXISTS "acs_policy" ON public.athlete_custom_sessions;
CREATE POLICY "acs_policy" ON public.athlete_custom_sessions
    FOR ALL USING (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND (
            athlete_user_id = auth.uid()
            OR coach_id = auth.uid()
            OR coach_id = public.get_my_coach_id()
        )
    ) WITH CHECK (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND (athlete_user_id = auth.uid() OR coach_id = auth.uid())
    );

DROP POLICY IF EXISTS "acwi_policy" ON public.athlete_custom_workout_items;
CREATE POLICY "acwi_policy" ON public.athlete_custom_workout_items
    FOR ALL USING (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND (
            athlete_user_id = auth.uid()
            OR coach_id = auth.uid()
            OR coach_id = public.get_my_coach_id()
        )
    ) WITH CHECK (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND (athlete_user_id = auth.uid() OR coach_id = auth.uid())
    );

-- ============================================================================
-- سياسات RLS: اختبارات CP (cp_tests & cp_values)
-- ============================================================================
DROP POLICY IF EXISTS "cp_tests_policy" ON public.cp_tests;
CREATE POLICY "cp_tests_policy" ON public.cp_tests
    FOR ALL USING (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND (athlete_user_id = auth.uid() OR coach_id = auth.uid())
    ) WITH CHECK (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND (athlete_user_id = auth.uid() OR coach_id = auth.uid())
    );

DROP POLICY IF EXISTS "cp_values_policy" ON public.cp_values;
CREATE POLICY "cp_values_policy" ON public.cp_values
    FOR ALL USING (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND (athlete_user_id = auth.uid() OR coach_id = auth.uid())
    ) WITH CHECK (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND (athlete_user_id = auth.uid() OR coach_id = auth.uid())
    );

-- ============================================================================
-- سياسات RLS: مواعيد الاختبارات ورسائل المدرب (testing_dates & coach_messages)
-- ============================================================================
DROP POLICY IF EXISTS "testing_dates_policy" ON public.testing_dates;
CREATE POLICY "testing_dates_policy" ON public.testing_dates
    FOR ALL USING (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND (coach_id = auth.uid() OR coach_id = public.get_my_coach_id())
    ) WITH CHECK (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND coach_id = auth.uid()
    );

DROP POLICY IF EXISTS "testing_date_recipients_policy" ON public.testing_date_recipients;
CREATE POLICY "testing_date_recipients_policy" ON public.testing_date_recipients
    FOR ALL USING (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND (athlete_id = auth.uid() OR EXISTS (
            SELECT 1 FROM public.testing_dates td
            WHERE td.id = testing_date_id AND td.coach_id = auth.uid()
        ))
    ) WITH CHECK (
        NOT public.is_admin()
        AND public.is_active_subscriber()
    );

DROP POLICY IF EXISTS "coach_messages_policy" ON public.coach_messages;
CREATE POLICY "coach_messages_policy" ON public.coach_messages
    FOR ALL USING (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND (athlete_id = auth.uid() OR coach_id = auth.uid())
    ) WITH CHECK (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND coach_id = auth.uid()
    );

-- ============================================================================
-- سياسات RLS: إعدادات التقدم ومصفوفة المناطق
-- ============================================================================
DROP POLICY IF EXISTS "progress_baseline_policy" ON public.progress_baseline_config;
CREATE POLICY "progress_baseline_policy" ON public.progress_baseline_config
    FOR ALL USING (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND (owner_id = auth.uid() OR owner_id = public.get_my_coach_id())
    ) WITH CHECK (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND owner_id = auth.uid()
    );

DROP POLICY IF EXISTS "matrix_zone_config_policy" ON public.matrix_zone_config;
CREATE POLICY "matrix_zone_config_policy" ON public.matrix_zone_config
    FOR ALL USING (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND (coach_id = auth.uid() OR coach_id = public.get_my_coach_id())
    ) WITH CHECK (
        NOT public.is_admin()
        AND public.is_active_subscriber()
        AND coach_id = auth.uid()
    );

-- ============================================================================
-- 24. عرض البيانات المشتركة للمنحنيات (shared_curve_data VIEW)
-- يعرض فقط أعمدة المنحنيات للاعبين الذين فعّلوا curves_shared = 1
-- ولزملاء نفس المدرب فقط (تُستخدم في المرحلة س3)
-- ============================================================================
CREATE OR REPLACE VIEW public.shared_curve_data WITH (security_invoker = true) AS
SELECT
    l.player_id,
    l.date,
    l.zone,
    l.kind,
    l.avg_power,
    l.ef,
    l.decoupling,
    l.eupnea_1,
    l.eupnea_2,
    l.eupnea_3,
    l.split_500
FROM public.logs l
JOIN public.players p ON (l.player_id = p.local_id OR l.athlete_user_id = p.athlete_user_id)
WHERE p.curves_shared = 1
  AND p.coach_id = public.get_my_coach_id();
