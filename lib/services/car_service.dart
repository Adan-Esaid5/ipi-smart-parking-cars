import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

/*
 * CarService
 * שירות לניהול רכבים וחניות.
 */

class CarService {
  final supabase = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> getParkingLots() async {
    final response = await supabase
        .from('parking_lots')
        .select();

    return List<Map<String, dynamic>>.from(response);
  }

  String generatePlate() {
    final random = Random();

    return
        "${100 + random.nextInt(900)}-"
        "${10 + random.nextInt(90)}-"
        "${100 + random.nextInt(900)}";
  }

  Future<void> insertCar({
    required Map<String, dynamic> parking,
  }) async {

    final available =
        parking['available_spots'] ?? 0;

    if (available <= 0) return;

    final plate = generatePlate();

    await supabase.from('parking_sessions').insert({
      'plate': plate,
      'parking_lot_id': parking['id'],
      'parking_name':
          parking['name'] ?? 'Parking',
      'entry_time': DateTime.now().toIso8601String(),
      'status': 'parking',
      'payment_status': 'unpaid',
      'price_per_minute':
          parking['price_per_minute'] ?? 0.5,
      'daily_max':
          parking['daily_max'] ?? 80,
      'grace_minutes':
          parking['GRACE_MINUTES'] ?? 0,
    });

    // הורדת מקום פנוי
    await supabase
        .from('parking_lots')
        .update({
          'available_spots': available - 1,
        })
        .eq('id', parking['id']);
  }

  Future<List<Map<String, dynamic>>> getActiveCars() async {
    final response = await supabase
        .from('parking_sessions')
        .select()
        .eq('status', 'parking')
        .order('entry_time');

    return List<Map<String, dynamic>>.from(response);
  }
}