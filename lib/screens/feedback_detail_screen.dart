import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/feedback_item.dart';
import '../models/pulse_rating.dart';
import '../services/feedback_service.dart';
import '../theme/app_theme.dart';
import '../widgets/feedback_bits.dart';
import '../widgets/ui.dart';

/// Inter font for everything on these screens, sheets and dialogs
/// (same as the employee screens).
Widget _withInter(BuildContext context, Widget child) {
  final t = Theme.of(context);
  return Theme(
    data: t.copyWith(textTheme: GoogleFonts.interTextTheme(t.textTheme)),
    child: child,
  );
}

/// Titles and big numbers in Inter.
TextStyle _h(
    double size, {
      FontWeight weight = FontWeight.w800,
      Color color = AppColors.ink,
      double? height,
    }) =>
    GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: size >= 22 ? -0.5 : -0.2,
    );

/// Management: open one entry, set its status, and write the reply
/// when the status is "Implemented".
class FeedbackDetailScreen extends StatefulWidget {
  const FeedbackDetailScreen({super.key, required this.item});

  final FeedbackItem item;

  @override
  State<FeedbackDetailScreen> createState() => _FeedbackDetailScreenState();
}

class _FeedbackDetailScreenState extends State<FeedbackDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _message;

  /// The status management tapped. Null until they choose one.
  String? _chosen;
  bool _busy = false;
  String? _error;

  String get _current => widget.item.status;

  /// What will be saved: the chosen status, or the current one.
  String get _status => _chosen ?? _current;

  bool get _implemented => _status == FeedbackStatus.implemented;

  /// Something to save: a new status, or an edit to the reply of a
  /// feedback that is already Implemented.
  bool get _canSave => _chosen != null || _implemented;

  @override
  void initState() {
    super.initState();
    _message = TextEditingController(text: widget.item.managementMessage);
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await FeedbackService.instance.updateStatus(
        id: widget.item.id,
        status: _status,
        message: _message.text,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _chosen == null
                ? 'Reply saved.'
                : 'Status updated to ${FeedbackStatus.label(_status)}.',
          ),
        ),
      );
      navigator.pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not update. Please check your internet '
            'connection and try again.';
      });
    }
  }

  String _date(DateTime? d) {
    if (d == null) return '';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final rating = item.rating;
    final source = item.isFromBox
        ? 'Suggestion Box'
        : rating == null
        ? 'Weekly Pulse'
        : 'Weekly Pulse, ${PulseRating.label(rating)}';
    final date = _date(item.createdAt);

    OutlineInputBorder replyBorder(double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: AppColors.ink, width: width),
    );

    return _withInter(context, Scaffold(
      appBar: AppBar(
        leadingWidth: 68,
        leading: const AppBackButton(),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Center(
              child: Text(
                date.isEmpty ? source : '$source, $date',
                style: const TextStyle(color: AppColors.muted, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The employee's own words lead the screen.
                    Text(
                      item.text,
                      style: _h(22, weight: FontWeight.w700, height: 1.3),
                    ),
                    const SizedBox(height: 10),
                    AuthorLine(item: item),
                    const SizedBox(height: 18),

                    Panel(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text('Status now', style: _h(16)),
                              ),
                              StatusPill(status: _current),
                            ],
                          ),
                          const SizedBox(height: 14),
                          const Divider(height: 1),
                          const SizedBox(height: 14),
                          const Text(
                            'Change status to',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 14.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final s in FeedbackStatus.all)
                                if (s != _current)
                                  _StatusChoice(
                                    label: FeedbackStatus.label(s),
                                    selected: s == _chosen,
                                    onTap: _busy
                                        ? null
                                        : () => setState(() {
                                      // Tap again to undo the choice.
                                      _chosen = s == _chosen ? null : s;
                                    }),
                                  ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (!_implemented) ...[
                      const SizedBox(height: 12),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          'The employee sees the new status in My Feedback. '
                              'A reply is asked only when you choose Implemented.',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],

                    if (_implemented) ...[
                      const SizedBox(height: 16),
                      Text('Reply to the employee', style: _h(16)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _message,
                        minLines: 3,
                        maxLines: 8,
                        maxLength: 1000,
                        textCapitalization: TextCapitalization.sentences,
                        style: const TextStyle(fontSize: 15.5, height: 1.4),
                        decoration: InputDecoration(
                          hintText: 'Tell the employee what has been done',
                          border: replyBorder(1.5),
                          enabledBorder: replyBorder(1.5),
                          focusedBorder: replyBorder(2),
                        ),
                        validator: (v) {
                          if (!_implemented) return null;
                          return (v == null || v.trim().isEmpty)
                              ? 'A reply is needed for Implemented'
                              : null;
                        },
                      ),
                      const Text(
                        'Needed for Implemented. The employee is notified '
                            'and sees it in My Feedback.',
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                    ],

                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy || !_canSave ? null : _save,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                      child: _busy
                          ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                          : Text(
                        _chosen == null
                            ? (_implemented
                            ? 'Save reply'
                            : 'Choose a status')
                            : 'Change to ${FeedbackStatus.label(_chosen!)}',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ));
  }
}

/// One status to choose, as a round button. Blue with a tick when
/// it is the chosen one.
class _StatusChoice extends StatelessWidget {
  const _StatusChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.blue : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? AppColors.blue : AppColors.inputBorder,
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(Icons.check, color: Colors.white, size: 16),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.ink,
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}