import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/free_usage_service.dart';
import 'widgets/premium_payment_sheet.dart';

void main() => runApp(const CrushReplyApp());

const _ink = Color(0xFF292326);
const _muted = Color(0xFF83777C);
const _rose = Color(0xFFE85D75);
const _paper = Color(0xFFFFF8F6);

class CrushReplyApp extends StatefulWidget {
  const CrushReplyApp({super.key});

  @override
  State<CrushReplyApp> createState() => _CrushReplyAppState();
}

class _CrushReplyAppState extends State<CrushReplyApp> {
  ThemeMode _themeMode = ThemeMode.light;

  void _toggleTheme() => setState(() {
    _themeMode = _themeMode == ThemeMode.light
        ? ThemeMode.dark
        : ThemeMode.light;
  });

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _rose,
        brightness: brightness,
        primary: _rose,
        surface: dark ? const Color(0xFF211D20) : Colors.white,
      ),
      scaffoldBackgroundColor: dark ? const Color(0xFF171416) : _paper,
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? const Color(0xFF171416) : _paper,
        foregroundColor: dark ? Colors.white : _ink,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF292427) : Colors.white,
        hintStyle: const TextStyle(color: _muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: dark ? Colors.white12 : const Color(0xFFF1E8E8),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'CrushReply',
    debugShowCheckedModeBanner: false,
    themeMode: _themeMode,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    home: HomeScreen(onToggleTheme: _toggleTheme),
  );
}

class ReplyCategory {
  const ReplyCategory(this.label, this.emoji, this.tone, this.color);
  final String label;
  final String emoji;
  final String tone;
  final Color color;
}

const _categories = <ReplyCategory>[
  ReplyCategory('Romantic', '❤️', 'Romantic', Color(0xFFFCE5E9)),
  ReplyCategory('Flirty', '😏', 'Flirty', Color(0xFFFFE9DC)),
  ReplyCategory('Funny', '😂', 'Funny', Color(0xFFFFF1CC)),
  ReplyCategory('Cute', '🥰', 'Cute', Color(0xFFFFE4EF)),
  ReplyCategory('Bold', '🔥', 'Bold', Color(0xFFFFE0D7)),
  ReplyCategory('Confident', '😎', 'Confident', Color(0xFFE1F0F2)),
  ReplyCategory('Apology', '💔', 'Apology', Color(0xFFF5E6EA)),
  ReplyCategory('First message', '👋', 'Casual', Color(0xFFE4EFE8)),
  ReplyCategory('Good night', '🌙', 'Cute', Color(0xFFEAE5F3)),
  ReplyCategory('Good morning', '☀️', 'Cute', Color(0xFFFFF0CF)),
  ReplyCategory('Ask them out', '💕', 'Confident', Color(0xFFFCE5E9)),
  ReplyCategory('Left on read', '👀', 'Funny', Color(0xFFE9E8F3)),
  ReplyCategory('Teasing', '😘', 'Flirty', Color(0xFFFFE9DC)),
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onToggleTheme});
  final VoidCallback onToggleTheme;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _openReplies({String? category}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReplyScreen(
          initialMessage: _messageController.text,
          initialCategory: category,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
              sliver: SliverList.list(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFCE5E9),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        alignment: Alignment.center,
                        child: const Text('💌', style: TextStyle(fontSize: 22)),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'CrushReply',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: dark
                            ? 'Switch to light mode'
                            : 'Switch to dark mode',
                        onPressed: widget.onToggleTheme,
                        icon: Icon(
                          dark
                              ? Icons.light_mode_outlined
                              : Icons.dark_mode_outlined,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Premium',
                        onPressed: () async {
                          await _showPremium(context);
                          if (mounted) setState(() {});
                        },
                        icon: const Icon(
                          Icons.workspace_premium_outlined,
                          color: _rose,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  const Text(
                    'YOUR TEXTING WINGPERSON',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w800,
                      color: _rose,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    "Don't know what to reply?\nWe've got you 😏",
                    style: TextStyle(
                      fontSize: 29,
                      height: 1.16,
                      fontWeight: FontWeight.w800,
                      color: dark ? Colors.white : _ink,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Paste their message. We’ll find the words.',
                    style: TextStyle(color: _muted, fontSize: 14),
                  ),
                  const SizedBox(height: 22),
                  TextField(
                    controller: _messageController,
                    minLines: 3,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: '“Why did you disappear? 😂”',
                      contentPadding: EdgeInsets.all(17),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: () => _openReplies(),
                      icon: const Icon(Icons.auto_awesome, size: 19),
                      label: const Text(
                        'Generate replies',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: _rose,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  Row(
                    children: [
                      Text(
                        'Pick your vibe',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: dark ? Colors.white : _ink,
                        ),
                      ),
                      const Spacer(),
                      const Text(
                        '13 situations',
                        style: TextStyle(fontSize: 12, color: _muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  GridView.builder(
                    itemCount: _categories.length,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 180,
                          mainAxisExtent: 55,
                          crossAxisSpacing: 9,
                          mainAxisSpacing: 9,
                        ),
                    itemBuilder: (context, index) {
                      final category = _categories[index];
                      return Material(
                        color: category.color.withValues(
                          alpha: dark ? 0.17 : 0.78,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _openReplies(category: category.label),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 11),
                            child: Row(
                              children: [
                                Text(
                                  category.emoji,
                                  style: const TextStyle(fontSize: 18),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    category.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 30),
                  Row(
                    children: [
                      Text(
                        'Popular right now',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: dark ? Colors.white : _ink,
                        ),
                      ),
                      const Spacer(),
                      const Icon(Icons.trending_up, size: 19, color: _rose),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _PopularReply(
                    emoji: '😏',
                    text: 'I was hoping you’d notice I was gone',
                    onTap: () => _openReplies(category: 'Romantic'),
                  ),
                  _PopularReply(
                    emoji: '💬',
                    text: 'Okay, but now I need the full story',
                    onTap: () => _openReplies(category: 'Flirty'),
                  ),
                  _PopularReply(
                    emoji: '✨',
                    text: 'You make being distracted look easy',
                    onTap: () => _openReplies(category: 'Cute'),
                  ),
                  const SizedBox(height: 16),
                  const _AdPlaceholder(),
                  const SizedBox(height: 12),
                  const Center(child: _PlanStatus()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PopularReply extends StatelessWidget {
  const _PopularReply({
    required this.emoji,
    required this.text,
    required this.onTap,
  });
  final String emoji;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
    leading: Text(emoji, style: const TextStyle(fontSize: 20)),
    title: Text(
      text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
    trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: _muted),
    onTap: onTap,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  );
}

class ReplyScreen extends StatefulWidget {
  const ReplyScreen({
    super.key,
    required this.initialMessage,
    this.initialCategory,
  });
  final String initialMessage;
  final String? initialCategory;

  @override
  State<ReplyScreen> createState() => _ReplyScreenState();
}

class _ReplyScreenState extends State<ReplyScreen> {
  static const _tones = [
    'Romantic',
    'Flirty',
    'Funny',
    'Cute',
    'Bold',
    'Casual',
  ];
  static const _options = [
    'Shorter',
    'More romantic',
    'Funnier',
    'More confident',
    'Less obvious',
  ];
  late final TextEditingController _messageController = TextEditingController(
    text: widget.initialMessage,
  );
  late String _tone = widget.initialCategory == null
      ? 'Flirty'
      : _categories
            .firstWhere(
              (item) => item.label == widget.initialCategory,
              orElse: () => _categories[1],
            )
            .tone;
  final Set<String> _selectedOptions = {};
  final _usageService = FreeUsageService();
  List<String> _replies = [];
  bool _generated = false;
  int _remainingToday = FreeUsageService.dailyLimit;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final canGenerate = await _usageService.consumeGeneration();
    if (!mounted) return;
    if (!canGenerate) {
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'That’s your five for today 💌',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Premium will unlock unlimited replies and remove ads.',
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(context);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _showPremium(this.context);
                      });
                    },
                    child: const Text('Get Premium · KSh 100/month'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }
    final remaining = await _usageService.remainingToday();
    if (!mounted) return;
    setState(() {
      _replies = _makeReplies(_messageController.text, _tone, _selectedOptions);
      _generated = true;
      _remainingToday = remaining;
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Your replies',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            const Text(
              'What did they say?',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _messageController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Paste their message here',
              ),
            ),
            const SizedBox(height: 21),
            const Text(
              'Choose a tone',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _tones
                  .map(
                    (tone) => ChoiceChip(
                      label: Text(tone),
                      selected: tone == _tone,
                      onSelected: (_) => setState(() => _tone = tone),
                      selectedColor: const Color(0xFFFCE5E9),
                      labelStyle: TextStyle(
                        color: tone == _tone
                            ? const Color(0xFFB83250)
                            : (dark ? Colors.white : _ink),
                        fontWeight: FontWeight.w600,
                      ),
                      side: BorderSide(
                        color: tone == _tone
                            ? _rose.withValues(alpha: 0.4)
                            : Colors.transparent,
                      ),
                      showCheckmark: false,
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 17),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text(
                'Fine-tune your reply',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'Optional adjustments',
                style: TextStyle(fontSize: 12, color: _muted),
              ),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _options
                      .map(
                        (option) => FilterChip(
                          label: Text(option),
                          selected: _selectedOptions.contains(option),
                          onSelected: (selected) => setState(
                            () => selected
                                ? _selectedOptions.add(option)
                                : _selectedOptions.remove(option),
                          ),
                          selectedColor: const Color(0xFFFCE5E9),
                          showCheckmark: false,
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 10),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                onPressed: _generate,
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: Text(_generated ? 'Generate again' : 'Generate replies'),
                style: FilledButton.styleFrom(
                  backgroundColor: _rose,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
            ),
            if (_generated) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  const Text(
                    'Made for your conversation',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  Text(
                    '${_replies.length} ideas',
                    style: const TextStyle(fontSize: 12, color: _muted),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (var index = 0; index < _replies.length; index++)
                _ReplyCard(
                  tone: _tone,
                  text: _replies[index],
                  emoji: _toneEmoji[_tone]!,
                ),
              const SizedBox(height: 8),
              const _AdPlaceholder(),
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _remainingToday < 0
                        ? 'Premium · unlimited replies'
                        : 'Free plan · $_remainingToday left today',
                    style: const TextStyle(fontSize: 11, color: _muted),
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(height: 28),
              Center(
                child: Column(
                  children: [
                    const Text('💌', style: TextStyle(fontSize: 39)),
                    const SizedBox(height: 8),
                    Text(
                      'A good reply is just one tap away',
                      style: TextStyle(color: _muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

const _toneEmoji = {
  'Romantic': '❤️',
  'Flirty': '😏',
  'Funny': '😂',
  'Cute': '🥰',
  'Bold': '🔥',
  'Casual': '💬',
};

List<String> _makeReplies(String message, String tone, Set<String> options) {
  final lower = message.toLowerCase();
  final cue =
      lower.contains('disappear') ||
          lower.contains('where') ||
          lower.contains('miss')
      ? 'I was hoping you’d notice I was gone'
      : lower.contains('?')
      ? 'That’s a good question... what answer are you hoping for?'
      : 'Okay, but now I need the full story';
  final replies = switch (tone) {
    'Romantic' => [
      cue,
      'Talking to you is becoming my favorite part of the day',
      'You’ve been on my mind more than I should admit',
    ],
    'Flirty' => [
      cue,
      'Careful, keep talking like that and I might get a crush',
      'Is this your way of asking for my attention?',
    ],
    'Funny' => [
      'I have a very good excuse. It involves snacks.',
      'My brain read that and immediately forgot how to act',
      'Plot twist: I was waiting for you to text first',
    ],
    'Cute' => [
      'Okay, this made me smile way too much',
      'You’re kind of my favorite notification',
      'Not to be dramatic, but I’m glad you texted',
    ],
    'Bold' => [
      'So when are you taking me out?',
      'I like your energy. Let’s see where this goes',
      'You and me, coffee this week. Pick a day',
    ],
    _ => [
      'Haha, fair point. What are you up to?',
      'Okay, I’m listening. Tell me more',
      'Well, you’ve got my attention now',
    ],
  };
  if (options.contains('Shorter')) {
    for (var index = 0; index < replies.length; index++) {
      if (replies[index].length > 48) {
        replies[index] = '${replies[index].substring(0, 45)}...';
      }
    }
  }
  if (options.contains('Funnier')) {
    replies[1] = 'My brain read that and forgot how to act 😂';
  }
  if (options.contains('More romantic')) {
    replies[1] = 'I think my day gets better every time you text me ❤️';
  }
  if (options.contains('More confident')) {
    replies[2] = 'Let’s stop hinting and go on that date';
  }
  if (options.contains('Less obvious')) {
    replies[2] = 'You’re surprisingly easy to talk to';
  }
  return replies;
}

class _ReplyCard extends StatelessWidget {
  const _ReplyCard({
    required this.tone,
    required this.text,
    required this.emoji,
  });
  final String tone;
  final String text;
  final String emoji;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.fromLTRB(14, 13, 10, 12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(
        color: Theme.of(context).dividerColor.withValues(alpha: 0.14),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(emoji),
            const SizedBox(width: 7),
            Text(
              tone,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _muted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Text(
          text,
          style: const TextStyle(
            fontSize: 15,
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Reply copied'),
                    duration: Duration(seconds: 1),
                  ),
                );
              }
            },
            icon: const Icon(Icons.copy_rounded, size: 15),
            label: const Text('Copy'),
            style: TextButton.styleFrom(
              foregroundColor: _rose,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ),
      ],
    ),
  );
}

class _AdPlaceholder extends StatelessWidget {
  const _AdPlaceholder();

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: FreeUsageService().isPremiumActive(),
    builder: (context, snapshot) {
      if (snapshot.data == true) return const SizedBox.shrink();
      return Container(
        height: 58,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text(
          'Ad space',
          style: TextStyle(color: _muted, fontSize: 11),
        ),
      );
    },
  );
}

class _PlanStatus extends StatelessWidget {
  const _PlanStatus();

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: FreeUsageService().isPremiumActive(),
    builder: (context, snapshot) => Text(
      snapshot.data == true
          ? 'Premium · unlimited replies'
          : 'Free plan · 5 generations per day',
      style: const TextStyle(fontSize: 11, color: _muted),
    ),
  );
}

Future<void> _showPremium(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const PremiumPaymentSheet(),
  );
}
