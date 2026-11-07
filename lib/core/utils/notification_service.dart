import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
      macOS: darwinInit,
    );

    await _notificationsPlugin.initialize(initSettings);
  }

  static Future<void> showLowStockAlert({
    required String productName,
    required int quantityOnHand,
    required int reorderLevel,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'low_stock_channel',
      'Low Stock Alerts',
      channelDescription: 'Notifications for products that reached reorder level',
      importance: Importance.high,
      priority: Priority.high,
    );
    const notificationDetails = NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      productName.hashCode,
      'Low Stock Alert: $productName',
      'Only $quantityOnHand left in stock (Reorder level: $reorderLevel)',
      notificationDetails,
    );
  }

  static Future<void> showDailySummaryAlert({
    required int lowStockCount,
    required int outOfStockCount,
  }) async {
    if (lowStockCount == 0 && outOfStockCount == 0) return;

    const androidDetails = AndroidNotificationDetails(
      'daily_summary_channel',
      'Daily Restock Summary',
      channelDescription: 'Daily overview of items needing restock',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const notificationDetails = NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      999999,
      'Daily Restock Overview',
      'You have $lowStockCount low stock item(s) and $outOfStockCount out of stock item(s).',
      notificationDetails,
    );
  }
}
