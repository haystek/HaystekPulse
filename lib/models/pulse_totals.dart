import 'pulse_rating.dart';

/// The totals for one week, as stored in `pulse_weeks/{weekId}`.
/// It holds counts only. It never says who chose which rating.
class PulseTotals {
  const PulseTotals({
    this.great = 0,
    this.good = 0,
    this.okay = 0,
    this.difficult = 0,
    this.submitted = 0,
  });

  final int great;
  final int good;
  final int okay;
  final int difficult;
  final int submitted;

  int countFor(String rating) {
    switch (rating) {
      case PulseRating.great:
        return great;
      case PulseRating.good:
        return good;
      case PulseRating.okay:
        return okay;
      default:
        return difficult;
    }
  }

  factory PulseTotals.fromMap(Map<String, dynamic>? data) {
    int read(String key) => ((data?[key] ?? 0) as num).toInt();
    return PulseTotals(
      great: read(PulseRating.great),
      good: read(PulseRating.good),
      okay: read(PulseRating.okay),
      difficult: read(PulseRating.difficult),
      submitted: read('submitted'),
    );
  }
}
