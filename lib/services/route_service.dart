import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Serviço de roteamento usando a API pública do OSRM
/// Calcula a rota entre dois pontos e retorna a lista de coordenadas
class RouteService {
  static const String _baseUrl =
      'http://router.project-osrm.org/route/v1/driving';

  /// Calcula a rota entre dois pontos
  ///
  /// Retorna uma lista de [LatLng] representando a polyline da rota.
  /// Retorna lista vazia se não encontrar rota ou ocorrer erro.
  Future<List<LatLng>> getRoute(LatLng start, LatLng end) async {
    try {
      // Formato: {lon1},{lat1};{lon2},{lat2}
      final coordinates =
          '${start.longitude},${start.latitude};${end.longitude},${end.latitude}';
      final uri = Uri.parse('$_baseUrl/$coordinates').replace(queryParameters: {
        'overview': 'full',
        'geometries': 'geojson',
        'steps': 'false',
      });

      final response = await http.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Verificar se há rotas
        final routes = data['routes'] as List<dynamic>?;
        if (routes == null || routes.isEmpty) {
          print('RouteService: Nenhuma rota encontrada');
          return [];
        }

        // Extrair geometria GeoJSON da primeira rota
        final route = routes.first as Map<String, dynamic>;
        final geometry = route['geometry'] as Map<String, dynamic>?;

        if (geometry == null) {
          print('RouteService: Geometria não encontrada');
          return [];
        }

        // GeoJSON retorna como [longitude, latitude]
        final coordinatesList = geometry['coordinates'] as List<dynamic>?;
        if (coordinatesList == null || coordinatesList.isEmpty) {
          return [];
        }

        // Converter para List<LatLng>
        return coordinatesList.map((coord) {
          final lon = (coord[0] as num).toDouble();
          final lat = (coord[1] as num).toDouble();
          return LatLng(lat, lon);
        }).toList();
      } else {
        print('RouteService: Erro HTTP ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('RouteService: Erro ao calcular rota: $e');
      return [];
    }
  }

  /// Calcula a distância total da rota em metros
  Future<double> getRouteDistance(LatLng start, LatLng end) async {
    try {
      final coordinates =
          '${start.longitude},${start.latitude};${end.longitude},${end.latitude}';
      final uri = Uri.parse('$_baseUrl/$coordinates').replace(queryParameters: {
        'overview': 'false',
        'steps': 'false',
      });

      final response = await http.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final routes = data['routes'] as List<dynamic>?;

        if (routes != null && routes.isNotEmpty) {
          final route = routes.first as Map<String, dynamic>;
          return (route['distance'] as num).toDouble();
        }
      }

      return 0.0;
    } catch (e) {
      print('RouteService: Erro ao calcular distância: $e');
      return 0.0;
    }
  }
}
