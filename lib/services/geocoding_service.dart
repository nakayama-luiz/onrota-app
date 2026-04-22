import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Serviço de geocoding usando a API gratuita do Nominatim
/// Converte nomes de locais em coordenadas (lat/lng)
class GeocodingService {
  static const String _baseUrl =
      'https://nominatim.openstreetmap.org/search';
  static const String _userAgent = 'detalhes/1.0 (Flutter Location Tracking App)';

  /// Geocodifica um endereço/local e retorna as coordenadas
  ///
  /// Retorna [LatLng] com as coordenadas ou [null] se não encontrar
  /// ou ocorrer erro na requisição.
  Future<LatLng?> geocode(String address) async {
    if (address.trim().isEmpty) {
      return null;
    }

    try {
      final uri = Uri.parse(_baseUrl).replace(queryParameters: {
        'q': address,
        'format': 'json',
        'limit': '1',
        'addressdetails': '1',
      });

      final response = await http
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> results = jsonDecode(response.body);

        if (results.isNotEmpty) {
          final firstResult = results.first as Map<String, dynamic>;
          final lat = double.tryParse(firstResult['lat'] ?? '');
          final lon = double.tryParse(firstResult['lon'] ?? '');

          if (lat != null && lon != null) {
            return LatLng(lat, lon);
          }
        }
      }

      return null;
    } catch (e) {
      print('Erro ao geocodificar endereço "$address": $e');
      return null;
    }
  }

  /// Geocodifica múltiplos endereços sequencialmente
  ///
  /// Respeita o limite de 1 request/segundo do Nominatim.
  /// Retorna lista de [LatLng?] na mesma ordem dos endereços.
  Future<List<LatLng?>> geocodeAll(List<String> addresses) async {
    final results = <LatLng?>[];

    for (int i = 0; i < addresses.length; i++) {
      // Aguarda 1 segundo entre requests (limite do Nominatim)
      if (i > 0) {
        await Future.delayed(const Duration(seconds: 1));
      }

      final result = await geocode(addresses[i]);
      results.add(result);
    }

    return results;
  }
}
