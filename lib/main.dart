import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'dart:async';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'data/card_collections.dart';

void main() {
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const DrinkingGameApp());
}

// ── Palette ──────────────────────────────────────────────────────────────────
class _P {
  static const bg       = Color(0xFF09090E);
  static const surface  = Color(0xFF12121A);
  static const card     = Color(0xFF0E0E18);
  static const gold     = Color(0xFFD4AF6A);
  static const goldDim  = Color(0xFF9B7D44);
  static const goldGlow = Color(0x40D4AF6A);
  static const cream    = Color(0xFFF0E6D0);
  static const muted    = Color(0xFF5A5470);
  static const white    = Color(0xFFFFFFFF);
  static const red      = Color(0xFFB94040);
}

// ── Text Styles ───────────────────────────────────────────────────────────────
class _T {
  static const display = TextStyle(
    fontFamily: 'Georgia',
    fontSize: 15,
    letterSpacing: 3,
    color: _P.gold,
    fontWeight: FontWeight.w400,
  );
  static const cardText = TextStyle(
    fontFamily: 'Georgia',
    fontSize: 22,
    height: 1.55,
    color: _P.cream,
    fontWeight: FontWeight.w400,
  );
  static const label = TextStyle(
    fontSize: 11,
    letterSpacing: 2.5,
    color: _P.muted,
    fontWeight: FontWeight.w600,
  );
  static const button = TextStyle(
    fontSize: 12,
    letterSpacing: 2,
    color: _P.gold,
    fontWeight: FontWeight.w600,
  );
}

// ── App ───────────────────────────────────────────────────────────────────────
class DrinkingGameApp extends StatelessWidget {
  const DrinkingGameApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MUUNU',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: _P.bg,
        useMaterial3: true,
        fontFamily: 'Georgia',
      ),
      home: const GameScreen(),
    );
  }
}

// ── Game Screen ───────────────────────────────────────────────────────────────
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with TickerProviderStateMixin {

  List<CardCollection> collections = List.from(defaultCollections);
  CardCollection? currentCollection;
  List<String> get currentCards => currentCollection?.cards ?? [];
  String currentCard = '';
  final Random _random = Random();
  final String _storageKey = 'saved_collections';
  bool _isSwiping = false;
  bool _hasStarted = false;

  // Timer
  int _timerSeconds = 10;
  int _remainingSeconds = 0;
  bool _isTimerActive = false;
  late Timer _ticker;

  // Animations
  late AnimationController _flipController;
  late AnimationController _shimmerController;
  late AnimationController _pulseController;
  late Animation<double> _flipAnim;
  late Animation<double> _shimmerAnim;
  late Animation<double> _pulseAnim;

  bool _showFront = true;

  @override
  void initState() {
    super.initState();

    // ── FIX #1: 1100 ms + easeInOutQuart ──────────────────────────────────
    // The previous 600–900 ms with easeInOutCubic felt too snappy on 120 Hz
    // displays (S22 Ultra) because the linear "middle" portion of the cubic
    // curve plays through twice as many frames.  easeInOutQuart has a much
    // wider ease-in/ease-out region, so the flip spends more frames
    // decelerating and accelerating — making it feel weighted on any Hz.
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _flipAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOutQuart),
    );

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _shimmerAnim = Tween<double>(begin: -1, end: 2).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _ticker = Timer.periodic(const Duration(seconds: 1), _onTick);
    _loadCollections();
  }

  @override
  void dispose() {
    _flipController.dispose();
    _shimmerController.dispose();
    _pulseController.dispose();
    _ticker.cancel();
    super.dispose();
  }

  void _onTick(Timer t) {
    if (_isTimerActive && _remainingSeconds > 0) {
      setState(() => _remainingSeconds--);
    } else if (_isTimerActive && _remainingSeconds <= 0) {
      setState(() => _isTimerActive = false);
    }
  }

  void _startTimer() {
    setState(() {
      _remainingSeconds = _timerSeconds;
      _isTimerActive = true;
    });
  }

  SharedPreferences? _prefs;

  Future<void> _loadCollections() async {
    _prefs ??= await SharedPreferences.getInstance();
    final saved = _prefs!.getString(_storageKey);
    if (saved != null) {
      final decoded = json.decode(saved) as List<dynamic>;
      setState(() {
        collections = decoded.map((item) => CardCollection(
          id: item['id'],
          name: item['name'],
          cards: (item['cards'] as List<dynamic>).cast<String>(),
          isDefault: item['isDefault'] ?? false,
        )).toList();
      });
    } else {
      setState(() { collections = List.from(defaultCollections); });
    }
    if (currentCollection == null && collections.isNotEmpty) {
      setState(() { currentCollection = collections.first; });
    }
  }

  Future<void> _saveCollections() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      json.encode(collections.map((c) => c.toJson()).toList()),
    );
  }

  // ── Card flip & shuffle ───────────────────────────────────────────────────
  void _drawCard() {
    if (_isSwiping || currentCards.isEmpty) return;
    _isSwiping = true;
    HapticFeedback.mediumImpact();

    _flipController.forward().then((_) {
      setState(() {
        _showFront = false;
        currentCard = currentCards[_random.nextInt(currentCards.length)];
        _hasStarted = true;
      });
      _flipController.reverse().then((_) {
        setState(() => _showFront = true);
        _startTimer();
        Future.delayed(const Duration(milliseconds: 400), () {
          _isSwiping = false;
        });
      });
    });
  }

  // ── Collection management ─────────────────────────────────────────────────
  void addNewCard(String text) {
    if (currentCollection == null) return;
    setState(() {
      final idx = collections.indexWhere((c) => c.id == currentCollection!.id);
      if (idx != -1) {
        final updated = CardCollection(
          id: currentCollection!.id,
          name: currentCollection!.name,
          cards: [...currentCollection!.cards, text.trim()],
          isDefault: currentCollection!.isDefault,
        );
        collections[idx] = updated;
        currentCollection = updated;
        _saveCollections();
      }
    });
  }

  void updateCard(int idx, String newText) {
    if (currentCollection == null) return;
    setState(() {
      final ci = collections.indexWhere((c) => c.id == currentCollection!.id);
      if (ci != -1) {
        final cards = List<String>.from(currentCollection!.cards);
        cards[idx] = newText.trim();
        final updated = CardCollection(
          id: currentCollection!.id, name: currentCollection!.name,
          cards: cards, isDefault: currentCollection!.isDefault,
        );
        collections[ci] = updated;
        currentCollection = updated;
        _saveCollections();
      }
    });
  }

  void deleteCard(int idx) {
    if (currentCollection == null) return;
    setState(() {
      final ci = collections.indexWhere((c) => c.id == currentCollection!.id);
      if (ci != -1) {
        final cards = List<String>.from(currentCollection!.cards);
        final removed = cards.removeAt(idx);
        final updated = CardCollection(
          id: currentCollection!.id, name: currentCollection!.name,
          cards: cards, isDefault: currentCollection!.isDefault,
        );
        collections[ci] = updated;
        currentCollection = updated;
        if (currentCard == removed) {
          currentCard = cards.isNotEmpty ? cards[_random.nextInt(cards.length)] : '';
        }
        _saveCollections();
      }
    });
  }

  void addNewCollection(String name) {
    setState(() {
      final c = CardCollection(
        name: name, cards: [],
        id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      );
      collections.add(c);
      currentCollection = c;
      _saveCollections();
    });
  }

  void _selectCollection(CardCollection col) {
    setState(() {
      currentCollection = col;
      _hasStarted = false;
      currentCard = '';
      _isTimerActive = false;
    });
    Navigator.of(context).pop();
  }

  // ── Export ────────────────────────────────────────────────────────────────
  // Writes a temp .json file then opens the OS share sheet.
  // Android: user can save to Downloads, share via Telegram/WhatsApp, etc.
  Future<void> _exportCollection(CardCollection col) async {
    await _shareJson(
      json.encode([col.toJson()]),   // always an array for import symmetry
      '${_safeFilename(col.name)}.json',
    );
  }

  Future<void> _exportAllCollections() async {
    await _shareJson(
      json.encode(collections.map((c) => c.toJson()).toList()),
      'muunu_all_collections.json',
    );
  }

  Future<void> _shareJson(String payload, String filename) async {
    try {
      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsString(payload, flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        subject: filename,
      );
    } catch (e) {
      _showSnack('Export failed: $e', isError: true);
    }
  }

  String _safeFilename(String name) =>
      name.replaceAll(RegExp(r'[^\w\s-]'), '').trim().replaceAll(' ', '_');

  // ── Import ────────────────────────────────────────────────────────────────
  // Opens the system file picker filtered to .json, reads the file, merges.
  Future<void> _importFromFile(BuildContext ctx) async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        allowMultiple: false,
      );
    } catch (_) {
      _showSnack('Could not open file picker', isError: true);
      return;
    }

    if (result == null || result.files.isEmpty) return;

    final pf = result.files.first;
    String raw;
    try {
      if (pf.bytes != null) {
        // Web / some Android versions return bytes directly
        raw = utf8.decode(pf.bytes!);
      } else if (pf.path != null) {
        raw = await File(pf.path!).readAsString();
      } else {
        _showSnack('Cannot read file', isError: true);
        return;
      }
    } catch (_) {
      _showSnack('Failed to read file', isError: true);
      return;
    }

    _parseAndImport(raw.trim());
  }

  void _parseAndImport(String raw) {
    if (raw.isEmpty) return;
    try {
      final decoded = json.decode(raw);
      final List<dynamic> items = decoded is List ? decoded : [decoded];
      int imported = 0;
      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;
        final name  = (item['name'] as String?) ?? 'Imported';
        final cards = (item['cards'] as List<dynamic>?)?.cast<String>() ?? [];
        final newId = 'import_${DateTime.now().millisecondsSinceEpoch}_$imported';
        final exists = collections.any((c) => c.name == name);
        final c = CardCollection(
          id: newId,
          name: exists ? '$name (import)' : name,
          cards: cards,
          isDefault: false,
        );
        setState(() {
          collections.add(c);
          currentCollection = c;
        });
        imported++;
      }
      _saveCollections();
      _showSnack('Imported $imported collection${imported == 1 ? '' : 's'}');
    } catch (_) {
      _showSnack('Invalid JSON — check your file', isError: true);
    }
  }

  // ── Snack helper ──────────────────────────────────────────────────────────
  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: _P.surface,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isError ? _P.red.withOpacity(0.5) : _P.gold.withOpacity(0.3),
        ),
      ),
      content: Row(children: [
        Icon(
          isError ? Icons.error_outline : Icons.check_circle_outline,
          color: isError ? _P.red : _P.gold,
          size: 16,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: const TextStyle(
          color: _P.cream, fontFamily: 'Georgia', fontSize: 13,
        ))),
      ]),
      duration: const Duration(seconds: 3),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: _P.bg,
      body: Stack(
        children: [
          _buildBg(),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: GestureDetector(
                    onTap: _drawCard,
                    onHorizontalDragEnd: (d) {
                      if ((d.velocity.pixelsPerSecond.dx).abs() > 200) _drawCard();
                    },
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildTimerRow(),
                          const SizedBox(height: 24),
                          _buildFlipCard(sw),
                          const SizedBox(height: 32),
                          _buildDrawButton(),
                          const SizedBox(height: 16),
                          _buildHint(),
                        ],
                      ),
                    ),
                  ),
                ),
                _buildBottomBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Background ────────────────────────────────────────────────────────────
  Widget _buildBg() => CustomPaint(size: Size.infinite, painter: _BgPainter());

  // ── Top bar ───────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 0),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('MUUNU', style: TextStyle(
                fontFamily: 'Georgia', fontSize: 22,
                letterSpacing: 6, color: _P.gold, fontWeight: FontWeight.w400,
              )),
              if (currentCollection != null)
                Text(currentCollection!.name.toUpperCase(),
                  style: _T.label.copyWith(fontSize: 9)),
            ],
          ),
          const Spacer(),
          _topIconButton(
            icon: _isTimerActive ? Icons.timer : Icons.timer_outlined,
            color: _isTimerActive ? _P.gold : _P.muted,
            onTap: () => _showTimerSheet(context),
          ),
          _topIconButton(icon: Icons.view_list_rounded,
            onTap: () => _showAllCards(context)),
          _topIconButton(icon: Icons.layers_outlined,
            onTap: () => _showCollectionSelector(context)),
        ],
      ),
    );
  }

  Widget _topIconButton({
    required IconData icon,
    Color color = _P.muted,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        margin: const EdgeInsets.only(left: 4),
        decoration: BoxDecoration(
          color: _P.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _P.gold.withOpacity(0.15)),
        ),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }

  // ── Timer row ─────────────────────────────────────────────────────────────
  Widget _buildTimerRow() {
    if (!_isTimerActive && !_hasStarted) return const SizedBox(height: 40);

    if (_isTimerActive) {
      final progress = _remainingSeconds / _timerSeconds;
      return Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 120,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(height: 2, color: _P.muted.withOpacity(0.3)),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 900),
                    height: 2,
                    width: 120 * progress,
                    color: progress > 0.4 ? _P.gold : _P.red,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text('$_remainingSeconds', style: TextStyle(
              fontFamily: 'Georgia', fontSize: 20,
              color: progress > 0.4 ? _P.gold : _P.red,
              fontWeight: FontWeight.w400,
            )),
            const SizedBox(width: 4),
            Text('SEC', style: _T.label),
          ],
        ),
      );
    }

    return Container(
      height: 40, alignment: Alignment.center,
      child: Text('TAP CARD TO DRAW', style: _T.label),
    );
  }

  // ── Flip Card ─────────────────────────────────────────────────────────────
  Widget _buildFlipCard(double sw) {
    final cardW = sw * 0.82;
    final cardH = cardW * 1.42;

    return AnimatedBuilder(
      animation: _flipAnim,
      builder: (context, child) {
        final angle   = _flipAnim.value * pi;
        final isFront = angle < pi / 2;

        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.002)
            ..rotateY(angle),
          child: isFront
              ? _buildCardFront(cardW, cardH)
              : Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateY(pi),
                  child: _buildCardBack(cardW, cardH),
                ),
        );
      },
    );
  }

  Widget _buildCardFront(double w, double h) {
    return Container(
      width: w, height: h,
      decoration: BoxDecoration(
        color: _P.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _P.gold.withOpacity(0.35), width: 1),
        boxShadow: [
          BoxShadow(color: _P.goldGlow, blurRadius: 30, spreadRadius: -4),
          BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 20),
        ],
      ),
      child: Stack(
        children: [
          ..._cornerOrnaments(),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _P.gold.withOpacity(0.12), width: 1),
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _shimmerAnim,
            builder: (_, __) => ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Opacity(
                opacity: 0.04,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(_shimmerAnim.value - 1, -1),
                      end: Alignment(_shimmerAnim.value, 1),
                      colors: const [Colors.transparent, _P.gold, Colors.transparent],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
              child: _hasStarted && currentCard.isNotEmpty
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _goldDivider(),
                        const SizedBox(height: 28),
                        Text(currentCard, style: _T.cardText, textAlign: TextAlign.center),
                        const SizedBox(height: 28),
                        _goldDivider(),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedBuilder(
                          animation: _pulseAnim,
                          builder: (_, __) => Opacity(
                            opacity: _pulseAnim.value,
                            child: const Icon(Icons.auto_awesome, color: _P.gold, size: 36),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text('TAP TO\nDRAW', style: _T.display.copyWith(
                          fontSize: 18, letterSpacing: 6, height: 1.6,
                        ), textAlign: TextAlign.center),
                      ],
                    ),
            ),
          ),
          if (currentCollection != null)
            Positioned(
              bottom: 22, left: 0, right: 0,
              child: Center(
                child: Text(currentCollection!.name.toUpperCase(),
                  style: _T.label.copyWith(fontSize: 8, letterSpacing: 2)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCardBack(double w, double h) {
    return Container(
      width: w, height: h,
      decoration: BoxDecoration(
        color: _P.gold.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _P.gold.withOpacity(0.4), width: 1),
      ),
      child: const Center(
        child: Icon(Icons.auto_awesome, color: _P.gold, size: 40),
      ),
    );
  }

  List<Widget> _cornerOrnaments() {
    const size = 24.0;
    const pad  = 16.0;
    final Widget o = SizedBox(width: size, height: size,
        child: CustomPaint(painter: _CornerPainter()));
    return [
      Positioned(top: pad, left: pad, child: o),
      Positioned(top: pad, right: pad,
        child: Transform.rotate(angle: pi / 2, child: o)),
      Positioned(bottom: pad, left: pad,
        child: Transform.rotate(angle: -pi / 2, child: o)),
      Positioned(bottom: pad, right: pad,
        child: Transform.rotate(angle: pi, child: o)),
    ];
  }

  Widget _goldDivider() => Row(children: [
    Expanded(child: Container(height: 0.5, color: _P.goldDim.withOpacity(0.4))),
    const Padding(
      padding: EdgeInsets.symmetric(horizontal: 10),
      child: Icon(Icons.diamond_outlined, size: 10, color: _P.goldDim),
    ),
    Expanded(child: Container(height: 0.5, color: _P.goldDim.withOpacity(0.4))),
  ]);

  // ── Draw button ───────────────────────────────────────────────────────────
  Widget _buildDrawButton() {
    return GestureDetector(
      onTap: _drawCard,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 14),
        decoration: BoxDecoration(
          color: _P.gold,
          borderRadius: BorderRadius.circular(40),
          boxShadow: [BoxShadow(color: _P.goldGlow, blurRadius: 20, spreadRadius: 2)],
        ),
        child: Text(
          _hasStarted ? 'DRAW AGAIN' : 'DRAW CARD',
          style: const TextStyle(
            fontFamily: 'Georgia', fontSize: 13,
            letterSpacing: 3, color: _P.bg, fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildHint() =>
      Text('SWIPE OR TAP TO SHUFFLE', style: _T.label.copyWith(fontSize: 9));

  // ── Bottom bar ────────────────────────────────────────────────────────────
  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: _P.gold.withOpacity(0.1))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('${currentCards.length} CARDS', style: _T.label),
          Container(width: 6, height: 6,
            decoration: const BoxDecoration(color: _P.gold, shape: BoxShape.circle)),
          Text('$_timerSeconds SEC TIMER', style: _T.label),
        ],
      ),
    );
  }

  // ── Timer sheet ───────────────────────────────────────────────────────────
  void _showTimerSheet(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: _P.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('TIMER DURATION', style: _T.label),
            const SizedBox(height: 20),
            ...[5, 10, 15, 30].map(_timerOption),
          ],
        ),
      ),
    );
  }

  Widget _timerOption(int sec) {
    final selected = _timerSeconds == sec;
    return GestureDetector(
      onTap: () { setState(() => _timerSeconds = sec); Navigator.pop(context); },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? _P.gold.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? _P.gold : _P.muted.withOpacity(0.3)),
        ),
        child: Row(children: [
          Text('$sec seconds', style: TextStyle(
            color: selected ? _P.gold : _P.cream,
            fontFamily: 'Georgia', fontSize: 16,
          )),
          const Spacer(),
          if (selected) const Icon(Icons.check, color: _P.gold, size: 18),
        ]),
      ),
    );
  }

  // ── All cards sheet ───────────────────────────────────────────────────────
  Future<void> _showAllCards(BuildContext ctx) async {
    if (currentCollection == null) return;
    await showModalBottomSheet<void>(
      context: ctx,
      backgroundColor: _P.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.85,
        child: Column(children: [
          Container(margin: const EdgeInsets.only(top: 14), width: 36, height: 3,
            decoration: BoxDecoration(color: _P.muted,
              borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('ALL CARDS', style: _T.label),
                const SizedBox(height: 4),
                Text(currentCollection!.name, style: const TextStyle(
                  fontFamily: 'Georgia', fontSize: 20, color: _P.cream)),
              ]),
              const Spacer(),
              _sheetButton('ADD', Icons.add, onTap: () {
                Navigator.pop(context);
                _showAddCardDialog(ctx);
              }),
            ]),
          ),
          const SizedBox(height: 16),
          Container(height: 0.5, color: _P.gold.withOpacity(0.2)),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: currentCollection!.cards.length,
              itemBuilder: (_, i) {
                final card      = currentCollection!.cards[i];
                final isCurrent = currentCard == card;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                  decoration: BoxDecoration(
                    color: isCurrent ? _P.gold.withOpacity(0.08) : _P.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isCurrent
                        ? _P.gold.withOpacity(0.5) : _P.muted.withOpacity(0.2)),
                  ),
                  child: Row(children: [
                    Text('${i + 1}', style: _T.label.copyWith(fontSize: 10)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(card, style: const TextStyle(
                      color: _P.cream, fontFamily: 'Georgia',
                      fontSize: 14, height: 1.4))),
                    PopupMenuButton<String>(
                      color: _P.surface,
                      icon: Icon(Icons.more_vert, color: _P.muted, size: 18),
                      onSelected: (v) {
                        if (v == 'edit')   _showEditCardDialog(ctx, i, card);
                        else if (v == 'delete') _showDeleteCardDialog(ctx, i, card);
                        else if (v == 'pick') {
                          setState(() => currentCard = card);
                          Navigator.pop(context);
                        }
                      },
                      itemBuilder: (_) => [
                        _menuItem('pick',   Icons.star_outline,   'Set Current'),
                        _menuItem('edit',   Icons.edit_outlined,  'Edit'),
                        _menuItem('delete', Icons.delete_outline, 'Delete', color: _P.red),
                      ],
                    ),
                  ]),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  // ── Collection selector sheet ─────────────────────────────────────────────
  Future<void> _showCollectionSelector(BuildContext ctx) async {
    return showModalBottomSheet(
      context: ctx,
      backgroundColor: _P.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.72,
        child: Column(children: [
          Container(margin: const EdgeInsets.only(top: 14), width: 36, height: 3,
            decoration: BoxDecoration(color: _P.muted,
              borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('COLLECTIONS', style: _T.label),
                const SizedBox(height: 2),
                const Text('Choose a deck', style: TextStyle(
                  color: _P.cream, fontFamily: 'Georgia', fontSize: 18)),
              ]),
              const Spacer(),
              // ── IMPORT button ──────────────────────────────────────────
              _sheetButton('IMPORT', Icons.file_download_outlined, onTap: () {
                Navigator.pop(context);
                _importFromFile(ctx);
              }),
              const SizedBox(width: 8),
              _sheetButton('NEW', Icons.add, onTap: () {
                Navigator.pop(context);
                _showAddCollectionDialog(ctx);
              }),
            ]),
          ),
          const SizedBox(height: 16),
          Container(height: 0.5, color: _P.gold.withOpacity(0.2)),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: collections.length,
              itemBuilder: (_, i) {
                final col      = collections[i];
                final selected = currentCollection?.id == col.id;
                return GestureDetector(
                  onTap: () => _selectCollection(col),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                    decoration: BoxDecoration(
                      color: selected ? _P.gold.withOpacity(0.08) : _P.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                          ? _P.gold.withOpacity(0.5) : _P.muted.withOpacity(0.2)),
                    ),
                    child: Row(children: [
                      Icon(Icons.layers_outlined,
                        color: selected ? _P.gold : _P.muted, size: 18),
                      const SizedBox(width: 14),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(col.name, style: TextStyle(
                            color: selected ? _P.gold : _P.cream,
                            fontFamily: 'Georgia', fontSize: 15)),
                          Text('${col.cards.length} cards',
                            style: _T.label.copyWith(fontSize: 9)),
                        ],
                      )),
                      // ── EXPORT single collection ───────────────────────
                      GestureDetector(
                        onTap: () => _exportCollection(col),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Icon(Icons.file_upload_outlined,
                            color: _P.muted, size: 16),
                        ),
                      ),
                      if (!col.isDefault)
                        GestureDetector(
                          onTap: () => _deleteCollection(col, ctx),
                          child: Icon(Icons.close, color: _P.muted, size: 16),
                        ),
                      if (selected)
                        const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Icon(Icons.check, color: _P.gold, size: 16),
                        ),
                    ]),
                  ),
                );
              },
            ),
          ),
          // ── EXPORT ALL button ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: GestureDetector(
              onTap: _exportAllCollections,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _P.gold.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _P.gold.withOpacity(0.25)),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.file_upload_outlined, color: _P.gold, size: 16),
                  const SizedBox(width: 8),
                  Text('EXPORT ALL COLLECTIONS', style: _T.button),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  void _deleteCollection(CardCollection col, BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (_) => _darkDialog(
        title: 'Delete "${col.name}"?',
        content: 'This cannot be undone.',
        confirmLabel: 'DELETE',
        confirmColor: _P.red,
        onConfirm: () {
          setState(() {
            collections.remove(col);
            if (currentCollection == col) {
              currentCollection = collections.isNotEmpty ? collections.first : null;
            }
            _saveCollections();
          });
          Navigator.pop(context);
          Navigator.pop(context);
        },
      ),
    );
  }

  // ── Dialogs ───────────────────────────────────────────────────────────────
  Future<void> _showAddCardDialog(BuildContext ctx) async {
    await showDialog(context: ctx, builder: (_) => _inputDialog(
      title: 'ADD CARD',
      subtitle: 'to ${currentCollection?.name}',
      hint: 'Enter card text…',
      multiline: true,
      onConfirm: (val) { if (val.trim().isNotEmpty) addNewCard(val.trim()); },
    ));
  }

  Future<void> _showEditCardDialog(BuildContext ctx, int idx, String current) async {
    await showDialog(context: ctx, builder: (_) => _inputDialog(
      title: 'EDIT CARD',
      initialValue: current,
      hint: 'Card text…',
      multiline: true,
      onConfirm: (val) { if (val.trim().isNotEmpty) updateCard(idx, val.trim()); },
    ));
  }

  Future<void> _showDeleteCardDialog(BuildContext ctx, int idx, String card) async {
    await showDialog(context: ctx, builder: (_) => _darkDialog(
      title: 'Delete this card?',
      content: card.length > 80 ? '${card.substring(0, 80)}…' : card,
      confirmLabel: 'DELETE',
      confirmColor: _P.red,
      onConfirm: () { deleteCard(idx); Navigator.pop(context); },
    ));
  }

  Future<void> _showAddCollectionDialog(BuildContext ctx) async {
    await showDialog(context: ctx, builder: (_) => _inputDialog(
      title: 'NEW COLLECTION',
      hint: 'Collection name…',
      onConfirm: (val) { if (val.trim().isNotEmpty) addNewCollection(val.trim()); },
    ));
  }

  Widget _darkDialog({
    required String title,
    required String content,
    required String confirmLabel,
    required Color confirmColor,
    required VoidCallback onConfirm,
  }) {
    return Dialog(
      backgroundColor: _P.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: _P.gold.withOpacity(0.2))),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(
              fontFamily: 'Georgia', fontSize: 18, color: _P.cream)),
            const SizedBox(height: 12),
            Text(content, style: const TextStyle(
              color: _P.muted, fontFamily: 'Georgia', fontSize: 13, height: 1.5)),
            const SizedBox(height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('CANCEL', style: _T.label)),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onConfirm,
                child: Text(confirmLabel, style: TextStyle(
                  color: confirmColor, letterSpacing: 1.5,
                  fontWeight: FontWeight.w700, fontSize: 12))),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _inputDialog({
    required String title,
    String? subtitle,
    String? initialValue,
    required String hint,
    bool multiline = false,
    required void Function(String) onConfirm,
  }) {
    String value = initialValue ?? '';
    return Dialog(
      backgroundColor: _P.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: _P.gold.withOpacity(0.2))),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: _T.label),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(
                fontFamily: 'Georgia', fontSize: 17, color: _P.cream)),
            ],
            const SizedBox(height: 20),
            TextField(
              onChanged: (v) => value = v,
              controller: TextEditingController(text: initialValue),
              maxLines: multiline ? 4 : 1,
              style: const TextStyle(color: _P.cream, fontFamily: 'Georgia', fontSize: 15),
              cursorColor: _P.gold,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: _P.muted, fontFamily: 'Georgia'),
                filled: true, fillColor: _P.card,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _P.gold.withOpacity(0.2))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _P.gold.withOpacity(0.2))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _P.gold.withOpacity(0.6))),
              ),
            ),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('CANCEL', style: _T.label)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () { onConfirm(value); Navigator.pop(context); },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: _P.gold, borderRadius: BorderRadius.circular(20)),
                  child: Text('CONFIRM', style: TextStyle(
                    color: _P.bg, fontFamily: 'Georgia',
                    fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label,
      {Color color = _P.cream}) {
    return PopupMenuItem(
      value: value,
      child: Row(children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: color, fontFamily: 'Georgia')),
      ]),
    );
  }

  Widget _sheetButton(String label, IconData icon, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: _P.gold.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _P.gold.withOpacity(0.4)),
        ),
        child: Row(children: [
          Icon(icon, color: _P.gold, size: 14),
          const SizedBox(width: 6),
          Text(label, style: _T.button),
        ]),
      ),
    );
  }
}

// ── Custom Painters ───────────────────────────────────────────────────────────

class _BgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.2),
        radius: 0.8,
        colors: const [Color(0xFF1A1530), Color(0xFF09090E)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    final dotPaint = Paint()
      ..color = const Color(0xFFD4AF6A).withOpacity(0.04)
      ..style = PaintingStyle.fill;

    const spacing = 28.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFD4AF6A).withOpacity(0.5)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    canvas.drawPath(
      Path()
        ..moveTo(0, size.height)
        ..lineTo(0, 0)
        ..lineTo(size.width, 0),
      paint,
    );
    canvas.drawCircle(Offset.zero, 2, paint..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(_) => false;
}