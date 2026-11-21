import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ════════════════════════ البيانات ════════════════════════

class Q {
  String text;
  String marks;
  String? img; // base64
  Q({this.text = '', this.marks = '20', this.img});

  Map<String, dynamic> toJson() => {'t': text, 'm': marks, 'i': img};

  factory Q.fromJson(Map<String, dynamic> j) => Q(
        text: (j['t'] ?? '').toString(),
        marks: (j['m'] ?? '').toString(),
        img: j['i'] as String?,
      );
}

class Exam {
  bool rtl;
  bool nameLine;
  Map<String, String> h;
  List<Q> qs;

  Exam({
    required this.rtl,
    required this.nameLine,
    required this.h,
    required this.qs,
  });

  static const List<String> keys = [
    'school',
    'title',
    'info',
    'note',
    'closing',
    'sign',
  ];

  factory Exam.sample() => Exam(
        rtl: true,
        nameLine: false,
        h: {
          'school': 'ثانوية زهرة خاتون للبنين',
          'title': 'امتحان الشهر الثاني\nللعام الدراسي 2026-2027',
          'info': 'الصف: الرابع العلمي\nالمادة: الرياضيات\nالوقت: 40 دقيقة',
          'note': '',
          'closing': 'مع تمنياتنا لكم بالنجاح والموفقية',
          'sign': 'مدرس المادة\nعادل محمد',
        },
        qs: [Q()],
      );

  Map<String, dynamic> toJson() => {
        'rtl': rtl,
        'nl': nameLine,
        'h': h,
        'qs': qs.map((q) => q.toJson()).toList(),
      };

  factory Exam.fromJson(Map<String, dynamic> j) {
    final e = Exam.sample();
    e.rtl = j['rtl'] == true;
    e.nameLine = j['nl'] == true;
    final hh = j['h'];
    if (hh is Map) {
      for (final k in Exam.keys) {
        if (hh[k] != null) e.h[k] = hh[k].toString();
      }
    }
    final list = j['qs'];
    if (list is List && list.isNotEmpty) {
      e.qs = list
          .map((x) => Q.fromJson(Map<String, dynamic>.from(x as Map)))
          .toList();
    }
    return e;
  }
}

Exam exam = Exam.sample();
TextEditingController? activeCtrl;

Timer? _saveTimer;

void save() {
  _saveTimer?.cancel();
  _saveTimer = Timer(const Duration(milliseconds: 500), () async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('exam', jsonEncode(exam.toJson()));
    } catch (_) {}
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final p = await SharedPreferences.getInstance();
    final s = p.getString('exam');
    if (s != null) {
      exam = Exam.fromJson(Map<String, dynamic>.from(jsonDecode(s) as Map));
    }
  } catch (_) {
    exam = Exam.sample();
  }
  runApp(const App());
}

// ════════════════════════ الواجهة ════════════════════════

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Exam Maker',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const Editor(),
    );
  }
}

/// حقل نص يسجّل نفسه كحقل فعّال حتى يدخل بي شريط الرموز.
class TF extends StatelessWidget {
  final TextEditingController c;
  final String label;
  final int lines;
  const TF(this.c, this.label, {this.lines = 1, super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Focus(
        onFocusChange: (focused) {
          if (focused) activeCtrl = c;
        },
        child: TextField(
          controller: c,
          minLines: 1,
          maxLines: lines,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ),
    );
  }
}

class Editor extends StatefulWidget {
  const Editor({super.key});

  @override
  State<Editor> createState() => _EditorState();
}

class _EditorState extends State<Editor> {
  final Map<String, TextEditingController> ctrls = {};

  static const Map<String, String> labels = {
    'school': 'اسم المدرسة',
    'title': 'العنوان وسنة الدراسة',
    'info': 'الصف / المادة / الوقت (سطر لكل معلومة)',
    'note': 'ملاحظة داخل مستطيل (اختياري)',
    'closing': 'عبارة الختام',
    'sign': 'التوقيع (مدرس المادة)',
  };

  @override
  void initState() {
    super.initState();
    for (final k in Exam.keys) {
      final c = TextEditingController(text: exam.h[k] ?? '');
      c.addListener(() {
        exam.h[k] = c.text;
        save();
      });
      ctrls[k] = c;
    }
  }

  @override
  void dispose() {
    for (final c in ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void move(int i, int d) {
    final j = i + d;
    if (j < 0 || j >= exam.qs.length) return;
    setState(() {
      final q = exam.qs.removeAt(i);
      exam.qs.insert(j, q);
    });
    save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Exam Maker'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'معاينة / PDF / طباعة',
            onPressed: () {
              FocusScope.of(context).unfocus();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const Preview()),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          setState(() => exam.qs.add(Q()));
          save();
        },
        icon: const Icon(Icons.add),
        label: const Text('سؤال جديد'),
      ),
      bottomNavigationBar: const SymbolBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(exam.rtl
                        ? 'ورقة عربية (من اليمين)'
                        : 'ورقة إنجليزية (من اليسار)'),
                    value: exam.rtl,
                    onChanged: (v) {
                      setState(() => exam.rtl = v);
                      save();
                    },
                  ),
                  for (final k in Exam.keys)
                    TF(
                      ctrls[k]!,
                      labels[k] ?? k,
                      lines: (k == 'title' || k == 'info' || k == 'sign') ? 4 : 2,
                    ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('سطر الاسم والشعبة (منقّط)'),
                    value: exam.nameLine,
                    onChanged: (v) {
                      setState(() => exam.nameLine = v);
                      save();
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (int i = 0; i < exam.qs.length; i++)
            QCard(
              key: ObjectKey(exam.qs[i]),
              q: exam.qs[i],
              index: i,
              onUp: () => move(i, -1),
              onDown: () => move(i, 1),
              onDelete: () {
                setState(() {
                  exam.qs.removeAt(i);
                  if (exam.qs.isEmpty) exam.qs.add(Q());
                });
                save();
              },
            ),
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'نصيحة: السطر اللي يبدي بنجمة (*) يطلع غامق بالورقة. '
              'استخدم الشريط الأسفل لإدخال الرموز.',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}

class QCard extends StatefulWidget {
  final Q q;
  final int index;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onDelete;

  const QCard({
    required this.q,
    required this.index,
    required this.onUp,
    required this.onDown,
    required this.onDelete,
    super.key,
  });

  @override
  State<QCard> createState() => _QCardState();
}

class _QCardState extends State<QCard> {
  late final TextEditingController text;
  late final TextEditingController marks;

  @override
  void initState() {
    super.initState();
    text = TextEditingController(text: widget.q.text);
    text.addListener(() {
      widget.q.text = text.text;
      save();
    });
    marks = TextEditingController(text: widget.q.marks);
    marks.addListener(() {
      widget.q.marks = marks.text;
      save();
    });
  }

  @override
  void dispose() {
    if (identical(activeCtrl, text) || identical(activeCtrl, marks)) {
      activeCtrl = null;
    }
    text.dispose();
    marks.dispose();
    super.dispose();
  }

  Future<void> pickImage() async {
    try {
      final f = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 85,
      );
      if (f == null) return;
      final bytes = await f.readAsBytes();
      if (!mounted) return;
      setState(() => widget.q.img = base64Encode(bytes));
      save();
    } catch (_) {}
  }

  static const Map<String, String> tplAr = {
    'اختيار من متعدد':
        '*اختر الإجابة الصحيحة:\n1- ........ ( أ - ب - ج - د )\n2- ........ ( أ - ب - ج - د )\n3- ........ ( أ - ب - ج - د )',
    'صح أو خطأ':
        '*ضع علامة (✓) أو (✗):\n1- ........ (   )\n2- ........ (   )\n3- ........ (   )',
    'املأ الفراغ':
        '*املأ الفراغات الآتية:\n1- ..............................\n2- ..............................',
    'فرعين (أ، ب)': 'أ: \nب: ',
  };

  static const Map<String, String> tplEn = {
    'Multiple choice':
        '*Choose the correct answer:\n1- ........ ( a - b - c )\n2- ........ ( a - b - c )\n3- ........ ( a - b - c )',
    'True / False':
        '*Write (True) or (False):\n1- ........ (True-False)\n2- ........ (True-False)\n3- ........ (True-False)',
    'Fill the blank':
        '*Write the missing word:\n1- ..............................\n2- ..............................',
    'Parts (a, b)': 'a: \nb: ',
  };

  void addTemplate(String tpl) {
    final t = text.text;
    text.text = t.trim().isEmpty ? tpl : '$t\n$tpl';
    text.selection = TextSelection.collapsed(offset: text.text.length);
  }

  @override
  Widget build(BuildContext context) {
    final img = widget.q.img;
    final tpls = exam.rtl ? tplAr : tplEn;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'السؤال ${widget.index + 1}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Spacer(),
                SizedBox(width: 80, child: TF(marks, 'الدرجة')),
                IconButton(
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: widget.onUp,
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_downward),
                  onPressed: widget.onDown,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: widget.onDelete,
                ),
              ],
            ),
            TF(text, 'نص السؤال', lines: 14),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                PopupMenuButton<String>(
                  onSelected: addTemplate,
                  itemBuilder: (_) => [
                    for (final e in tpls.entries)
                      PopupMenuItem<String>(value: e.value, child: Text(e.key)),
                  ],
                  child: const Chip(
                    avatar: Icon(Icons.view_list_outlined, size: 18),
                    label: Text('قالب جاهز'),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: pickImage,
                  icon: const Icon(Icons.image_outlined),
                  label: Text(img == null ? 'إضافة صورة / شكل' : 'تغيير الصورة'),
                ),
                if (img != null)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      setState(() => widget.q.img = null);
                      save();
                    },
                  ),
              ],
            ),
            if (img != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Image.memory(base64Decode(img), height: 120),
              ),
          ],
        ),
      ),
    );
  }
}

class SymbolBar extends StatelessWidget {
  const SymbolBar({super.key});

  static const List<String> syms = [
    '²', '³', '√', 'π', 'θ', 'α', 'β', 'γ', 'Δ', 'ω', 'μ', 'λ', 'Ω', '°',
    '±', '×', '÷', '≤', '≥', '≠', '≈', '∞', '∑', '∫', '½', '¼', '→', '⇌',
    '↑', '↓', '⁺', '⁻', '₀', '₁', '₂', '₃', '₄', '₅', '⁄', '·', '∠', '⊥',
    '∥', '△',
  ];

  void insert(String s) {
    final c = activeCtrl;
    if (c == null) return;
    final t = c.text;
    final sel = c.selection;
    final st = sel.isValid ? sel.start : t.length;
    final en = sel.isValid ? sel.end : t.length;
    c.value = TextEditingValue(
      text: t.replaceRange(st, en, s),
      selection: TextSelection.collapsed(offset: st + s.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            children: [
              for (final s in syms)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: ActionChip(
                    label: Text(s, style: const TextStyle(fontSize: 18)),
                    onPressed: () => insert(s),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class Preview extends StatelessWidget {
  const Preview({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المعاينة')),
      body: PdfPreview(
        build: (format) => buildPdf(exam),
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        pdfFileName: 'exam.pdf',
      ),
    );
  }
}

// ════════════════════════ ورقة الامتحان (PDF) ════════════════════════

pw.Font? _regular;
pw.Font? _bold;

Future<void> _loadFonts() async {
  if (_regular != null && _bold != null) return;
  final r = await rootBundle.load('assets/fonts/DejaVuSans.ttf');
  final b = await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf');
  _regular = pw.Font.ttf(r);
  _bold = pw.Font.ttf(b);
}

Future<Uint8List> buildPdf(Exam e) async {
  await _loadFonts();
  final theme = pw.ThemeData.withFont(base: _regular!, bold: _bold!);

  final rtl = e.rtl;
  final dir = rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
  final ta = rtl ? pw.TextAlign.right : pw.TextAlign.left;
  const line = pw.BorderSide(width: 0.6);

  pw.Widget t(String s,
      {bool bold = false, double size = 12, pw.TextAlign? al}) {
    return pw.Text(
      s,
      textDirection: dir,
      textAlign: al ?? ta,
      style: pw.TextStyle(
        fontSize: size,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    );
  }

  pw.Widget dots() => pw.Container(
        height: 12,
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(style: pw.BorderStyle.dotted, width: 0.8),
          ),
        ),
      );

  final header = pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Row(
        textDirection: dir,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(child: t(e.h['school'] ?? '', bold: true)),
          pw.Expanded(
            child: t(e.h['title'] ?? '', bold: true, al: pw.TextAlign.center),
          ),
          pw.Expanded(child: t(e.h['info'] ?? '', bold: true)),
        ],
      ),
      pw.Divider(thickness: 2, height: 14, color: PdfColors.black),
      if (e.nameLine)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Row(
            textDirection: dir,
            children: [
              t(rtl ? 'الاسم:' : 'Name:', bold: true),
              pw.SizedBox(width: 6),
              pw.Expanded(flex: 3, child: dots()),
              pw.SizedBox(width: 14),
              t(rtl ? 'الشعبة:' : 'Section:', bold: true),
              pw.SizedBox(width: 6),
              pw.Expanded(child: dots()),
            ],
          ),
        ),
      if ((e.h['note'] ?? '').trim().isNotEmpty)
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 6),
          margin: const pw.EdgeInsets.only(bottom: 6),
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8)),
          child: t(e.h['note'] ?? '', bold: true, al: pw.TextAlign.center),
        ),
    ],
  );

  pw.Widget question(int i, Q q) {
    final label = rtl ? 'س${i + 1}:' : 'Q${i + 1}:';
    final m = q.marks.trim();
    final marks = m.isEmpty ? '' : (rtl ? '($m درجة)' : '($m Marks)');
    final lines = <pw.Widget>[];
    for (final l in q.text.split('\n')) {
      final isBold = l.startsWith('*');
      final s = isBold ? l.substring(1) : l;
      lines.add(t(s.isEmpty ? ' ' : s, bold: isBold));
    }

    pw.Widget? image;
    final b64 = q.img;
    if (b64 != null) {
      image = pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6),
        child: pw.Center(
          child: pw.Image(
            pw.MemoryImage(base64Decode(b64)),
            height: 200,
            fit: pw.BoxFit.contain,
          ),
        ),
      );
    }

    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 4),
      padding: const pw.EdgeInsets.only(top: 6, bottom: 4),
      decoration: const pw.BoxDecoration(border: pw.Border(top: line)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            textDirection: dir,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              t(label, bold: true, size: 13),
              pw.SizedBox(width: 6),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: lines,
                ),
              ),
              pw.SizedBox(width: 8),
              t(marks, bold: true),
            ],
          ),
          if (image != null) image,
        ],
      ),
    );
  }

  final footer = pw.Padding(
    padding: const pw.EdgeInsets.only(top: 26),
    child: pw.Row(
      textDirection: dir,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 2,
          child: t(e.h['closing'] ?? '', bold: true, al: pw.TextAlign.center),
        ),
        pw.Expanded(child: t(e.h['sign'] ?? '', bold: true)),
      ],
    ),
  );

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(38, 36, 38, 36),
        textDirection: dir,
        theme: theme,
        buildBackground: (ctx) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Padding(
            padding: const pw.EdgeInsets.all(16),
            child: pw.Container(
              padding: const pw.EdgeInsets.all(2.5),
              decoration: pw.BoxDecoration(border: pw.Border.all(width: 1.6)),
              child: pw.Container(
                decoration:
                    pw.BoxDecoration(border: pw.Border.all(width: 0.6)),
              ),
            ),
          ),
        ),
      ),
      footer: (ctx) => pw.Center(
        child: pw.Text(
          '${ctx.pageNumber} / ${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 9),
        ),
      ),
      build: (ctx) => [
        header,
        for (int i = 0; i < e.qs.length; i++) question(i, e.qs[i]),
        footer,
      ],
    ),
  );
  return doc.save();
}