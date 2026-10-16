/**
 * Haystek Pulse: automatic notifications.
 * Every Friday at 5:45 PM (India time), tell all employees that the
 * Weekly Pulse opens at 6 PM.
 */

const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

admin.initializeApp();

exports.pulseHeadsUp = onSchedule(
  {
    // minute hour day-of-month month day-of-week (5 = Friday)
    schedule: "45 17 * * 5",
    timeZone: "Asia/Kolkata",
    region: "asia-south1",
  },
  async () => {
    const title = "Weekly Pulse opens at 6 PM 💙";
    const body = "Take a minute to rate your week. Open until Sunday night.";

    await admin.messaging().send({
      topic: "employees",
      notification: { title, body },
      data: { type: "pulse_soon" },
      android: {
        priority: "high",
        notification: {
          channelId: "haystek_alerts",
          icon: "ic_notification",
        },
      },
      apns: {
        payload: { aps: { sound: "default" } },
      },
    });

    console.log("Weekly Pulse heads-up sent to employees.");
  }
);
