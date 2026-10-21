/**
 * Haystek Pulse: automatic notifications.
 * 15 minutes before the Weekly Pulse opens, tell all employees.
 * Live time: Friday 5:45 PM (India time). For testing, change the time
 * in Cloud Scheduler (the next deploy sets it back to this time).
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
    const title = "Weekly Pulse opens in 15 minutes 💙";
    const body = "Take a minute to rate your week when it opens.";

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
