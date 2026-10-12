import 'models/pulse_totals.dart';
import 'services/pulse_service.dart';
class DemoData {
  static const bool on = false;
  static const int people = 56;

  static Map<String, PulseTotals> weeks(String thisWeek) {
    const sample = [
      [18, 16, 8, 4],
      [22, 14, 6, 2],
      [12, 18, 12, 6],
      [20, 14, 8, 4],
    ];
    return {
      for (var i = 0; i < sample.length; i++)
        PulseService.shiftWeek(thisWeek, i - sample.length): PulseTotals(
          great: sample[i][0],
          good: sample[i][1],
          okay: sample[i][2],
          difficult: sample[i][3],
          submitted: sample[i].reduce((a, b) => a + b),
        ),
    };
  }
}