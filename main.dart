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
        home: const HomePage(),
      );
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
  Widget build(BuildContext c) => page(t, const Center(child: Text('تُبنى في المرحلة القادمة')));
}

// ================== الصفحة الرئيسية (لوحة التحكم) ==================
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Widget _iconCard(BuildContext c, String t, IconData i, Widget p) => InkWell(
        onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => Directionality(textDirection: TextDirection.rtl, child: p))),
        child: Card(
          color: navy,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(i, size: 54, color: yellow),
              const SizedBox(height: 16),
              Text(t, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('تدريب التجديف')),
        body: GridView.count(
          padding: const EdgeInsets.all(24),
          crossAxisCount: 2,
          mainAxisSpacing: 24,
          crossAxisSpacing: 24,
          children: [
            _iconCard(context, 'البرنامج التدريبي', Icons.event_note, const ProgramPage()),
            _iconCard(context, 'المنحنيات', Icons.show_chart, const Soon('المنحنيات والزونات')),
            _iconCard(context, 'اللاعبون', Icons.groups, const PlayersPage()),
            _iconCard(context, 'المواسم و Cycles', Icons.loop, const SeasonPage()),
            _iconCard(context, 'المزيد', Icons.settings, const MorePage()),
          ],
        ),
      );
}

// ================== البرنامج التدريبي (المواعيد والحصص) ==================
class ProgramPage extends StatefulWidget {
  const ProgramPage({super.key});
  @override
  State<ProgramPage> createState() => _ProgramState();
}

class _ProgramState extends State<ProgramPage> {
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
      'البرنامج التدريبي',
      ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: ListTile(
          title: Text('التاريخ: ${dstr(day)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          trailing: const Icon(Icons.calendar_month, color: navy),
          onTap: () async {
            final p = await showDatePicker(context: context, initialDate: day, firstDate: DateTime(2024), lastDate: DateTime(2035));
            if (p != null) { day = p; load(); }
          },
        )),
        const SizedBox(height: 12),
        heading('حصص اليوم (اضغط للتسجيل)'),
        if (s.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('لا توجد حصص، أضف حصة لبدء التدريب.'))),
        for (final r in s)
          Card(
            color: sky,
            child: InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Directionality(textDirection: TextDirection.rtl, child: SessionPlayersPage(date: dstr(day), session: r)))),
              child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
                CircleAvatar(backgroundColor: navy, child: Text('${(r['idx'] as int) + 1}', style: const TextStyle(color: Colors.white))),
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
              ])),
            ),
          ),
        if (s.length < 4) FilledButton.icon(onPressed: () => setSession(s.length, 'Erg', 'Z2'),
            icon: const Icon(Icons.add), label: const Text('إضافة حصة جديدة')),
        heading('ملاحظات اليوم'),
        TextField(controller: gen, maxLines: 2, decoration: const InputDecoration(labelText: 'البرنامج العام'), onChanged: (_) => saveNotes()),
        const SizedBox(height: 8),
        TextField(controller: tech, maxLines: 2, decoration: const InputDecoration(labelText: 'التعليمات الفنية'), onChanged: (_) => saveNotes()),
      ]));
}

// ================== قائمة اللاعبين لتسجيل الحصة ==================
class SessionPlayersPage extends StatefulWidget {
  final String date;
  final Map<String, Object?> session;
  const SessionPlayersPage({super.key, required this.date, required this.session});
  @override
  State<SessionPlayersPage> createState() => _SessionPlayersState();
}

class _SessionPlayersState extends State<SessionPlayersPage> {
  List<Map<String, Object?>> ps = [];
  List<int> loggedPlayerIds = [];

  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    ps = await DB.q('SELECT * FROM players WHERE active=1 ORDER BY name');
    final logs = await DB.q('SELECT player_id FROM logs WHERE date=? AND idx=?', [widget.date, widget.session['idx']]);
    loggedPlayerIds = logs.map((e) => e['player_id'] as int).toList();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => page(
    'الحصة ${(widget.session['idx'] as int) + 1} - ${widget.session['kind']} (${widget.session['zone']})',
    ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (ps.isEmpty) const Text('لا يوجد لاعبين متاحين. أضف لاعبين من الإعدادات.'),
        for (final p in ps)
          Card(
            color: loggedPlayerIds.contains(p['id']) ? Colors.green.shade50 : Colors.white,
            child: ListTile(
              leading: CircleAvatar(backgroundColor: navy, child: Text('${p['name'].toString()[0]}', style: const TextStyle(color: Colors.white))),
              title: Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              subtitle: loggedPlayerIds.contains(p['id']) ? const Text('تم التسجيل ✔', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)) : const Text('لم يسجل بعد', style: TextStyle(color: Colors.red)),
              trailing: const Icon(Icons.edit_note, color: navy),
              onTap: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => Directionality(textDirection: TextDirection.rtl, child: PlayerEntryPage(date: widget.date, session: widget.session, player: p))));
                load(); // Reload to update tick mark
              },
            ),
          )
      ]
    )
  );
}

// ================== نموذج التسجيل الفردي (الماستر-ديتيل) ==================
class _Row {
  final Map<String, Object?> p;
  final c = {for (final k in [
    'rhr', 'hrv', 'hr', 'hr_max', 'hr_post', 'hr_1min', 'w', 'fatigue', 'sleep',
    'avg_power', 'max_power', 'distance', 'split', 'ef'
  ]) k: TextEditingController()};
  _Row(this.p);
}

class PlayerEntryPage extends StatefulWidget {
  final String date;
  final Map<String, Object?> session;
  final Map<String, Object?> player;
  const PlayerEntryPage({super.key, required this.date, required this.session, required this.player});
  @override
  State<PlayerEntryPage> createState() => _PlayerEntryState();
}

class _PlayerEntryState extends State<PlayerEntryPage> {
  late _Row r;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    r = _Row(widget.player);
    load();
  }

  Future<void> load() async {
    final l = await DB.q('SELECT * FROM logs WHERE player_id=? AND date=? AND idx=?', [widget.player['id'], widget.date, widget.session['idx']]);
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
        r.c['avg_power']!.text = '${l[0]['avg_power'] ?? ''}';
        r.c['max_power']!.text = '${l[0]['max_power'] ?? ''}';
        r.c['distance']!.text = '${l[0]['distance'] ?? ''}';
        r.c['split']!.text = '${l[0]['split_500'] ?? ''}';
        r.c['ef']!.text = '${l[0]['ef'] ?? ''}';
    }
    setState(() => loading = false);
  }

  Future<void> save() async {
      final hr = int.tryParse(r.c['hr']!.text), mhr = r.p['mhr'] as int;
      if (hr != null && (hr < 30 || hr > 230 || hr > mhr + 10)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('نبض غير منطقي للاعب ${r.p['name']}')));
        return;
      }
      final hrPost = int.tryParse(r.c['hr_post']!.text);
      if (hrPost != null && hr != null && hrPost > hr + 5) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('النبض بعد التمرين أعلى من أثناء التمرين')));
        return;
      }
      final hr1min = int.tryParse(r.c['hr_1min']!.text);
      if (hr1min != null && hrPost != null && hr1min > hrPost + 5) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('نبض الاستشفاء (دقيقة) أعلى من النبض بعد التمرين')));
        return;
      }
      final fatigue = int.tryParse(r.c['fatigue']!.text);
      if (fatigue != null && (fatigue < 1 || fatigue > 5)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الإرهاق يجب أن يكون من 1 (ممتاز) إلى 5 (مرهق)')));
        return;
      }

      final avgPower = double.tryParse(r.c['avg_power']!.text);
      final maxPower = double.tryParse(r.c['max_power']!.text);
      if (avgPower != null && avgPower < 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('متوسط الواط غير منطقي')));
        return;
      }
      if (maxPower != null && avgPower != null && maxPower < avgPower) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أقصى واط أقل من المتوسط')));
        return;
      }
      
      final distance = int.tryParse(r.c['distance']!.text);
      if (distance != null && distance <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('مسافة غير منطقية')));
        return;
      }

      final ef = double.tryParse(r.c['ef']!.text);
      if (ef != null && ef < 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('معدل الـ EF غير منطقي')));
        return;
      }

      if (!r.c.values.every((e) => e.text.isEmpty)) {
        await DB.put('logs', {
          'player_id': r.p['id'], 'date': widget.date, 'idx': widget.session['idx'],
          'rhr': int.tryParse(r.c['rhr']!.text),
          'hrv': int.tryParse(r.c['hrv']!.text),
          'hr': hr,
          'hr_max': int.tryParse(r.c['hr_max']!.text),
          'hr_post': hrPost,
          'hr_1min': hr1min,
          'weight': double.tryParse(r.c['w']!.text),
          'fatigue': fatigue,
          'sleep_hours': double.tryParse(r.c['sleep']!.text),
          'avg_power': avgPower,
          'max_power': maxPower,
          'distance': distance,
          'split_500': double.tryParse(r.c['split']!.text),
          'ef': ef,
        });
      }
      
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ البيانات ✔')));
         Navigator.pop(context);
      }
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
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Row(children: [
      Icon(icon, size: 20, color: color),
      const SizedBox(width: 8),
      Text(text, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    if (loading) return page('تسجيل البيانات', const Center(child: CircularProgressIndicator()));
    final zone = widget.session['zone'] as String;
    
    return Scaffold(
      appBar: AppBar(title: Text('بيانات ${widget.player['name']}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: navy,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('التمرين: ${widget.session['kind']}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('الزون المستهدف: $zone', style: const TextStyle(color: yellow, fontSize: 16)),
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('النبض الأقصى: ${widget.player['mhr']}', style: const TextStyle(color: Colors.white)),
                  Text('نبض التمرينة: ${hrRange(widget.player['mhr'] as int, zone)}', style: const TextStyle(color: Colors.white70)),
                ]),
              ]),
            ),
          ),
          
          sectionLabel('قبل التدريب (المؤشرات الصباحية)', Icons.bedtime, Colors.indigo),
          Row(children: [
            field(r, 'rhr', 'RHR', hint: 'نبض الراحة'),
            field(r, 'hrv', 'HRV', hint: 'تغير النبض'),
          ]),
          Row(children: [
            field(r, 'sleep', 'النوم', dec: true, hint: 'ساعات'),
            field(r, 'fatigue', 'إرهاق', hint: '1-5'),
          ]),

          sectionLabel('أثناء التدريب (الأداء والنبض)', Icons.fitness_center, Colors.red.shade700),
          Row(children: [
            field(r, 'hr', 'النبض', hint: 'متوسط'),
            field(r, 'hr_max', 'أقصى نبض', hint: 'أعلى قيمة'),
          ]),
          Row(children: [
            field(r, 'avg_power', 'الواط', dec: true, hint: 'متوسط'),
            field(r, 'max_power', 'أقصى واط', dec: true, hint: 'أقصى'),
            field(r, 'distance', 'المسافة', hint: 'متر'),
          ]),
          Row(children: [
            field(r, 'split', 'الاسبليت', dec: true, hint: 'ث/500م'),
            field(r, 'ef', 'EF', dec: true, hint: 'الكفاءة'),
          ]),

          sectionLabel('بعد التدريب (الاستشفاء)', Icons.favorite_border, Colors.green.shade700),
          Row(children: [
            field(r, 'hr_post', 'نبض بعد', hint: 'فورًا'),
            field(r, 'hr_1min', 'بعد دقيقة', hint: 'استشفاء'),
            field(r, 'w', 'الوزن', dec: true, hint: 'كجم'),
          ]),
          
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: save, 
            icon: const Icon(Icons.save), 
            label: const Text('حفظ البيانات والعودة')
          ),
          const SizedBox(height: 24),
        ],
      )
    );
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
    return page('المزيد والإعدادات', ListView(padding: const EdgeInsets.all(16), children: [
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
