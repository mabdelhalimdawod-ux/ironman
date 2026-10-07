import 'package:flutter/material.dart';
import 'db.dart';
import 'player_profile.dart';

const navy = Color(0xFF0D3B66);
const sky = Color(0xFFD6EEFB);
const yellow = Color(0xFFFFC93C);

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'تدريب التجديف',
        builder: (c, w) => Directionality(textDirection: TextDirection.rtl, child: w!),
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: navy, primary: navy, secondary: yellow),
          scaffoldBackgroundColor: Colors.white,
          appBarTheme: const AppBarTheme(
              backgroundColor: navy,
              foregroundColor: Colors.white,
              titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          textTheme: const TextTheme(
              bodyMedium: TextStyle(fontSize: 18), bodyLarge: TextStyle(fontSize: 18)),
          cardTheme: const CardThemeData(
              color: sky, margin: EdgeInsets.symmetric(vertical: 8), elevation: 0),
          filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                  backgroundColor: yellow,
                  foregroundColor: navy,
                  minimumSize: const Size(0, 54),
                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          inputDecorationTheme: const InputDecorationTheme(
              filled: true, fillColor: Colors.white, border: OutlineInputBorder()),
        ),
        home: const Shell(),
      );
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int i = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [const HomePage(), const TodayPage(), const EntryPage(), const Soon('المنحنيات'), const MorePage()];
    return Scaffold(
      body: SafeArea(child: KeyedSubtree(key: ValueKey(i), child: pages[i])),
      bottomNavigationBar: NavigationBar(
        selectedIndex: i,
        indicatorColor: yellow,
        onDestinationSelected: (v) => setState(() => i = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.fitness_center), label: 'اليوم'),
          NavigationDestination(icon: Icon(Icons.edit_note), label: 'تسجيل'),
          NavigationDestination(icon: Icon(Icons.show_chart), label: 'المنحنيات'),
          NavigationDestination(icon: Icon(Icons.menu), label: 'المزيد'),
        ],
      ),
    );
  }
}

Widget page(String title, Widget body, {Widget? fab}) =>
    Scaffold(appBar: AppBar(title: Text(title)), body: body, floatingActionButton: fab);

Widget heading(String t) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 4),
    child: Text(t, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: navy)));

class Soon extends StatelessWidget {
  final String t;
  const Soon(this.t, {super.key});
  @override
  Widget build(BuildContext c) => page(t, const Center(child: Text('تُبنى في المرحلة الثانية')));
}

// ================== الرئيسية (محسّنة) ==================
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Future<Map<String, dynamic>> load() async {
    final d = dstr(DateTime.now());
    final s = await DB.sessions(d);
    final missing = await DB.q(
        'SELECT name FROM players WHERE active=1 AND id NOT IN (SELECT player_id FROM logs WHERE date=?)', [d]);
    final readiness = await DB.allPlayersReadiness();
    return {'d': d, 's': s, 'm': missing, 'r': readiness};
  }

  @override
  Widget build(BuildContext context) => page(
      'الرئيسية',
      FutureBuilder<Map<String, dynamic>>(
          future: load(),
          builder: (c, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final s = snap.data!['s'] as List, m = snap.data!['m'] as List;
            final readiness = snap.data!['r'] as List<Map<String, dynamic>>;
            return ListView(padding: const EdgeInsets.all(16), children: [
              // ---- جاهزية اللاعبين ----
              if (readiness.isNotEmpty) ...[
                heading('🎯 جاهزية اللاعبين'),
                SizedBox(
                  height: 100,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final r in readiness)
                        _readinessChip(context, r),
                    ],
                  ),
                ),
              ],
              // ---- تمرينة اليوم ----
              heading('تمرينة اليوم ${snap.data!['d']}'),
              if (s.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('لا توجد حصص اليوم'))),
              for (final r in s)
                Card(child: ListTile(
                    leading: CircleAvatar(backgroundColor: navy, child: Text('${(r['idx'] as int) + 1}', style: const TextStyle(color: Colors.white))),
                    title: Text('${r['kind']}  •  ${r['zone']}', style: const TextStyle(fontWeight: FontWeight.bold)))),
              // ---- لم يسجلوا ----
              heading('لم يسجلوا اليوم'),
              Card(child: Padding(padding: const EdgeInsets.all(16),
                  child: Text(m.isEmpty ? 'الجميع سجّل ✔' : m.map((e) => e['name']).join('، ')))),
            ]);
          }));

  Widget _readinessChip(BuildContext context, Map<String, dynamic> data) {
    final player = data['player'] as Map<String, Object?>;
    final score = data['readiness'] as double;
    final hasData = data['has_data'] as bool;
    final color = Color(readinessColor(score));

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => Directionality(
              textDirection: TextDirection.rtl,
              child: PlayerProfilePage(player: player),
            ),
          ),
        );
      },
      child: Container(
        width: 80,
        margin: const EdgeInsets.only(left: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 52,
                  height: 52,
                  child: CircularProgressIndicator(
                    value: hasData ? score / 100 : 0,
                    strokeWidth: 4,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation(hasData ? color : Colors.grey),
                  ),
                ),
                CircleAvatar(
                  radius: 20,
                  backgroundColor: hasData ? color.withOpacity(0.15) : Colors.grey.shade100,
                  child: Text(
                    player['name'].toString()[0],
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: hasData ? color : Colors.grey,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${player['name']}',
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (hasData)
              Text(
                '${score.round()}%',
                style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold),
              ),
          ],
        ),
      ),
    );
  }
}

// ================== اليوم ==================
class TodayPage extends StatefulWidget {
  const TodayPage({super.key});
  @override
  State<TodayPage> createState() => _TodayState();
}

class _TodayState extends State<TodayPage> {
  DateTime day = DateTime.now();
  List<Map<String, Object?>> s = [];
  final gen = TextEditingController(), tech = TextEditingController();

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final d = dstr(day);
    s = await DB.sessions(d);
    final n = await DB.q('SELECT * FROM notes WHERE date=?', [d]);
    gen.text = n.isEmpty ? '' : (n[0]['general'] as String? ?? '');
    tech.text = n.isEmpty ? '' : (n[0]['tech'] as String? ?? '');
    setState(() {});
  }

  Future<void> saveNotes() =>
      DB.put('notes', {'date': dstr(day), 'general': gen.text, 'tech': tech.text});

  Future<void> setSession(int idx, String kind, String zone) async {
    await DB.put('sessions', {'date': dstr(day), 'idx': idx, 'kind': kind, 'zone': zone});
    load();
  }

  @override
  Widget build(BuildContext context) => page(
      'اليوم',
      ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: ListTile(
          title: Text(dstr(day), style: const TextStyle(fontWeight: FontWeight.bold)),
          trailing: const Icon(Icons.calendar_month),
          onTap: () async {
            final p = await showDatePicker(context: context, initialDate: day, firstDate: DateTime(2024), lastDate: DateTime(2035));
            if (p != null) { day = p; load(); }
          },
        )),
        heading('الحصص'),
        for (final r in s)
          Card(child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
            Text('${(r['idx'] as int) + 1}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(width: 10),
            Expanded(child: DropdownButtonFormField<String>(
                value: r['kind'] as String, items: [for (final k in kinds) DropdownMenuItem(value: k, child: Text(k))],
                onChanged: (v) => setSession(r['idx'] as int, v!, r['zone'] as String))),
            const SizedBox(width: 8),
            Expanded(child: DropdownButtonFormField<String>(
                value: r['zone'] as String, isExpanded: true,
                items: [for (final z in zones.keys) DropdownMenuItem(value: z, child: Text(z))],
                onChanged: (v) => setSession(r['idx'] as int, r['kind'] as String, v!))),
            IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () async {
              await DB.del('sessions', 'date=? AND idx=?', [dstr(day), r['idx']]);
              load();
            }),
          ]))),
        if (s.length < 4) FilledButton.icon(onPressed: () => setSession(s.length, 'Erg', 'Z2'),
            icon: const Icon(Icons.add), label: const Text('إضافة حصة')),
        heading('البرنامج العام'),
        TextField(controller: gen, maxLines: 3, onChanged: (_) => saveNotes()),
        heading('الملاحظات الفنية والتقنية'),
        TextField(controller: tech, maxLines: 3, onChanged: (_) => saveNotes()),
      ]));
}

// ================== تسجيل اللاعبين (محسّن) ==================
class _Row {
  final Map<String, Object?> p;
  final c = {for (final k in [
    'rhr', 'hrv', 'hr', 'hr_max', 'hr_post', 'hr_1min', 'w', 'fatigue', 'sleep'
  ]) k: TextEditingController()};
  _Row(this.p);
}

class EntryPage extends StatefulWidget {
  const EntryPage({super.key});
  @override
  State<EntryPage> createState() => _EntryState();
}

class _EntryState extends State<EntryPage> {
  final date = dstr(DateTime.now());
  List<Map<String, Object?>> s = [];
  List<_Row> rows = [];
  int idx = 0;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    s = await DB.sessions(date);
    final ps = await DB.q('SELECT * FROM players WHERE active=1 ORDER BY name');
    rows = [for (final p in ps) _Row(p)];
    for (final r in rows) {
      final l = await DB.q('SELECT * FROM logs WHERE player_id=? AND date=? AND idx=?', [r.p['id'], date, idx]);
      if (l.isNotEmpty) {
        r.c['rhr']!.text = '${l[0]['rhr'] ?? ''}';
        r.c['hrv']!.text = '${l[0]['hrv'] ?? ''}';
        r.c['hr']!.text = '${l[0]['hr'] ?? ''}';
        r.c['hr_max']!.text = '${l[0]['hr_max'] ?? ''}';
        r.c['hr_post']!.text = '${l[0]['hr_post'] ?? ''}';
        r.c['hr_1min']!.text = '${l[0]['hr_1min'] ?? ''}';
        r.c['w']!.text = '${l[0]['weight'] ?? ''}';
        r.c['fatigue']!.text = '${l[0]['fatigue'] ?? ''}';
        r.c['sleep']!.text = '${l[0]['sleep_hours'] ?? ''}';
      }
    }
    setState(() {});
  }

  Future<void> save() async {
    for (final r in rows) {
      final hr = int.tryParse(r.c['hr']!.text), mhr = r.p['mhr'] as int;
      // التحقق من منطقية النبض أثناء التمرين
      if (hr != null && (hr < 30 || hr > 230 || hr > mhr + 10)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('نبض غير منطقي للاعب ${r.p['name']}')));
        return;
      }
      // التحقق من منطقية النبض بعد التمرين
      final hrPost = int.tryParse(r.c['hr_post']!.text);
      if (hrPost != null && hr != null && hrPost > hr + 5) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('النبض بعد التمرين أعلى من أثناء التمرين للاعب ${r.p['name']}')));
        return;
      }
      // التحقق من منطقية نبض الاستشفاء
      final hr1min = int.tryParse(r.c['hr_1min']!.text);
      if (hr1min != null && hrPost != null && hr1min > hrPost + 5) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('نبض الاستشفاء (دقيقة) أعلى من النبض بعد التمرين للاعب ${r.p['name']}')));
        return;
      }
      // التحقق من الإرهاق (1-5)
      final fatigue = int.tryParse(r.c['fatigue']!.text);
      if (fatigue != null && (fatigue < 1 || fatigue > 5)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الإرهاق يجب أن يكون من 1 (ممتاز) إلى 5 (مرهق)')));
        return;
      }

      if (r.c.values.every((e) => e.text.isEmpty)) continue;
      await DB.put('logs', {
        'player_id': r.p['id'], 'date': date, 'idx': idx,
        'rhr': int.tryParse(r.c['rhr']!.text),
        'hrv': int.tryParse(r.c['hrv']!.text),
        'hr': hr,
        'hr_max': int.tryParse(r.c['hr_max']!.text),
        'hr_post': hrPost,
        'hr_1min': hr1min,
        'weight': double.tryParse(r.c['w']!.text),
        'fatigue': fatigue,
        'sleep_hours': double.tryParse(r.c['sleep']!.text),
      });
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الحفظ ✔')));
  }

  Widget field(_Row r, String k, String label, {bool dec = false, String? hint}) => Expanded(
      child: Padding(padding: const EdgeInsets.all(3), child: TextField(
          controller: r.c[k], textInputAction: TextInputAction.next,
          keyboardType: TextInputType.numberWithOptions(decimal: dec),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            isDense: true,
          ))));

  Widget sectionLabel(String text, IconData icon, Color color) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 2),
    child: Row(children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 4),
      Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final zone = s.length > idx ? s[idx]['zone'] as String : 'Z2';
    return page('تسجيل اللاعبين', Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: s.isEmpty
          ? const Text('أضف حصص اليوم أولًا من صفحة "اليوم"')
          : DropdownButtonFormField<int>(
              value: idx.clamp(0, s.length - 1),
              items: [for (var i = 0; i < s.length; i++) DropdownMenuItem(value: i, child: Text('حصة ${i + 1}: ${s[i]['kind']} • ${s[i]['zone']}'))],
              onChanged: (v) { idx = v!; load(); })),
      // دليل الإرهاق
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          '📊 الإرهاق: 1=ممتاز  2=جيد  3=مقبول  4=متعب  5=مرهق',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ),
      Expanded(child: rows.isEmpty
          ? const Center(child: Text('أضف لاعبين من "المزيد"'))
          : ListView(padding: const EdgeInsets.symmetric(horizontal: 12), children: [
              for (final r in rows)
                Card(child: Padding(padding: const EdgeInsets.all(10), child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ---- اسم اللاعب والهدف ----
                    Row(children: [
                      Expanded(child: Text('${r.p['name']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20))),
                      Text('هدف: ${hrRange(r.p['mhr'] as int, zone)}',
                          style: const TextStyle(fontSize: 14, color: Colors.grey)),
                    ]),
                    // ---- قبل التدريب ----
                    sectionLabel('قبل التدريب', Icons.bedtime, Colors.indigo),
                    Row(children: [
                      field(r, 'rhr', 'RHR', hint: 'نبض الراحة'),
                      field(r, 'hrv', 'HRV', hint: 'تغير النبض'),
                      field(r, 'sleep', 'النوم', dec: true, hint: 'ساعات'),
                      field(r, 'fatigue', 'إرهاق', hint: '1-5'),
                    ]),
                    // ---- أثناء التدريب ----
                    sectionLabel('أثناء التدريب', Icons.fitness_center, Colors.red.shade700),
                    Row(children: [
                      field(r, 'hr', 'النبض', hint: 'متوسط'),
                      field(r, 'hr_max', 'أقصى نبض', hint: 'أعلى قيمة'),
                    ]),
                    // ---- بعد التدريب ----
                    sectionLabel('بعد التدريب', Icons.favorite_border, Colors.green.shade700),
                    Row(children: [
                      field(r, 'hr_post', 'نبض بعد', hint: 'فورًا'),
                      field(r, 'hr_1min', 'بعد دقيقة', hint: 'استشفاء'),
                      field(r, 'w', 'الوزن', dec: true, hint: 'كجم'),
                    ]),
                  ],
                ))),
            ])),
      Padding(padding: const EdgeInsets.all(12),
          child: SizedBox(width: double.infinity, child: FilledButton(onPressed: save, child: const Text('حفظ')))),
    ]));
  }
}

// ================== المزيد ==================
class MorePage extends StatelessWidget {
  const MorePage({super.key});
  @override
  Widget build(BuildContext context) {
    Widget item(IconData i, String t, Widget p) => Card(child: ListTile(
        leading: Icon(i, color: navy), title: Text(t), trailing: const Icon(Icons.chevron_left),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Directionality(textDirection: TextDirection.rtl, child: p)))));
    return page('المزيد', ListView(padding: const EdgeInsets.all(16), children: [
      item(Icons.groups, 'اللاعبون', const PlayersPage()),
      item(Icons.event, 'الموسم والـ Cycles', const SeasonPage()),
      item(Icons.speed, 'اختبارات الـ Cycle', const Soon('الاختبارات')),
      item(Icons.link, 'المراجع', const Soon('المراجع')),
      item(Icons.cloud_upload, 'النسخ الاحتياطي', const Soon('النسخ الاحتياطي')),
    ]));
  }
}

// ================== اللاعبون (مع الملف الشخصي) ==================
class PlayersPage extends StatefulWidget {
  const PlayersPage({super.key});
  @override
  State<PlayersPage> createState() => _PlayersState();
}

class _PlayersState extends State<PlayersPage> {
  List<Map<String, Object?>> ps = [];
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async { ps = await DB.q('SELECT * FROM players ORDER BY name'); setState(() {}); }

  Future<void> add() async {
    final n = TextEditingController(), m = TextEditingController();
    await showDialog(context: context, builder: (_) => Directionality(textDirection: TextDirection.rtl, child: AlertDialog(
      title: const Text('إضافة لاعب'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: n, decoration: const InputDecoration(labelText: 'الاسم')),
        const SizedBox(height: 10),
        TextField(controller: m, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'MHR')),
      ]),
      actions: [FilledButton(onPressed: () async {
        final mhr = int.tryParse(m.text);
        if (n.text.trim().isEmpty || mhr == null) return;
        await DB.put('players', {'name': n.text.trim(), 'mhr': mhr, 'active': 1});
        if (mounted) Navigator.pop(context);
      }, child: const Text('حفظ'))],
    )));
    load();
  }

  @override
  Widget build(BuildContext context) => page('اللاعبون (${ps.length}/25)',
      ListView(padding: const EdgeInsets.all(16), children: [
        for (final p in ps)
          Card(child: ListTile(
            leading: CircleAvatar(
              backgroundColor: navy,
              child: Text(p['name'].toString()[0], style: const TextStyle(color: Colors.white)),
            ),
            title: Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('MHR ${p['mhr']}  •  ${p['active'] == 1 ? 'نشط ✅' : 'غير نشط ❌'}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // زر الملف الشخصي (التحليلات)
                IconButton(
                  icon: const Icon(Icons.analytics, color: navy),
                  tooltip: 'ملف اللاعب',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Directionality(
                        textDirection: TextDirection.rtl,
                        child: PlayerProfilePage(player: p),
                      ),
                    ),
                  ),
                ),
                // زر تفعيل/تعطيل
                Switch(
                  value: p['active'] == 1,
                  onChanged: (v) async {
                    await DB.put('players', {...p, 'active': v ? 1 : 0});
                    load();
                  },
                ),
              ],
            ),
          )),
      ]),
      fab: ps.length >= 25 ? null : FloatingActionButton.extended(
          backgroundColor: yellow, onPressed: add, icon: const Icon(Icons.add), label: const Text('لاعب جديد')));
}

// ================== الموسم والـ Cycles ==================
class SeasonPage extends StatefulWidget {
  const SeasonPage({super.key});
  @override
  State<SeasonPage> createState() => _SeasonState();
}

class _SeasonState extends State<SeasonPage> {
  List<Map<String, Object?>> cs = [];
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async { cs = await DB.q('SELECT * FROM cycles ORDER BY start'); setState(() {}); }

  Future<void> add() async {
    final n = TextEditingController();
    DateTime a = DateTime.now(), b = DateTime.now().add(const Duration(days: 28));
    await showDialog(context: context, builder: (_) => Directionality(textDirection: TextDirection.rtl,
      child: StatefulBuilder(builder: (c, set) => AlertDialog(
        title: const Text('Cycle جديد'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: n, decoration: const InputDecoration(labelText: 'الاسم')),
          ListTile(title: Text('البداية: ${dstr(a)}'), onTap: () async {
            final p = await showDatePicker(context: c, initialDate: a, firstDate: DateTime(2024), lastDate: DateTime(2035));
            if (p != null) set(() => a = p);
          }),
          ListTile(title: Text('النهاية: ${dstr(b)}'), onTap: () async {
            final p = await showDatePicker(context: c, initialDate: b, firstDate: DateTime(2024), lastDate: DateTime(2035));
            if (p != null) set(() => b = p);
          }),
        ]),
        actions: [FilledButton(onPressed: () async {
          if (n.text.trim().isEmpty) return;
          await DB.put('cycles', {'name': n.text.trim(), 'start': dstr(a), 'end': dstr(b)});
          if (c.mounted) Navigator.pop(c);
        }, child: const Text('حفظ'))],
      ))));
    load();
  }

  @override
  Widget build(BuildContext context) => page('الموسم والـ Cycles',
      ListView(padding: const EdgeInsets.all(16), children: [
        for (final c in cs) Card(child: ListTile(
            title: Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${c['start']}  →  ${c['end']}'),
            trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () async { await DB.del('cycles', 'id=?', [c['id']]); load(); }))),
      ]),
      fab: FloatingActionButton.extended(backgroundColor: yellow, onPressed: add, icon: const Icon(Icons.add), label: const Text('Cycle جديد')));
}
