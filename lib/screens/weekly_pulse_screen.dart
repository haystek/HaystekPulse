import 'package:flutter/material.dart';

import '../models/employee.dart';
import '../models/pulse_rating.dart';
import '../services/feedback_service.dart';
import '../services/pulse_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

enum _Stage { loading, loadError, closed, alreadyDone, pick, done }

/// Weekly Pulse: one rating, one extra question for Okay or Difficult,
/// and a confirmation. One answer per employee per week.
class WeeklyPulseScreen extends StatefulWidget {
  const WeeklyPulseScreen({
    super.key,
    required this.employee,
    this.initialRating,
  });

  final Employee employee;

  /// The face tapped on the home screen. It starts already chosen.
  final String? initialRating;

  @override
  State<WeeklyPulseScreen> createState() => _WeeklyPulseScreenState();
}

class _WeeklyPulseScreenState extends State<WeeklyPulseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _text = TextEditingController();

  _Stage _stage = _Stage.loading;
  String? _rating;
  bool _anonymous = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _rating = widget.initialRating;
    _check();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() => _stage = _Stage.loading);
    if (!PulseService.isOpen()) {
      setState(() => _stage = _Stage.closed);
      return;
    }
    try {
      final existing =
      await PulseService.instance.myRatingThisWeek(widget.employee.uid);
      if (!mounted) return;
      setState(
            () => _stage = existing == null ? _Stage.pick : _Stage.alreadyDone,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _stage = _Stage.loadError);
    }
  }

  void _pick(String rating) {
    setState(() {
      _rating = rating;
      _error = null;
    });
  }

  Future<void> _submit() async {
    final rating = _rating;
    if (rating == null) return;
    if (PulseRating.needsText(rating) &&
        !_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await PulseService.instance.submit(
        employee: widget.employee,
        rating: rating,
        text: _text.text,
        anonymous: _anonymous,
      );
      if (!mounted) return;
      setState(() => _stage = _Stage.done);
    } catch (_) {
      if (!mounted) return;
      setState(
            () => _error = 'Could not send. Please check your internet '
            'connection and try again.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 68,
        leading: const AppBackButton(),
        titleSpacing: 4,
        centerTitle: false,
        title: Text('Weekly Pulse', style: heading(22)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Center(
              child: Text(
                PulseService.weekLabel(PulseService.currentWeekId()),
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
            constraints: const BoxConstraints(maxWidth: 480),
            child: _body(context),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    switch (_stage) {
      case _Stage.loading:
        return const Center(child: CircularProgressIndicator());
      case _Stage.loadError:
        return _Info(
          icon: Icons.wifi_off,
          title: 'Could not load',
          text: 'Please check your internet connection and try again.',
          buttonLabel: 'Try again',
          onPressed: _check,
        );
      case _Stage.closed:
        return _Info(
          icon: Icons.event,
          title: 'Opens on ${PulseService.openDayLabel()} at '
              '${PulseService.openTimeLabel()}',
          text: 'Please come back then.\n'
              'The Suggestion Box is open every day.',
          buttonLabel: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        );
      case _Stage.alreadyDone:
        return _Info(
          icon: Icons.check,
          title: 'Already answered',
          text: 'You have shared your feedback for this week.\nThank you.',
          buttonLabel: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        );
      case _Stage.pick:
        return _buildPick(context);
      case _Stage.done:
        return _Info(
          icon: Icons.check,
          title: 'Feedback sent',
          text: 'Thank you for your feedback.\nIt helps us improve.',
          buttonLabel: 'Done',
          onPressed: () => Navigator.of(context).pop(),
        );
    }
  }

  Widget _buildPick(BuildContext context) {
    final theme = Theme.of(context);
    final rating = _rating;
    final needsText = rating != null && PulseRating.needsText(rating);

    Widget tile(String option) => Expanded(
      child: _RatingTile(
        rating: option,
        selected: option == rating,
        onTap: _busy ? null : () => _pick(option),
      ),
    );

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('How was your week?', style: heading(28)),
                        const SizedBox(height: 4),
                        const Text(
                          'Tap one. It takes a few seconds.',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Four tiles, two in each row.
                  for (var i = 0; i < PulseRating.all.length; i += 2) ...[
                    if (i > 0) const SizedBox(height: 10),
                    Row(
                      children: [
                        tile(PulseRating.all[i]),
                        const SizedBox(width: 10),
                        if (i + 1 < PulseRating.all.length)
                          tile(PulseRating.all[i + 1])
                        else
                          const Expanded(child: SizedBox()),
                      ],
                    ),
                  ],
                  if (needsText) ...[
                    const SizedBox(height: 14),
                    Panel(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            PulseRating.question(rating ?? ''),
                            style: heading(16.5),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _text,
                            minLines: 3,
                            maxLines: 8,
                            maxLength: FeedbackService.maxTextLength,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              hintText:
                              'You can mention the project, team or process',
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Please write a few words'
                                : null,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Submit anonymously',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15.5,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      _anonymous
                                          ? 'On: management sees only your '
                                          'feedback. Your name and '
                                          'employee ID are hidden.'
                                          : 'Off: management sees your name '
                                          'and employee ID with this '
                                          'feedback.',
                                      style: const TextStyle(
                                        color: AppColors.muted,
                                        fontSize: 14,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Switch(
                                value: _anonymous,
                                onChanged: _busy
                                    ? null
                                    : (v) => setState(() => _anonymous = v),
                              ),
                            ],
                          ),
                        ],
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
                ],
              ),
            ),
          ),
        ),
        // The send button stays at the bottom of the screen.
        if (rating != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: FilledButton(
              onPressed: _busy ? null : _submit,
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
                  : Text(needsText ? 'Send feedback' : 'Send rating'),
            ),
          ),
      ],
    );
  }
}

/// One of the four answers, as a big tile with a face. The chosen one
/// turns blue with a tick in the corner.
class _RatingTile extends StatelessWidget {
  const _RatingTile({
    required this.rating,
    required this.selected,
    required this.onTap,
  });

  final String rating;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.blue : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: selected ? AppColors.blue : AppColors.border,
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 116,
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      PulseRating.icon(rating),
                      size: 42,
                      color: selected ? Colors.white : AppColors.blueDeep,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      PulseRating.label(rating),
                      style: heading(
                        17,
                        color: selected ? Colors.white : AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 15,
                      color: AppColors.blue,
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

class _Info extends StatelessWidget {
  const _Info({
    required this.icon,
    required this.title,
    required this.text,
    required this.buttonLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String text;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            child: CircleAvatar(
              radius: 36,
              backgroundColor: AppColors.blue,
              child: Icon(icon, color: Colors.white, size: 38),
            ),
          ),
          const SizedBox(height: 24),
          Text(title, textAlign: TextAlign.center, style: heading(28)),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 15.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            child: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}