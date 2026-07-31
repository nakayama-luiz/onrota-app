import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/trip.dart';

class InstallationStorage {
  static const _secureStorage = FlutterSecureStorage();
  static const String _apiKeyStorageKey = 'client_api_key';
  static const String _cpfStorageKey = 'cpf';
  static const String _tripStorageKey = 'trip_data';

  static Future<String?> getApiKey() {
    return _secureStorage.read(key: _apiKeyStorageKey);
  }

  static Future<String?> saveApiKey(String apiKey) async {
    final normalizedKey = apiKey.trim();
    final previousKey = await getApiKey();
    await _secureStorage.write(key: _apiKeyStorageKey, value: normalizedKey);
    return previousKey;
  }

  static Future<void> clearApiKey() async {
    await _secureStorage.delete(key: _apiKeyStorageKey);
  }

  static Future<String> getCpf() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_cpfStorageKey) ?? '';
  }

  static Future<void> saveCpf(String cpf) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cpfStorageKey, cpf);
  }

  static Future<void> removeCpf() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cpfStorageKey);
  }

  static Future<Trip?> getStoredTrip() async {
    final prefs = await SharedPreferences.getInstance();
    final tripJson = prefs.getString(_tripStorageKey);
    if (tripJson == null || tripJson.isEmpty) {
      return null;
    }
    return Trip.fromJson(jsonDecode(tripJson) as Map<String, dynamic>);
  }

  static Future<void> saveStoredTrip(Trip trip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tripStorageKey, jsonEncode(trip.toJson()));
  }

  static Future<void> removeStoredTrip() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tripStorageKey);
  }
}
