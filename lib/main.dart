// Fisika Native — app offline UI ala Obsidian (mandiri).
// Tab: Beranda | Teori | Soal | Rumus | Aktivasi
// Freemium: teori full, soal 3/hari saat FREE, trial 7 hari full, PRO via key.
// Konten: assets/content/content.json (hasil export vault, tanpa butuh Obsidian).

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'license_verify.dart';

const String kAppId = 'FIS';
const String kAppName = 'Fisika Native';
const Color kInk = Color(0xFF1A1A1A);
const Color kPaper = Color(0xFFF7F2E8);
const Color kAccent = Color(0xFFB54708);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NativeApp());
}

class ContentItem {
  final String id, title, topic, level, excerpt, body;
  final List<String> visuals;
  final bool proGated;
  ContentItem.fromJson(Map<String, dynamic> j)
      : id = (j['id'] ?? '').toString(),
        title = (j['title'] ?? '').toString(),
        topic = (j['topic'] ?? '').toString(),
        level = (j['level'] ?? '').toString(),
        excerpt = (j['excerpt'] ?? '').toString(),
        body = (j['body'] ?? '').toString(),
        visuals = ((j['visuals'] ?? []) as List).map((e) => e.toString()).toList(),
        proGated = (j['pro_gated'] ?? false) == true;
}

class ContentRepo {
  Map<String, List<ContentItem>> cats = {'teori': [], 'soal': [], 'rumus': [], 'projek': []};
  Future<void> load() async {
    final raw = await rootBundle.loadString('assets/content/content.json');
    final j = json.decode(raw) as Map<String, dynamic>;
    final c = (j['cats'] ?? {}) as Map<String, dynamic>;
    for (final k in cats.keys) {
      final list = (c[k] ?? []) as List;
      cats[k] = list.map((e) => ContentItem.fromJson(e as Map<String, dynamic>)).toList();
    }
  }
}

class NativeApp extends StatelessWidget {
  const NativeApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: kPaper,
        colorScheme: ColorScheme.fromSeed(seedColor: kAccent),
        appBarTheme: const AppBarTheme(backgroundColor: kPaper, foregroundColor: kInk),
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int idx = 0;
  final repo = ContentRepo();
  final store = LicenseStore(kAppId);
  bool loaded = false;
  String tier = 'FREE';
  String note = '';
  int trialLeft = 0;
  String query = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await repo.load();
    await store.ensureFirstRun();
    await _refreshLicense();
    setState(() => loaded = true);
  }

  Future<void> _refreshLicense() async {
    final s = await store.status();
    final left = await store.trialLeftDays();
    setState(() {
      tier = s.$1;
      note = s.$2;
      trialLeft = left;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _Beranda(repo: repo, tier: tier, note: note, trialLeft: trialLeft,
          onOpen: (it) => _openItem(it), onGo: (i) => setState(() => idx = i)),
      _ListPage(title: 'Teori', items: _filter(repo.cats['teori']!), onOpen: _openItem),
      _ListPage(title: 'Soal', items: _filter(repo.cats['soal']!), gated: true,
          onOpen: _openItem, store: store, onChanged: _refreshLicense),
      _ListPage(title: 'Bank Rumus', items: _filter(repo.cats['rumus']!), onOpen: _openItem),
      _Aktivasi(store: store, onChanged: _refreshLicense),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text('$kAppName  •  $tier'),
        actions: [
          if (tier == 'TRIAL') Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Chip(label: Text('Trial $trialLeft hr'), visualDensity: VisualDensity.compact),
          ),
          IconButton(icon: const Icon(Icons.search), onPressed: _askSearch),
        ],
      ),
      body: loaded ? pages[idx] : const Center(child: CircularProgressIndicator()),
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (i) => setState(() => idx = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Beranda'),
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), label: 'Teori'),
          NavigationDestination(icon: Icon(Icons.edit_note_outlined), label: 'Soal'),
          NavigationDestination(icon: Icon(Icons.functions_outlined), label: 'Rumus'),
          NavigationDestination(icon: Icon(Icons.key_outlined), label: 'Aktivasi'),
        ],
      ),
    );
  }

  List<ContentItem> _filter(List<ContentItem> src) {
    if (query.isEmpty) return src;
    final q = query.toLowerCase();
    return src.where((e) =>
        e.title.toLowerCase().contains(q) ||
        e.topic.toLowerCase().contains(q) ||
        e.excerpt.toLowerCase().contains(q)).toList();
  }

  Future<void> _askSearch() async {
    final c = TextEditingController(text: query);
    final v = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cari konsep'),
        content: TextField(controller: c, autofocus: true,
            decoration: const InputDecoration(hintText: 'mis. pythagoras, SPLDV, limit')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('Reset')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Cari')),
        ],
      ),
    );
    if (v != null) setState(() => query = v.trim());
  }

  Future<void> _openItem(ContentItem it) async {
    if (it.proGated) {
      final ok = await store.canOpenSoal();
      if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Batas gratis 3 soal/hari. Trial habis — aktivasi key untuk PRO.')));
        setState(() => idx = 4);
        return;
      }
    }
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => ReaderPage(item: it)));
  }
}

class _Beranda extends StatelessWidget {
  final ContentRepo repo;
  final String tier, note;
  final int trialLeft;
  final void Function(ContentItem) onOpen;
  final void Function(int) onGo;
  const _Beranda({required this.repo, required this.tier, required this.note,
    required this.trialLeft, required this.onOpen, required this.onGo});

  @override
  Widget build(BuildContext context) {
    final teori = repo.cats['teori']!.take(3).toList();
    final soal = repo.cats['soal']!.take(3).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('🏠 HOME — Fisika Native',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('Cari konsep → belajar visual → latihan adaptif → komputasi. '
                  'Mandiri, offline, tanpa install Obsidian.'),
              const SizedBox(height: 8),
              Text(note, style: const TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                FilledButton(onPressed: () => onGo(1), child: const Text('Mulai Teori')),
                OutlinedButton(onPressed: () => onGo(2), child: const Text('Kerjakan Soal')),
                OutlinedButton(onPressed: () => onGo(4), child: const Text('Aktivasi Key')),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        const Text('Mulai di sini (3 klik)', style: TextStyle(fontWeight: FontWeight.bold)),
        ...teori.map((e) => ListTile(
              title: Text(e.title), subtitle: Text('${e.topic} • ${e.level}'),
              trailing: const Icon(Icons.chevron_right), onTap: () => onOpen(e))),
        const Divider(),
        const Text('Latihan hari ini', style: TextStyle(fontWeight: FontWeight.bold)),
        ...soal.map((e) => ListTile(
              title: Text(e.title),
              subtitle: Text('${e.topic} ${e.proGated ? "• PRO" : ""}'),
              trailing: const Icon(Icons.chevron_right), onTap: () => onOpen(e))),
      ],
    );
  }
}

class _ListPage extends StatelessWidget {
  final String title;
  final List<ContentItem> items;
  final bool gated;
  final void Function(ContentItem) onOpen;
  final LicenseStore? store;
  final Future<void> Function()? onChanged;
  const _ListPage({required this.title, required this.items, required this.onOpen,
    this.gated = false, this.store, this.onChanged});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return Center(child: Text('Belum ada $title.'));
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final e = items[i];
        return Card(
          child: ListTile(
            title: Text(e.title),
            subtitle: Text('${e.topic} • ${e.level}\n${e.excerpt}',
                maxLines: 2, overflow: TextOverflow.ellipsis),
            isThreeLine: true,
            trailing: e.proGated ? const Icon(Icons.lock_outline) : const Icon(Icons.chevron_right),
            onTap: () => onOpen(e),
          ),
        );
      },
    );
  }
}

class _Aktivasi extends StatefulWidget {
  final LicenseStore store;
  final Future<void> Function() onChanged;
  const _Aktivasi({required this.store, required this.onChanged});
  @override
  State<_Aktivasi> createState() => _AktivasiState();
}

class _AktivasiState extends State<_Aktivasi> {
  final c = TextEditingController();
  String msg = '';
  String tier = '';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await widget.store.status();
    setState(() {
      tier = s.$1;
      msg = s.$2;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('🔑 Aktivasi', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      Text('Status: $tier\n$msg'),
      const SizedBox(height: 12),
      TextField(controller: c,
          decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Tempel key di sini',
              hintText: 'v1.FIS.PRO.20270922.XXXXXX.XXXXXXXX')),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: () async {
          final r = await widget.store.saveKey(c.text);
          setState(() => msg = r.message);
          await widget.onChanged();
          await _load();
          if (context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(r.message)));
          }
        },
        child: const Text('Aktifkan'),
      ),
      TextButton(
        onPressed: () async {
          await widget.store.clearKey();
          await widget.onChanged();
          await _load();
        },
        child: const Text('Hapus key'),
      ),
      const Divider(),
      const Text('Gratis: teori terbuka, soal 3/hari.\n'
          'Trial 7 hari: semua terbuka otomatis.\n'
          'PRO: soal + pembahasan full + tanpa batas.\n'
          'Key individual per pembeli, ada expiry. Beli via kontak porto.'),
    ]);
  }
}

class ReaderPage extends StatelessWidget {
  final ContentItem item;
  const ReaderPage({super.key, required this.item});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('${item.topic} • ${item.level}',
            style: const TextStyle(color: Colors.black54, fontSize: 12)),
        const SizedBox(height: 8),
        MarkdownBody(data: item.body, selectable: true),
        if (item.visuals.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('Visual interaktif (butuh internet):',
              style: TextStyle(fontWeight: FontWeight.bold)),
          for (final u in item.visuals)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(u, style: const TextStyle(fontSize: 11, color: Colors.blue)),
                SizedBox(
                  height: 320,
                  child: WebViewWidget(
                      controller: WebViewController()
                        ..setJavaScriptMode(JavaScriptMode.unrestricted)
                        ..loadRequest(Uri.parse(u))),
                ),
              ]),
            ),
        ],
      ]),
    );
  }
}
