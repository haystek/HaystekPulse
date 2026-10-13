import 'package:flutter/material.dart';

import '../models/feedback_item.dart';
import '../models/pulse_rating.dart';
import '../services/feedback_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import 'feedback_detail_screen.dart';

/// Management search. Two kinds, never mixed:
/// - source 'box': Suggestion Box. Search box only: the Suggestion Box
///   tab already has the status chips and the dates.
/// - source 'pulse': Weekly Pulse comments. Rating, status and date.
/// Type words, a name or an employee ID. Matching words are highlighted.
class FeedbackListScreen extends StatefulWidget {
  const FeedbackListScreen({super.key, this.source = 'box'});

  /// 'box' or 'pulse'.
  final String source;

  bool get isPulse => source == 'pulse';

  @override
  State<FeedbackListScreen> createState() => _FeedbackListScreenState();
}

class _FeedbackListScreenState extends State<FeedbackListScreen> {
  late final Stream<List<FeedbackItem>> _stream = FeedbackService.instance
      .watchAll()
      .map((all) => all.where((f) => f.source == widget.source).toList());
  final TextEditingController _search = TextEditingController();

  String _query = '';

  /// Weekly Pulse rating: null is any rating.
  String? _rating;

  /// The chosen status: null is any status.
  String? _status;

  /// The chosen dates.
  _Dates _dates = _Dates.any;

  /// The month chosen with "Pick a month…" (first day of that month).
  DateTime? _month;

  static DateTime _dateOf(FeedbackItem f) => f.createdAt ?? DateTime.now();

  bool _matchesDates(FeedbackItem f) {
    final d = _dateOf(f);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_dates) {
      case _Dates.any:
        return true;
      case _Dates.days7:
        return !d.isBefore(DateTime(today.year, today.month, today.day - 7));
      case _Dates.days30:
        return !d.isBefore(DateTime(today.year, today.month, today.day - 30));
      case _Dates.months3:
        return !d.isBefore(DateTime(today.year, today.month - 3, today.day));
      case _Dates.thisYear:
        return d.year == now.year;
      case _Dates.month:
        return d.year == _month!.year && d.month == _month!.month;
    }
  }

  String _datesLabel() {
    switch (_dates) {
      case _Dates.any:
        return 'Any date';
      case _Dates.days7:
        return 'Last 7 days';
      case _Dates.days30:
        return 'Last 30 days';
      case _Dates.months3:
        return 'Last 3 months';
      case _Dates.thisYear:
        return 'This year';
      case _Dates.month:
        return '${_longMonths[_month!.month - 1]} ${_month!.year}';
    }
  }

  /// How many filters are on, for "Clear all".
  int get _filtersOn =>
      (_rating != null ? 1 : 0) +
          (_status != null ? 1 : 0) +
          (_dates != _Dates.any ? 1 : 0);

  /// Every filter except status, so the status chips can show counts.
  bool _matchesOthers(FeedbackItem f) {
    if (_rating != null && f.rating != _rating) return false;
    if (!_matchesDates(f)) return false;
    return _matchesQuery(f);
  }

  Future<void> _openDates(List<FeedbackItem> all) async {
    Widget option(String label, _Dates value) => ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        label,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),
      trailing: Icon(
        _dates == value
            ? Icons.radio_button_checked
            : Icons.radio_button_unchecked,
        color: _dates == value ? AppColors.blue : const Color(0xFFC9D0DC),
      ),
      onTap: () {
        Navigator.of(context).pop();
        setState(() {
          _dates = value;
          _month = null;
        });
      },
    );

    final months = <DateTime>{
      for (final f in all) DateTime(_dateOf(f).year, _dateOf(f).month, 1),
    }.toList()
      ..sort((a, b) => b.compareTo(a));

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.75,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            children: [
              Text(
                widget.isPulse
                    ? 'Show comments from'
                    : 'Show suggestions from',
                style: heading(19, weight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              option('Any date', _Dates.any),
              option('Last 7 days', _Dates.days7),
              option('Last 30 days', _Dates.days30),
              option('Last 3 months', _Dates.months3),
              option('This year', _Dates.thisYear),
              if (months.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(0, 14, 0, 4),
                  child: Text(
                    'Or pick a month',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                for (final m in months)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${_longMonths[m.month - 1]} ${m.year}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    trailing: Icon(
                      _dates == _Dates.month && _month == m
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: _dates == _Dates.month && _month == m
                          ? AppColors.blue
                          : const Color(0xFFC9D0DC),
                    ),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      setState(() {
                        _dates = _Dates.month;
                        _month = m;
                      });
                    },
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// True when the words, the name or the employee ID match. Names and
  /// IDs of anonymous suggestions are never searched.
  bool _matchesQuery(FeedbackItem item) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (item.text.toLowerCase().contains(q)) return true;
    if (item.anonymous) return false;
    final name = (item.authorName ?? '').toLowerCase();
    final id = (item.authorEmployeeId ?? '').toLowerCase();
    return name.contains(q) || id.contains(q);
  }

  void _clearAll() {
    _search.clear();
    setState(() {
      _query = '';
      _rating = null;
      _status = null;
      _dates = _Dates.any;
      _month = null;
    });
  }

  void _open(FeedbackItem item) {
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FeedbackDetailScreen(item: item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        leadingWidth: 68,
        leading: const AppBackButton(),
        titleSpacing: 4,
        centerTitle: false,
        title: Text(
          widget.isPulse ? 'Search comments' : 'Search suggestions',
          style: heading(22),
        ),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: StreamBuilder<List<FeedbackItem>>(
              stream: _stream,
              builder: (context, snap) {
                final all = snap.data ?? const <FeedbackItem>[];
                final found = all.where(_matchesOthers).toList();
                final items = _status == null
                    ? found
                    : found.where((f) => f.status == _status).toList();
                final filters = <String?>[null, ...FeedbackStatus.all];

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Search box.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                      child: TextField(
                        controller: _search,
                        autofocus: true,
                        onChanged: (v) => setState(() => _query = v),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Words, name or employee ID',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _search.clear();
                              setState(() => _query = '');
                            },
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF5F7FB),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(28),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(28),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(28),
                            borderSide: const BorderSide(
                              color: AppColors.blue,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Ratings, only for Weekly Pulse comments.
                    if (widget.isPulse) ...[
                      SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          children: [
                            _PlainChip(
                              label: 'Any rating',
                              selected: _rating == null,
                              onTap: () => setState(() => _rating = null),
                            ),
                            for (final r in PulseRating.all) ...[
                              const SizedBox(width: 8),
                              _PlainChip(
                                label: PulseRating.label(r),
                                icon: PulseRating.icon(r),
                                selected: _rating == r,
                                onTap: () => setState(() => _rating = r),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    // Status chips, with how many match.
                    if (widget.isPulse)
                      SizedBox(
                        height: 40,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: filters.length,
                          separatorBuilder: (context, index) =>
                          const SizedBox(width: 8),
                          itemBuilder: (context, i) {
                            final s = filters[i];
                            return _StatusChip(
                              label: s == null ? 'All' : FeedbackStatus.label(s),
                              dot: s == null ? null : _statusDot(s),
                              count: s == null
                                  ? found.length
                                  : found.where((f) => f.status == s).length,
                              selected: s == _status,
                              onTap: () => setState(() => _status = s),
                            );
                          },
                        ),
                      ),
                    // Date button, how many show, and Clear all.
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        widget.isPulse ? 20 : 24,
                        12,
                        12,
                        4,
                      ),
                      child: Row(
                        children: [
                          if (widget.isPulse) ...[
                            Material(
                              color: _dates == _Dates.any
                                  ? const Color(0xFFF2F6FF)
                                  : AppColors.blue,
                              shape: const StadiumBorder(),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => _openDates(all),
                                child: Padding(
                                  padding:
                                  const EdgeInsets.fromLTRB(12, 8, 8, 8),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.calendar_month_outlined,
                                        size: 18,
                                        color: _dates == _Dates.any
                                            ? AppColors.blue
                                            : Colors.white,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _datesLabel(),
                                        style: TextStyle(
                                          color: _dates == _Dates.any
                                              ? AppColors.blue
                                              : Colors.white,
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Icon(
                                        Icons.arrow_drop_down,
                                        color: _dates == _Dates.any
                                            ? AppColors.blue
                                            : Colors.white,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: Text(
                              _resultLine(items.length, snap.hasData),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (_filtersOn > 0 || _query.isNotEmpty)
                            TextButton(
                              onPressed: _clearAll,
                              child: const Text('Clear all'),
                            ),
                        ],
                      ),
                    ),
                    Expanded(child: _list(snap, all, items)),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  String _resultLine(int count, bool loaded) {
    if (!loaded) return 'Loading…';
    final things = count == 1 ? '1 result' : '$count results';
    final q = _query.trim();
    if (q.isEmpty) return things;
    return '$things for $q';
  }

  Widget _list(
      AsyncSnapshot<List<FeedbackItem>> snap,
      List<FeedbackItem> all,
      List<FeedbackItem> items,
      ) {
    if (snap.hasError) {
      return const _Empty(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load',
        text: 'Please go back and try again.',
      );
    }
    if (!snap.hasData) {
      return const Center(child: CircularProgressIndicator());
    }
    if (all.isEmpty) {
      return _Empty(
        icon: Icons.inbox_outlined,
        title: 'Nothing yet',
        text: widget.isPulse
            ? 'When employees write Weekly Pulse comments, you can search '
            'them here.'
            : 'When employees send suggestions, you can search them here.',
      );
    }
    if (items.isEmpty) {
      return _Empty(
        icon: Icons.search_off,
        title: 'Nothing found',
        text: 'Try another word, or change the filters.',
        action: TextButton(
          onPressed: _clearAll,
          child: const Text('Clear search and filter'),
        ),
      );
    }
    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, i) => _ResultCard(
        item: items[i],
        query: _query.trim(),
        onTap: () => _open(items[i]),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Pieces
// ---------------------------------------------------------------------

/// The date choices.
enum _Dates { any, days7, days30, months3, thisYear, month }

const List<String> _longMonths = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// A round chip with an optional icon. The chosen one is dark blue.
class _PlainChip extends StatelessWidget {
  const _PlainChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.ink : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? AppColors.ink : const Color(0xFFD5DCE8),
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 17,
                  color: selected ? Colors.white : AppColors.muted,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A round chip: an optional colour dot, the name and the number.
/// The chosen one is blue.
class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.dot,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color? dot;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.blue : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? AppColors.blue : const Color(0xFFD5DCE8),
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dot != null) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: selected ? Colors.white : dot,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 7),
              Container(
                constraints: const BoxConstraints(minWidth: 22),
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.22)
                      : const Color(0xFFEEF1F6),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: selected ? Colors.white : AppColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One result: status tag and date, the text with the searched words
/// highlighted, who wrote it, and a round arrow.
class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.item,
    required this.query,
    required this.onTap,
  });

  final FeedbackItem item;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = item.status;
    final isNew = status == FeedbackStatus.newItem;
    final name = item.authorName ?? '';
    final id = item.authorEmployeeId ?? '';
    final who =
    item.anonymous ? 'Anonymous' : (id.isEmpty ? name : '$name ($id)');
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final textStyle = TextStyle(
      fontSize: 15.5,
      height: 1.4,
      color: AppColors.ink,
      fontWeight: isNew ? FontWeight.w600 : FontWeight.w500,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE6EBF4), width: 1.5),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
                            decoration: BoxDecoration(
                              color: _statusTint(status),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: _statusDot(status),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  isNew
                                      ? 'Needs reply'
                                      : FeedbackStatus.label(status),
                                  style: TextStyle(
                                    color: _statusInk(status),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          const SizedBox(width: 8),
                          Text(
                            _when(item.createdAt),
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Weekly Pulse comments: the rating.
                      if (!item.isFromBox && item.rating != null) ...[
                        Row(
                          children: [
                            Icon(
                              PulseRating.icon(item.rating!),
                              size: 15,
                              color: AppColors.muted,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              PulseRating.label(item.rating!),
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text.rich(
                        _highlight(item.text, query, textStyle),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: item.anonymous
                                  ? const Color(0xFFEEF1F6)
                                  : AppColors.blueTint,
                              shape: BoxShape.circle,
                            ),
                            child: item.anonymous
                                ? const Icon(
                              Icons.lock_outline,
                              size: 13,
                              color: AppColors.muted,
                            )
                                : Text(
                              initial,
                              style: const TextStyle(
                                color: AppColors.blueDeep,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text.rich(
                              _highlight(
                                who,
                                item.anonymous ? '' : query,
                                const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 13,
                                ),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF2F6FF),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.chevron_right,
                    color: AppColors.blue,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The text with every match of [query] on a yellow background.
TextSpan _highlight(String text, String query, TextStyle style) {
  if (query.isEmpty) return TextSpan(text: text, style: style);
  final lower = text.toLowerCase();
  final q = query.toLowerCase();
  final spans = <TextSpan>[];
  var start = 0;
  while (true) {
    final at = lower.indexOf(q, start);
    if (at < 0) {
      spans.add(TextSpan(text: text.substring(start)));
      break;
    }
    if (at > start) spans.add(TextSpan(text: text.substring(start, at)));
    spans.add(
      TextSpan(
        text: text.substring(at, at + q.length),
        style: const TextStyle(
          backgroundColor: Color(0xFFFFE58A),
          color: AppColors.ink,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    start = at + q.length;
  }
  return TextSpan(style: style, children: spans);
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.title,
    required this.text,
    this.action,
  });

  final IconData icon;
  final String title;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: const Color(0xFFB7C0D1)),
            const SizedBox(height: 12),
            Text(title, style: heading(18, weight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 15),
            ),
            if (action != null) ...[
              const SizedBox(height: 8),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "3:40 PM" for today, "7 Oct" this year, "7 Oct 2025" before.
String _when(DateTime? d) {
  if (d == null) return 'Just now';
  final now = DateTime.now();
  if (d.year == now.year && d.month == now.month && d.day == now.day) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
  }
  final short = '${d.day} ${_months[d.month - 1]}';
  return d.year == now.year ? short : '$short ${d.year}';
}

/// Same status colours as the Suggestion Box tab.
Color _statusDot(String status) {
  switch (status) {
    case FeedbackStatus.newItem:
      return const Color(0xFFE9A83B);
    case FeedbackStatus.underReview:
      return const Color(0xFF8B5CF6);
    case FeedbackStatus.planned:
      return const Color(0xFF0EA5A4);
    case FeedbackStatus.inProgress:
      return AppColors.blue;
    default:
      return const Color(0xFF16A34A);
  }
}

Color _statusTint(String status) {
  switch (status) {
    case FeedbackStatus.newItem:
      return const Color(0xFFFDF3DF);
    case FeedbackStatus.underReview:
      return const Color(0xFFF1EBFE);
    case FeedbackStatus.planned:
      return const Color(0xFFE0F5F4);
    case FeedbackStatus.inProgress:
      return const Color(0xFFE6EDFF);
    default:
      return const Color(0xFFE3F6EA);
  }
}

Color _statusInk(String status) {
  switch (status) {
    case FeedbackStatus.newItem:
      return const Color(0xFF8A5A00);
    case FeedbackStatus.underReview:
      return const Color(0xFF5B34C7);
    case FeedbackStatus.planned:
      return const Color(0xFF0B6B6A);
    case FeedbackStatus.inProgress:
      return AppColors.blueDeep;
    default:
      return const Color(0xFF166534);
  }
}