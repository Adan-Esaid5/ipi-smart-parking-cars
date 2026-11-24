/*
 * שם המסך: CarSimulatorScreen – מערכת הרכבים של IPI SMART PARKING
 * מציג את כל הכניסות והיציאות של הרכבים שנשמרו ב-Supabase.
 * אפשר לבחור תאריך, לחפש רכב או חניון, לראות מצב תשלום ופרטי ביקור.
 * אפשר לפתוח היסטוריית חניונים של רכב ולראות כמה פעמים נכנס.
 * בצד המסך מוצגת רשימת החניונים והמחירים שלהם.
 * חשוב: המסך הזה מציג נתונים מתוך מסד הנתונים. קיימות בו גם
 * פעולות עזר להכנת נתוני סימולציה ולחישוב מחירים.
 * הפקת 15 ביקורים ביום לכל חניון נעשית ב-Supabase בעזרת SQL/pg_cron.
 */

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
class CarSimulatorScreen extends StatefulWidget {
  const CarSimulatorScreen({super.key});
  @override
  State<CarSimulatorScreen> createState() => _CarSimulatorScreenState();
}
class _CarSimulatorScreenState extends State<CarSimulatorScreen> {
  /// החיבור למסד הנתונים Supabase שממנו נלקחים הרכבים והחניונים.
  final supabase = Supabase.instance.client;
  static const Color blue = Color(0xFF0D47A1);
  static const Color blue2 = Color(0xFF1565C0);
  static const Color lightBlue = Color(0xFFEAF3FF);
  static const Color border = Color(0xFFD4E4FA);
  static const Color pageBg = Color(0xFFF6F9FE);
  /// שומר את מה שמקלידים בשדה החיפוש של הרכבים.
  final searchController = TextEditingController();
  /// שומר את מה שמקלידים בחיפוש החניונים.
  final parkingSearchController = TextEditingController();
  /// שעון שמפעיל רענון אוטומטי של הנתונים.
  Timer? refreshTimer;
  /// קובע אם להציג עיגול טעינה בזמן שהנתונים מגיעים.
  bool loading = true;
  /// הטקסט שמופיע כרגע בחיפוש הרכבים.
  String search = '';
  /// הטקסט שמופיע כרגע בחיפוש החניונים.
  String parkingSearch = '';
  /// התאריך שנבחר בלוח השנה. כשהוא ריק מוצגים כל התאריכים.
  DateTime? selectedDate;
  /// רשימת ביקורי הרכבים שנטענה כרגע מהשרת.
  List<Map<String, dynamic>> sessions = [];
  /// רשימת החניונים הפעילים שנקראו מהשרת.
  List<Map<String, dynamic>> parkingLots = [];
  /// מציין אם המערכת טוענת עכשיו עוד רכבים.
  bool loadingMore = false;
  /// מציין אם ייתכן שיש עוד רכבים שאפשר לטעון.
  bool hasMore = true;
  /// מספר קבוצת הרשומות שנטענה לאחרונה.
  int pageNumber = 0;
  static const int pageSize = 200;
  /// מילת החיפוש שנשלחת בפועל ל-Supabase.
  String serverSearch = '';
  /// שעון שמחכה מעט אחרי ההקלדה לפני ביצוע החיפוש.
  Timer? searchDebounce;
  /// מספר שמאפשר להתעלם מתשובה ישנה כאשר מתחיל חיפוש חדש.
  int requestId = 0;
  @override
  /// מופעלת כשהדף נפתח. טוענת נתונים ומרעננת את רשימת הרכבים והחניונים כל דקה. אפשר לשנות את זמן הרענון כאן.
  void initState() {
    super.initState();
    loadAll();
    refreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) async {
        await loadParkingLots();
        await loadSessions(silent: true);
      },
    );
  }
  @override
  /// מופעלת כשעוזבים את הדף. עוצרת שעונים ומנקה שדות חיפוש כדי שלא ימשיכו לפעול ברקע.
  void dispose() {
    refreshTimer?.cancel();
    searchDebounce?.cancel();
    searchController.dispose();
    parkingSearchController.dispose();
    super.dispose();
  }
  /// מחזירה את תחילת היום שנבחר, בשעה 00:00. משמשת לסינון לפי תאריך.
  DateTime startOfDay(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }
  /// מחזירה את תחילת היום שאחרי התאריך שנבחר. כך החיפוש כולל יום אחד בלבד.
  DateTime endOfDay(DateTime value) {
    return startOfDay(value).add(const Duration(days: 1));
  }
  /// ממירה תאריך לפורמט של השרת. שינוי הפורמט עלול להשפיע על חיפוש לפי תאריך.
  String apiDate(DateTime value) {
    return value.toUtc().toIso8601String();
  }
  /// מציגה תאריך בצורה יום/חודש/שנה. אפשר לשנות כאן את סדר התצוגה.
  String formatDate(DateTime? value) {
    if (value == null) return 'כל התאריכים';
    return '${value.day.toString().padLeft(2, '0')}/'
        '${value.month.toString().padLeft(2, '0')}/'
        '${value.year}';
  }
  /// מסירה מקפים וסימנים ממספר רכב ומשאירה רק ספרות, לצורך חיפוש והשוואה.
  String normalizePlate(String value) {
    return value.replaceAll(RegExp(r'[^0-9]'), '');
  }
  /// מוסיפה מקפים למספרי רכב בני 7 או 8 ספרות. כאן משנים את צורת הצגת המספר.
  String formatPlateForDb(String value) {
    final digits = normalizePlate(value);
    if (digits.length == 8) {
      return '${digits.substring(0, 3)}-${digits.substring(3, 5)}-${digits.substring(5)}';
    }
    if (digits.length == 7) {
      return '${digits.substring(0, 2)}-${digits.substring(2, 5)}-${digits.substring(5)}';
    }
    return value.trim();
  }
  /// מוצאת את מספר הזיהוי של חניון מתוך הרשומה במסד הנתונים.
  int parkingLotId(Map<String, dynamic> parking) {
    return asInt(
      parking['id'] ??
          parking['parking_id'] ??
          parking['lot_id'] ??
          0,
    );
  }
  // תעריף יומי לפי יום הכניסה בישראל. שישי ושבת יכולים לקבל מחיר נפרד.
  double _dayRate(Map<String, dynamic> lot, DateTime entry, {bool student = false}) {
    final regular = asDouble(lot['daily_max']);
    final weekend = asDouble(lot['weekend_daily_price']);
    final studentPrice = asDouble(lot['student_daily_price']);
    if (student && studentPrice > 0) return studentPrice;
    final local = entry.toLocal(); // החישוב הסופי מאומת בצד Supabase לפי Asia/Jerusalem.
    if ((local.weekday == DateTime.friday || local.weekday == DateTime.saturday) && weekend > 0) {
      return weekend;
    }
    return regular;
  }

  /// מחשבת מחיר חניה לפי דקות, מחיר לדקה, זמן חסד ותקרה יומית. שינוי הנוסחה משנה את המחיר המחושב.
  double calcPrice({
    required int minutes,
    required double pricePerMinute,
    required double dailyMax,
    required int graceMinutes,
    bool student = false,
    DateTime? entryTime,
    Map<String, dynamic>? parking,
  }) {
    final billableMinutes = minutes - graceMinutes;
    if (billableMinutes <= 0) return 0;
    // מחיר 0 לדקה + תעריף יומי => חניה מחויבת לפי ימים (לא בחינם).
    if (pricePerMinute <= 0 && dailyMax > 0) {
      final days = (billableMinutes + 1439) ~/ 1440;
      double total = 0;
      for (var day = 0; day < days; day++) {
        final tariffDay = entryTime?.add(Duration(minutes: graceMinutes + day * 1440));
        total += parking != null && tariffDay != null
            ? _dayRate(parking, tariffDay, student: student)
            : dailyMax;
      }
      return double.parse(total.toStringAsFixed(2));
    }
    final rawFullDayCharge = pricePerMinute * 1440;
    final fullDayCharge = dailyMax > 0
        ? min(rawFullDayCharge, dailyMax)
        : rawFullDayCharge;
    final fullDays = billableMinutes ~/ 1440;
    final remainingMinutes = billableMinutes % 1440;
    double total = fullDays * fullDayCharge;
    if (remainingMinutes > 0) {
      final partialCharge = remainingMinutes * pricePerMinute;
      total += dailyMax > 0 ? min(partialCharge, dailyMax) : partialCharge;
    }
    return double.parse(total.toStringAsFixed(2));
  }
  /// בוחרת באופן אקראי כמה זמן רכב יישאר בחניון. אפשר לשנות כאן את טווחי משכי החניה ואת הסיכויים.
  int randomDurationMinutes(Random random) {
    final bucket = random.nextInt(100);
    if (bucket < 25) {
      return 10 + random.nextInt(60); // short stay
    }
    if (bucket < 55) {
      return 70 + random.nextInt(300); // a few hours
    }
    if (bucket < 80) {
      return 370 + random.nextInt(1070); // up to 24h
    }
    return 1440 + random.nextInt(3 * 1440); // 1-4 days
  }
  /// מייצרת מספר רכב אקראי בן 7 או 8 ספרות לצורכי סימולציה.
  String randomPlate(Random random) {
    final length = random.nextBool() ? 7 : 8;
    final digits = List.generate(length, (_) => random.nextInt(10)).join();
    return formatPlateForDb(digits);
  }
  /// בוחרת תאריך ושעת כניסה אקראיים מתוך 14 הימים האחרונים. אפשר לשנות את מספר הימים ואת טווח השעות.
  DateTime randomEntryTime(Random random, DateTime now) {
    final daysBack = random.nextInt(14); // today or up to 13 days back
    final hour = random.nextInt(24);
    final minute = random.nextInt(60);
    final baseDay = DateTime(now.year, now.month, now.day).subtract(
      Duration(days: daysBack),
    );
    return baseDay.add(Duration(hours: hour, minutes: minute));
  }
  // true רק אם המנהל סימן פטור לסוג הנכה המסוים בחניון.
  // קורא את ipi_features, אותו שדה שטופס המנהל מעדכן ב-Supabase.
  bool disabledExemptForLot(Map<String, dynamic> lot, String rawType) {
    final type = rawType.toLowerCase().trim();
    final kind = (type == 'disabled_regular')
        ? 'disabled_regular'
        : (type == 'disabled_wheelchair' || type == 'wheelchair')
            ? 'disabled_wheelchair'
            : null;
    if (kind == null) return false; // תו נכה ישן לא מקבל פטור לא מוכח.
    final raw = lot['ipi_features'];
    if (raw is List) return raw.map((e) => e.toString()).contains(kind);
    // תאימות לעמודות ישנות, רק כאשר אין מערך מאפיינים.
    final legacy = lot[kind];
    return legacy == true || legacy?.toString().toLowerCase() == 'true';
  }

  /// מכינה את כל פרטי ביקור של רכב: כניסה, יציאה, מחיר, שם וסטטוס תשלום. אפשר לשנות כאן את הסיכויים, אבל לא את שמות השדות בלי התאמה ל-Supabase.
  Map<String, dynamic> buildSessionRow({
    required String plate,
    required String customer,
    required Map<String, dynamic> parking,
    required DateTime entryTime,
    required Random random,
    int? durationMinutes,
    bool? stillParking,
    bool isVerifiedStudent = false, // רק אם מספר הרכב אומת בטבלת student_vehicles.
    String vehicleType = 'regular', // רגיל, נכה רגיל, נכה כיסא גלגלים או מנוי.
  }) {
    final effectiveDuration = durationMinutes ?? randomDurationMinutes(random);
    final isStillParking = stillParking ?? (random.nextInt(100) < 16);
    final exitTime = isStillParking
        ? null
        : entryTime.add(Duration(minutes: effectiveDuration));
    final pricePerMinute = asDouble(parking['price_per_minute']);
    // הסכום המקסימלי ליום שנשמר עבור הביקור.
    final dailyMax = asDouble(parking['daily_max']);
    final type = vehicleType.toLowerCase().trim();
    final isDisabled = ['disabled', 'disabled_regular', 'disabled_wheelchair',
      'wheelchair'].contains(type);
    // בודק פטור לפי הסוג המדויק ולפי סימוני המנהל בחניון.
    // disabled_regular וסוג כיסא גלגלים יכולים לקבל פטורים שונים.
    // שדה הפטור הישן disabled_exit_allowed כבר לא קובע פטור לשניהם יחד.
    final disabledFree = isDisabled && disabledExemptForLot(parking, type);
    final isSubscriber = type == 'subscriber' || type == 'subscription';
    final isStudentRate = !isDisabled && !isSubscriber && isVerifiedStudent &&
        asDouble(parking['student_daily_price']) > 0;
    final rateForVisit = pricePerMinute <= 0
        ? _dayRate(parking, entryTime, student: isStudentRate)
        : dailyMax;
    final graceMinutes = asInt(
      parking['grace_minutes'] ?? parking['GRACE_MINUTES'],
    );
    // סכום החניה שנשמר בביקור הזה.
    final totalPrice = (isStillParking || disabledFree || isSubscriber)
        ? 0.0
        : calcPrice(
            minutes: effectiveDuration,
            pricePerMinute: pricePerMinute,
            dailyMax: dailyMax,
            graceMinutes: graceMinutes,
            parking: parking,
            entryTime: entryTime,
            student: isStudentRate,
          );
    // רכב שעדיין חונה יכול להיות ממתין לתשלום; יציאה בתשלום חייבת
    // להיות אחרי תשלום. יציאה בלי תשלום מותרת רק לפטור אמיתי.
    String paymentStatus = 'waiting_payment';
    String paymentMethod = 'none';
    String? endedBy = isStillParking ? null : 'system_simulator';
    String? paidAt;
    if (!isStillParking) {
      if (totalPrice <= 0) {
        paymentStatus = 'not_required';
        if (disabledFree) paymentMethod = 'disabled_permit';
        if (isSubscriber) paymentMethod = 'subscription';
      } else {
        paymentStatus = 'paid';
        // שלושה מסלולי סיום תקינים בסימולציה.
        final methods = ['user_app', 'simulation', 'admin'];
        paymentMethod = methods[random.nextInt(methods.length)];
        paidAt = exitTime!.toUtc().toIso8601String();
        endedBy = paymentMethod == 'admin' ? 'admin' : 'system_simulator';
      }
    }
    return {
      'plate': formatPlateForDb(plate),
      'parking_lot_id': parkingLotId(parking) == 0 ? null : parkingLotId(parking),
      'parking_name': parkingName(parking),
      'entry_time': entryTime.toUtc().toIso8601String(),
      'exit_time': exitTime?.toUtc().toIso8601String(),
      'status': isStillParking ? 'parking' : 'exited',
      'payment_status': paymentStatus,
      'customer_name': customer.trim().isEmpty ? null : customer.trim(),
      'vehicle_source': customer.trim().isEmpty ? 'random' : 'named',
      'vehicle_type': vehicleType,
      'is_student': isStudentRate,
      'price_per_minute': pricePerMinute,
      'daily_max': rateForVisit,
      'grace_minutes': graceMinutes,
      'total_price': totalPrice,
      'payment_method': paymentMethod,
      'ended_by': endedBy,
      'paid_at': paidAt,
    };
  }
  /// בודקת אם מספר הרכב מתאים לחיפוש, גם כשכותבים אותו בלי מקפים.
  bool plateMatchesSearch(dynamic plateValue, String query) {
    final plate = (plateValue ?? '').toString().toLowerCase();
    final normalizedPlate = normalizePlate(plate);
    final normalizedQuery = normalizePlate(query);
    if (plate.contains(query.toLowerCase())) return true;
    if (normalizedQuery.isNotEmpty &&
        normalizedPlate.contains(normalizedQuery)) {
      return true;
    }
    return false;
  }
  /// קוראת את תאריך הכניסה של רכב לצורך מיון וספירה.
  DateTime sessionEntryDate(Map<String, dynamic> session) {
    return DateTime.tryParse((session['entry_time'] ?? '').toString()) ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }
  /// סופרת כמה רשומות יש לכל מספר רכב ברשימה שנטענה כעת.
  Map<String, int> plateEntryCounts() {
    final counts = <String, int>{};
    for (final session in sessions) {
      final key = normalizePlate((session['plate'] ?? '').toString());
      if (key.isEmpty) continue;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }
  /// סופרת כמה מספרי רכב מופיעים יותר מפעם אחת ברשומות שנטענו.
  int repeatedVehiclesCount() {
    return plateEntryCounts().values.where((count) => count > 1).length;
  }
  /// מחשבת מה מספר הכניסה של הרכב מתוך הרשומות שנטענו למסך.
  int entryNumberForSession(Map<String, dynamic> session) {
    final plateKey = normalizePlate((session['plate'] ?? '').toString());
    if (plateKey.isEmpty) return 1;
    final samePlateSessions = sessions.where((item) {
      return normalizePlate((item['plate'] ?? '').toString()) == plateKey;
    }).toList()
      ..sort((a, b) => sessionEntryDate(a).compareTo(sessionEntryDate(b)));
    final currentId = (session['id'] ?? '').toString();
    for (int i = 0; i < samePlateSessions.length; i++) {
      final item = samePlateSessions[i];
      final itemId = (item['id'] ?? '').toString();
      if (currentId.isNotEmpty && itemId == currentId) {
        return i + 1;
      }
      if (currentId.isEmpty &&
          item['plate'] == session['plate'] &&
          item['parking_name'] == session['parking_name'] &&
          item['entry_time'] == session['entry_time']) {
        return i + 1;
      }
    }
    return 1;
  }
  // Full vehicle history must be queried from the database, not from the
  // currently displayed 200-row page (or the selected date).
  final Map<String, List<Map<String, dynamic>>> _vehicleHistoryCache = {};

  /// מביאה מ-Supabase את ההיסטוריה המלאה של מספר רכב, גם אם יש יותר מ-200 רשומות. שומרת את התוצאה זמנית כדי לא לטעון שוב.
  Future<List<Map<String, dynamic>>> _allVisitsForPlate(String plate) async {
    final key = normalizePlate(plate);
    if (key.isEmpty) return [];
    if (_vehicleHistoryCache.containsKey(key)) {
      return _vehicleHistoryCache[key]!;
    }

    // Support both dashed and undashed legacy license-plate formats.
    final options = <String>{
      plate.trim(), key, formatPlateForDb(key),
      if (key.length == 7)
        '${key.substring(0, 3)}-${key.substring(3, 5)}-${key.substring(5)}',
      if (key.length == 8)
        '${key.substring(0, 2)}-${key.substring(2, 5)}-${key.substring(5)}',
    }..removeWhere((v) => v.isEmpty);
    final conditions = options.map((v) => 'plate.eq.$v').join(',');
    const pageSize = 500;
    var offset = 0;
    final result = <Map<String, dynamic>>[];
    while (true) {
      final data = await supabase
          .from('parking_sessions')
          .select('id,plate,parking_lot_id,parking_name,entry_time,exit_time,status')
          .or(conditions)
          .order('entry_time', ascending: false)
          .range(offset, offset + pageSize - 1);
      final page = List<Map<String, dynamic>>.from(data);
      result.addAll(page.where((visit) =>
          normalizePlate((visit['plate'] ?? '').toString()) == key));
      if (page.length < pageSize) break;
      offset += pageSize;
    }
    _vehicleHistoryCache[key] = result;
    return result;
  }

  /// קובעת מפתח לחניון כדי לחבר יחד את הביקורים של אותו רכב באותו חניון.
  String _visitLotKey(Map<String, dynamic> visit) {
    final id = (visit['parking_lot_id'] ?? '').toString().trim();
    if (id.isNotEmpty) return 'id:$id';
    final name = (visit['parking_name'] ?? '').toString().trim().toLowerCase();
    return name.isEmpty ? 'unknown' : 'name:$name';
  }

  /// מוצאת שם ברור לחניון עבור חלון היסטוריית הרכב, ורצוי בעברית אם קיים.
  String _visitLotLabel(Map<String, dynamic> visit) {
    final id = (visit['parking_lot_id'] ?? '').toString().trim();
    if (id.isNotEmpty) {
      for (final lot in parkingLots) {
        if ((lot['id'] ?? '').toString() == id) {
          final display = (lot['name_he'] ?? lot['name_en'] ??
              lot['name'] ?? '').toString().trim();
          if (display.isNotEmpty) return display;
        }
      }
    }
    final name = (visit['parking_name'] ?? '').toString().trim();
    return name.isEmpty ? 'חניון לא מזוהה' : name;
  }

  /// פותחת חלון עם כל הביקורים של רכב, מסודרים לפי חניונים ותאריכים. אפשר לשנות כאן את הכותרות ואת גודל החלון.
  Future<void> showVehicleParkingHistory(Map<String, dynamic> vehicle) async {
    final plate = (vehicle['plate'] ?? '').toString();
    if (normalizePlate(plate).isEmpty) return;
    // Loading dialog provides immediate feedback while fetching all pages.
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('היסטוריית חניונים • ${formatPlateForDb(plate)}'),
        content: SizedBox(
          width: 600,
          height: 420,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _allVisitsForPlate(plate),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                // Do not display technical errors or exception details to users.
                return const Center(child: Text('הנתונים אינם זמינים כרגע'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final visits = snapshot.data!;
              final grouped = <String, List<Map<String, dynamic>>>{};
              for (final visit in visits) {
                grouped.putIfAbsent(_visitLotKey(visit), () => []).add(visit);
              }
              final distinctLots = grouped.length;
              final sortedGroups = grouped.values.toList()
                ..sort((a, b) => b.length.compareTo(a.length));
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('סה״כ כניסות: ${visits.length}  |  חניונים שונים: $distinctLots',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: blue)),
                  const SizedBox(height: 8),
                  const Text('הספירה כוללת את כל התאריכים, גם חניונים שהוסרו מתצוגה.'),
                  const Divider(),
                  Expanded(
                    child: ListView.builder(
                      itemCount: sortedGroups.length,
                      itemBuilder: (context, index) {
                        final entries = sortedGroups[index];
                        return ExpansionTile(
                          title: Text(_visitLotLabel(entries.first),
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${entries.length} כניסות לחניון'),
                          children: entries.map((visit) => ListTile(
                            dense: true,
                            title: Text('כניסה: ${formatDateTime(visit['entry_time'])}'),
                            subtitle: Text('יציאה: ${formatDateTime(visit['exit_time'])}'),
                          )).toList(),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext),
            child: const Text('סגור')),
        ],
      ),
    );
  }

  /// מכינה כיתוב כמו "כניסה 1 מתוך 3" לפי הרשומות שנטענו כרגע.
  String entryCountText(Map<String, dynamic> session) {
    final plateKey = normalizePlate((session['plate'] ?? '').toString());
    if (plateKey.isEmpty) return 'כניסה 1 מתוך 1';
    final total = plateEntryCounts()[plateKey] ?? 1;
    final current = entryNumberForSession(session);
    return 'כניסה $current מתוך $total';
  }
  /// מציגה תאריך ושעה בשעון המקומי. כאן אפשר לשנות את צורת התאריך והשעה שמופיעה במסך.
  String formatDateTime(dynamic value) {
    if (value == null) return '-';
    final date = DateTime.tryParse(value.toString())?.toLocal();
    if (date == null) return '-';
    return '${formatDate(date)} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }
  /// ממירה נתון למספר עם נקודה עשרונית. אם אין מספר תקין, מחזירה 0.
  double asDouble(dynamic value) {
    return double.tryParse((value ?? 0).toString()) ?? 0;
  }
  /// ממירה נתון למספר שלם. אם אין מספר תקין, מחזירה 0.
  int asInt(dynamic value) {
    return int.tryParse((value ?? 0).toString()) ?? 0;
  }
  /// מציגה שם לקוח, ואם אין שם מציגה "ללא שם".
  String customerName(Map<String, dynamic> session) {
    final value = (session['customer_name'] ?? '').toString().trim();
    return value.isEmpty ? 'ללא שם' : value;
  }
  /// מחליפה את סוג מקור הרכב בטקסט בעברית: עם שם או בלי שם.
  String sourceText(dynamic value) {
    switch ((value ?? '').toString()) {
      case 'named':
        return 'רכב עם שם';
      case 'random':
        return 'רכב ללא שם';
      default:
        return '-';
    }
  }
  /// מחליפה את סטטוס החניה לטקסט בעברית, למשל "חונה עכשיו".
  String statusText(dynamic value) {
    switch ((value ?? '').toString()) {
      case 'parking':
        return 'חונה עכשיו';
      case 'exited':
        return 'יצא';
      default:
        return (value ?? '-').toString();
    }
  }
  /// מחליטה איזה הסבר תשלום להציג לפי סטטוס התשלום והדרך שבה שולם.
  String paymentText(Map<String, dynamic> session) {
    final type = (session['vehicle_type'] ?? 'regular').toString();
    final status = (session['status'] ?? '').toString();
    final paymentStatus = (session['payment_status'] ?? '').toString();
    final paymentMethod = (session['payment_method'] ?? '').toString();
    // ביקורי דוגמה: מציגים ללקוח הניהולי מה בדיוק קרה, לפי demo_case ב-DB.
    final demoCase = (session['demo_case'] ?? '').toString();
    if (type == 'subscriber') return 'מנוי - ללא תשלום';
    if (demoCase == 'paid_at_parking' && paymentStatus == 'paid') {
      return 'שולם בחניון (סימולציה)';
    }
    if (demoCase == 'admin_exit_waiting') {
      return paymentStatus == 'paid'
          ? 'הוצא ע״י מנהל - שולם'
          : 'חריגה בנתוני הדגמה: נדרש תיקון';
    }
    if (demoCase == 'admin_paid' && paymentStatus == 'paid') {
      return 'שולם ע״י מנהל';
    }
    if (demoCase == 'student_paid' && paymentStatus == 'paid') {
      return 'סטודנט - שולם';
    }
    if (demoCase == 'student_waiting' && paymentStatus == 'waiting_payment') {
      return 'סטודנט - ממתין לתשלום';
    }
    if (paymentStatus == 'not_required') return 'לא נדרש תשלום';
    if (status == 'parking') return 'עדיין בחניון';
    if (paymentStatus == 'paid' && paymentMethod == 'simulation') {
      return 'שולם בסימולציה';
    }
    if (paymentStatus == 'paid' && paymentMethod == 'admin') {
      return 'שולם דרך ADMIN';
    }
    if (paymentStatus == 'paid' && paymentMethod == 'user_app') {
      return 'שולם באפליקציית USER';
    }
    if (paymentStatus == 'waiting_payment') {
      return status == 'parking'
          ? 'חונה - ממתין לתשלום באפליקציה'
          : 'חריגה: יצא ללא אישור תשלום';
    }
    return paymentStatus.isEmpty ? '-' : paymentStatus;
  }
  // מחזיר תיאור קצר של תרחיש הסימולציה שנשמר ב-DB.
  String demoCaseDescription(dynamic value) {
    switch ((value ?? '').toString()) {
      case 'paid_at_parking': return 'שולם בחניון';
      case 'waiting_app': return 'ממתין לתשלום באפליקציה';
      case 'admin_exit_waiting': return 'יציאה ע״י מנהל (נתון ישן לבדיקה)';
      case 'admin_paid': return 'שולם דרך המנהל';
      case 'subscriber': return 'מנוי ללא חיוב';
      case 'student_paid': return 'סטודנט מאומת - שולם';
      case 'student_waiting': return 'סטודנט מאומת - ממתין';
      case 'paid_in_app': return 'שולם באפליקציה';
      case 'parking_now': return 'חונה כרגע';
      case 'grace_free': return 'יצא בזמן חסד';
      default: return '';
    }
  }

  /// מתרגמת קודי אמצעי תשלום לשמות ברורים, כמו USER APP או סימולציה.
  String paymentMethodText(dynamic value) {
    switch ((value ?? '').toString()) {
      case 'simulation':
        return 'סימולציה';
      case 'user_app':
        return 'USER APP';
      case 'admin':
        return 'ADMIN';
      case 'subscription':
        return 'מנוי';
      case 'disabled_permit':
        return 'אישור נכה';
      case 'none':
        return '-';
      default:
        return (value ?? '-').toString();
    }
  }
  /// מציגה מי ביצע את היציאה: המנהל, האפליקציה או הסימולטור.
  String endedByText(dynamic value) {
    switch ((value ?? '').toString()) {
      case 'system_simulator':
        return 'סימולטור';
      case 'user_app':
        return 'USER APP';
      case 'admin':
        return 'ADMIN';
      default:
        return (value ?? '-').toString();
    }
  }
  /// מתרגמת את סוג הרכב לשם בעברית: רגיל, מנוי או נכה.
  String vehicleTypeText(dynamic value) {
    switch ((value ?? '').toString()) {
      case 'disabled_regular':
        return 'נכה רגיל';
      case 'disabled':
        return 'נכה'; // הרשומה הישנה אינה מפרטת סוג נכות.
      case 'disabled_wheelchair':
      case 'wheelchair':
        return 'נכה כיסא גלגלים';
      case 'subscriber':
        return 'מנוי';
      case 'regular':
        return 'רגיל';
      case 'student':
        return 'סטודנט';
      default:
        return (value ?? 'רגיל').toString();
    }
  }
  /// מוצאת את שם החניון ברשומת חניון. כרגע מעדיפה את השם באנגלית.
  String parkingName(Map<String, dynamic> p) {
    return (p['name_en'] ??
            p['name'] ??
            p['display_name'] ??
            'Parking')
        .toString();
  }
  /// טוענת מחדש את החניונים ואת רשומות הרכבים. מופעלת גם בכפתור הרענון.
  Future<void> loadAll() async {
    if (mounted) setState(() => loading = true);
    try {
      await loadParkingLots();

      await loadSessions(silent: true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }
  // Server-side paging ensures searches also reach old DB records.
  /// טוענת רכבים מ-Supabase לפי התאריך והחיפוש. מביאה עד pageSize רשומות בכל פעם, עם אפשרות "טען עוד".
  Future<void> loadSessions({bool silent = false, bool append = false}) async {
    if (append && (loadingMore || !hasMore)) return;
    final myRequest = append ? requestId : ++requestId;
    if (mounted) {
      setState(() {
        if (!append) {
          pageNumber = 0;
          hasMore = true;
        }
        loadingMore = true;
      });
    }
    try {
      final nextPage = append ? pageNumber + 1 : 0;
      final from = nextPage * pageSize;
      final to = from + pageSize - 1;
      // Start with Supabase query, not a local 3,000-record snapshot.
      var query = supabase.from('parking_sessions').select();
      if (selectedDate != null) {
        query = query
            .gte('entry_time', startOfDay(selectedDate!).toUtc().toIso8601String())
            .lt('entry_time', endOfDay(selectedDate!).toUtc().toIso8601String());
      }
      final term = serverSearch.trim();
      if (term.isNotEmpty) {
        final safe = term.replaceAll(RegExp(r'[,().%*]'), '').trim();
        final digits = normalizePlate(safe);
        final formatted = formatPlateForDb(digits);
        // Both dashed and plain-number plates; plus name/lot searches.
        final conditions = <String>[
          'plate.ilike.%$safe%',
          'customer_name.ilike.%$safe%',
          'parking_name.ilike.%$safe%',
        ];
        if (digits.length == 7 || digits.length == 8) {
          if (formatted != safe) conditions.add('plate.ilike.%$formatted%');
        }
        query = query.or(conditions.join(','));
      }
      final data = await query
          .order('entry_time', ascending: false)
          .order('id', ascending: false)
          .range(from, to);
      if (!mounted || myRequest != requestId) return;
      final fresh = List<Map<String, dynamic>>.from(data);
      _vehicleHistoryCache.clear();
      setState(() {
        sessions = append ? [...sessions, ...fresh] : fresh;
        pageNumber = nextPage;
        hasMore = fresh.length == pageSize;
      });
    } catch (error) {
      if (!silent) showError(error);
    } finally {
      if (mounted && myRequest == requestId) {
        setState(() => loadingMore = false);
      }
    }
  }

  /// מתחילה חיפוש אחרי 350 אלפיות שנייה מההקלדה, כדי לא לבצע בקשת שרת על כל אות.
  void changeSearch(String value) {
    setState(() => search = value);
    searchDebounce?.cancel();
    searchDebounce = Timer(const Duration(milliseconds: 350), () {
      serverSearch = value;
      loadSessions(silent: false);
    });
  }

  /// מביאה את רשימת החניונים מ-Supabase ומציגה רק חניונים פעילים.
  Future<void> loadParkingLots() async {
    try {
      final response = await supabase
          .from('parking_lots')
          .select()
          .order('id', ascending: true);
      if (!mounted) return;
      setState(() {
        parkingLots = List<Map<String, dynamic>>.from(response)
            .where((p) => p['is_active'] != false).toList();
      });
    } catch (e) {
      showError(e);
    }
  }
  /// רושמת שגיאת טעינה בחלון הפיתוח. אינה מציגה הודעת שגיאה למשתמש.
  void showError(Object error) {
    // Keep diagnostic information for developers without showing a snackbar.
    debugPrint('CarSimulatorScreen data load failed: $error');
  }
  /// מחזירה את רשימת הרכבים שכבר נטענה מהשרת.
  List<Map<String, dynamic>> filteredSessions() => sessions;

  /// מסננת את רשימת החניונים לפי שם, עיר או כתובת.
  List<Map<String, dynamic>> filteredParkingLots() {
    final q = parkingSearch.trim().toLowerCase();
    if (q.isEmpty) return parkingLots;
    return parkingLots.where((p) {
      final name = parkingName(p).toLowerCase();
      final city = (p['city'] ?? '').toString().toLowerCase();
      final address = (p['address'] ?? '').toString().toLowerCase();
      final addressAr = (p['address_ar'] ?? '').toString().toLowerCase();
      return name.contains(q) ||
          city.contains(q) ||
          address.contains(q) ||
          addressAr.contains(q);
    }).toList();
  }
  /// פותחת לוח שנה. אחרי בחירת תאריך מביאה רק רכבים שנכנסו באותו יום.
  Future<void> chooseDate() async {
    // תאריכים עתידיים חסומים. בכל פתיחה של הלוח בודקים מחדש מה התאריך היום.
    // אחרי 00:00 היום החדש יהיה זמין בפעם הבאה שפותחים את הלוח.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = selectedDate != null && !selectedDate!.isAfter(today)
        ? selectedDate!
        : today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024, 1, 1),
      lastDate: today,
    );
    if (picked == null || !mounted) return;
    // בדיקה נוספת למקרה ששעון המכשיר השתנה בזמן שהלוח היה פתוח.
    final current = DateTime.now();
    final currentDay = DateTime(current.year, current.month, current.day);
    if (picked.isAfter(currentDay)) return;
    setState(() {
      selectedDate = picked;
    });
    await loadSessions();
  }
  /// מבטלת את סינון התאריך ומטעינה מחדש את הרשומות.
  Future<void> showAllDates() async {
    setState(() {
      selectedDate = null;
    });
    await loadSessions();
  }
  /// מנקה את חיפוש הרכבים ואת התאריך שנבחר ומטעינה את הרשימה מחדש.
  Future<void> clearSearchAndDate() async {
    searchController.clear();
    serverSearch = "";
    setState(() {
      search = '';
      selectedDate = null;
    });
    await loadSessions();
  }
  @override
  /// בונה את כל המסך: כותרת עליונה, חיפוש, נתונים מסכמים, חניונים ורכבים. כאן משנים את סידור המסך.
  Widget build(BuildContext context) {
    final list = filteredSessions();
    // סופרת כמה רכבים עדיין מסומנים כחונים ברשומות שהתקבלו.
    final activeCount =
        sessions.where((s) => s['status'] == 'parking').length;
    // סופרת כמה רכבים יצאו ברשומות שהתקבלו.
    final exitedCount =
        sessions.where((s) => s['status'] == 'exited').length;
    // סופרת כמה רכבים שילמו ברשומות שהתקבלו.
    final paidCount =
        sessions.where((s) => s['payment_status'] == 'paid').length;
    // סופרת כמה רשומות כוללות שם של לקוח.
    final namedCount = sessions.where((s) {
      return (s['customer_name'] ?? '').toString().trim().isNotEmpty;
    }).length;
    // סופרת כמה רשומות בלי שם לקוח.
    final unnamedCount = sessions.length - namedCount;
    // מחברת את הסכום הכולל של הרשומות שנטענו; זה לא בהכרח סכום ששולם בפועל.
    final income = sessions.fold<double>(
      0,
      (sum, s) => sum + asDouble(s['total_price']),
    );
    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: blue,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.local_parking),
            SizedBox(width: 10),
            Text(
              'IPI Car Simulator',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'רענון',
            onPressed: loadAll,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(color: blue),
            )
          : Column(
              children: [
                _buildTopControls(),
                _buildStats(
                  activeCount: activeCount,
                  exitedCount: exitedCount,
                  paidCount: paidCount,
                  namedCount: namedCount,
                  unnamedCount: unnamedCount,
                  income: income,
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 1050) {
                        return _buildVehicleList(list);
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 330,
                            child: _buildParkingPanel(),
                          ),
                          Expanded(
                            child: _buildVehicleList(list),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
  /// בונה את שורת החיפוש וכפתורי התאריך, כל התאריכים וניקוי.
  Widget _buildTopControls() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: searchController,
              onChanged: changeSearch,
              decoration: InputDecoration(
                hintText:
                    'חיפוש מספר רכב 7/8 ספרות / שם / חניון / סטטוס / תשלום / סוג רכב',
                prefixIcon: const Icon(Icons.search, color: blue),
                suffixIcon: search.trim().isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, color: blue),
                        onPressed: () {
                          searchController.clear();
                          changeSearch('');
                        },
                      ),
                filled: true,
                fillColor: lightBlue,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: blue,
              side: const BorderSide(color: blue),
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 18,
              ),
            ),
            onPressed: chooseDate,
            icon: const Icon(Icons.calendar_month),
            label: Text(formatDate(selectedDate)),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: blue,
              side: const BorderSide(color: blue),
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 18,
              ),
            ),
            onPressed: showAllDates,
            icon: const Icon(Icons.date_range),
            label: const Text('כל התאריכים'),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: blue,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 18,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: clearSearchAndDate,
            icon: const Icon(Icons.cleaning_services),
            label: const Text('נקה'),
          ),
        ],
      ),
    );
  }
  /// בונה את הכרטיסים שמציגים כמה רכבים נכנסו, חונים, יצאו, שילמו ועוד. כאן משנים כותרות וסדר הכרטיסים.
  Widget _buildStats({
    required int activeCount,
    required int exitedCount,
    required int paidCount,
    required int namedCount,
    required int unnamedCount,
    required double income,
  }) {
    // רשימת כרטיסי המספרים בראש הדף. אפשר לשנות כאן כותרות, סדר וסמלים.
    final cards = [
      _StatData('סה״כ כניסות', sessions.length.toString(), Icons.directions_car),
      _StatData('חונים', activeCount.toString(), Icons.local_parking),
      _StatData('יצאו', exitedCount.toString(), Icons.logout),
      _StatData('שולמו', paidCount.toString(), Icons.payments),
      _StatData('עם שם', namedCount.toString(), Icons.person),
      _StatData('בלי שם', unnamedCount.toString(), Icons.shuffle),
      _StatData('הכנסה', '₪${income.toStringAsFixed(2)}', Icons.attach_money),
    ];
    return SizedBox(
      height: 112,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final item = cards[index];
          return Container(
            width: 160,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: lightBlue,
                  child: Icon(item.icon, color: blue),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: blue,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        item.title,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
  /// בונה את רשימת החניונים בצד, כולל חיפוש, מספר מקומות פנויים ומחירון.
  Widget _buildParkingPanel() {
    final list = filteredParkingLots();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 6, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
            child: Column(
              children: [
                const Row(
                  children: [
                    Icon(Icons.local_parking, color: blue),
                    SizedBox(width: 8),
                    Text(
                      'PARKING_LOTS',
                      style: TextStyle(
                        color: blue,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: parkingSearchController,
                  onChanged: (value) {
                    setState(() => parkingSearch = value);
                  },
                  decoration: InputDecoration(
                    hintText: 'חיפוש חניון',
                    prefixIcon: const Icon(Icons.search, color: blue),
                    filled: true,
                    fillColor: lightBlue,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: list.length,
              itemBuilder: (context, index) {
                final p = list[index];
                final available = asInt(p['available_spots']);
                final total = asInt(
                  p['total_spots'] ?? p['available_spots'],
                );
                final price = asDouble(p['price_per_minute']);
                // הסכום המקסימלי ליום שנשמר עבור הביקור.
                final dailyMax = asDouble(p['daily_max']);
                // מספר דקות החסד שנשמר עבור הביקור.
                final grace = asInt(p['grace_minutes']);
                return Card(
                  color: lightBlue,
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          parkingName(p),
                          style: const TextStyle(
                            color: blue,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text('פנוי: $available / $total'),
                        if (price > 0) Text('מחיר לדקה: ₪${price.toStringAsFixed(2)}'),
                        Text('זמן חסד: $grace דקות'),
                        Text(price <= 0 ? 'מחיר יומי: ₪${dailyMax.toStringAsFixed(2)}' : 'תקרה יומית: ₪${dailyMax.toStringAsFixed(2)}'),
                        if (price <= 0 && asDouble(p['weekend_daily_price']) > 0)
                          Text('שישי–שבת: ₪${asDouble(p['weekend_daily_price']).toStringAsFixed(2)} ליום'),
                        if (price <= 0 && asDouble(p['student_daily_price']) > 0)
                          Text('לסטודנט מאומת: ₪${asDouble(p['student_daily_price']).toStringAsFixed(2)} ליום'),
                        // מציג פטור נפרד לכל אחד משני סוגי הנכים.
                        Text('נכה רגיל: ${disabledExemptForLot(p, 'disabled_regular') ? 'פטור מתשלום' : 'משלם לפי התעריף'}'),
                        Text('נכה עם כיסא גלגלים: ${disabledExemptForLot(p, 'disabled_wheelchair') ? 'פטור מתשלום' : 'משלם לפי התעריף'}'),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
  /// מציגה את כרטיסי הרכבים שנמצאו ואת הכפתור לטעינת עוד 200 רשומות.
  Widget _buildVehicleList(List<Map<String, dynamic>> list) {
    return Container(
      margin: const EdgeInsets.fromLTRB(6, 0, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(Icons.directions_car, color: blue),
                const SizedBox(width: 8),
                Text(
                  'פרטי רכבים - ${formatDate(selectedDate)}',
                  style: const TextStyle(
                    color: blue,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                Text(
                  '${list.length} תוצאות',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: list.isEmpty
                ? const Center(
                    child: Text('אין רכבים בתאריך/חיפוש שנבחר'),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: list.length + 1,
                    itemBuilder: (context, index) {
                      if (index == list.length) {
                        if (!hasMore) return const Padding(
                          padding: EdgeInsets.all(12),
                          child: Center(child: Text('סוף הרשומות')),
                        );
                        return Padding(
                          padding: const EdgeInsets.all(12),
                          child: Center(child: TextButton.icon(
                            onPressed: loadingMore ? null : () => loadSessions(append: true),
                            icon: loadingMore
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.expand_more),
                            label: Text(loadingMore ? 'טוען...' : 'טען עוד 200 רשומות'),
                          )),
                        );
                      }
                      return _vehicleCard(list[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }
  /// בונה כרטיס של רכב אחד עם מספר רכב, שם, תאריכים, תשלום, מחיר וקישור להיסטוריה.
  Widget _vehicleCard(Map<String, dynamic> s) {
    // בודקת אם ביקור סומן כשולם או שלא נדרש עליו תשלום.
    final paid = s['payment_status'] == 'paid' || s['payment_status'] == 'not_required';
    // בודקת אם הרכב עדיין נמצא בחניון.
    final active = s['status'] == 'parking';
    // סכום החניה שנשמר בביקור הזה.
    final totalPrice = asDouble(s['total_price']);
    // המחיר לדקה שנשמר עבור הביקור.
    final ppm = asDouble(s['price_per_minute']);
    // הסכום המקסימלי ליום שנשמר עבור הביקור.
    final dailyMax = asDouble(s['daily_max']);
    // מספר דקות החסד שנשמר עבור הביקור.
    final grace = asInt(s['grace_minutes']);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFF0F7FF) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: active ? blue2 : border,
          width: active ? 1.4 : 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: lightBlue,
                child: Icon(
                  active ? Icons.local_parking : Icons.directions_car,
                  color: blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${formatPlateForDb((s['plate'] ?? '-').toString())}  •  ${customerName(s)}',
                      style: const TextStyle(
                        color: blue,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${s['parking_name'] ?? '-'}  •  ${sourceText(s['vehicle_source'])}  •  ${entryCountText(s)}',
                    ),
                  ],
                ),
              ),
              _badge(
                statusText(s['status']),
                active ? blue : Colors.grey.shade700,
              ),
              const SizedBox(width: 7),
              _badge(
                paymentText(s),
                paid ? Colors.green.shade700 : Colors.orange.shade800,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Wrap(
            spacing: 20,
            runSpacing: 10,
            children: [
              _detail('מספר כניסה לרכב', entryCountText(s)),
              if (demoCaseDescription(s['demo_case']).isNotEmpty)
                _detail('תרחיש הדגמה', demoCaseDescription(s['demo_case'])),
              TextButton.icon(
                onPressed: () => showVehicleParkingHistory(s),
                icon: const Icon(Icons.account_tree_outlined),
                label: const Text('כמה חניונים שונים? כל הכניסות והימים'),
              ),
              _detail('כניסה', formatDateTime(s['entry_time'])),
              _detail('יציאה', formatDateTime(s['exit_time'])),
              _detail('שולם בתאריך', formatDateTime(s['paid_at'])),
              _detail('סוג רכב', (s['vehicle_type'] == 'student' ||
                  (s['is_student'] == true && (s['vehicle_type'] == 'regular' || s['vehicle_type'] == null)))
                  ? 'סטודנט מאומת' : vehicleTypeText(s['vehicle_type'])),
              if (ppm > 0) _detail('מחיר לדקה', '₪${ppm.toStringAsFixed(2)}'),
              _detail('זמן חסד', '$grace דקות'),
              _detail(ppm <= 0 ? 'מחיר יומי' : 'תקרה יומית', '₪${dailyMax.toStringAsFixed(2)}'),
              _detail(
                'סכום לתשלום',
                '₪${totalPrice.toStringAsFixed(2)}',
              ),
              _detail(
                'אמצעי תשלום',
                paymentMethodText(s['payment_method']),
              ),
              _detail(
                'יציאה על ידי',
                endedByText(s['ended_by']),
              ),
            ],
          ),
        ],
      ),
    );
  }
  /// בונה תווית קטנה וצבעונית לסטטוס הרכב או התשלום. אפשר לשנות כאן את הריווח והפינות.
  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
  /// בונה שורת מידע קצרה עם כותרת וערך, למשל "זמן חסד: 10 דקות".
  Widget _detail(String title, String value) {
    return SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
class _StatData {
  final String title;
  final String value;
  final IconData icon;
  const _StatData(this.title, this.value, this.icon);
}




