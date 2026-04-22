import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../models/trip.dart';
import '../services/geocoding_service.dart';
import '../services/route_service.dart';

/// Widget que exibe o mapa com a rota da trip
class RouteMapWidget extends StatefulWidget {
  final Trip? currentTrip;
  final Position? currentPosition;

  const RouteMapWidget({
    super.key,
    required this.currentTrip,
    required this.currentPosition,
  });

  @override
  State<RouteMapWidget> createState() => _RouteMapWidgetState();
}

class _RouteMapWidgetState extends State<RouteMapWidget> {
  final MapController _mapController = MapController();
  final GeocodingService _geocodingService = GeocodingService();
  final RouteService _routeService = RouteService();

  LatLng? _startPoint;
  LatLng? _endPoint;
  List<LatLng> _routePoints = [];
  String? _errorMessage;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadRoute();
  }

  @override
  void didUpdateWidget(RouteMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Recarregar rota se a trip mudou
    if (oldWidget.currentTrip?.key != widget.currentTrip?.key) {
      _loadRoute();
    }
  }

  Future<void> _loadRoute() async {
    final trip = widget.currentTrip;
    if (trip == null) {
      setState(() {
        _errorMessage = 'Nenhuma trip disponível';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _startPoint = null;
      _endPoint = null;
      _routePoints = [];
    });

    try {
      // Obter coordenadas do ponto de partida (API ou geocoding)
      if (trip.hasLoadingCoordinates) {
        _startPoint = LatLng(
          trip.loadingLatitude!,
          trip.loadingLongitude!,
        );
      } else if (trip.loadingName != null && trip.loadingName!.isNotEmpty) {
        _startPoint = await _geocodingService.geocode(trip.loadingName!);
      }

      // Obter coordenadas do ponto de chegada (API ou geocoding)
      if (trip.hasUnloadingCoordinates) {
        _endPoint = LatLng(
          trip.unloadingLatitude!,
          trip.unloadingLongitude!,
        );
      } else if (trip.unloadingName != null && trip.unloadingName!.isNotEmpty) {
        _endPoint = await _geocodingService.geocode(trip.unloadingName!);
      }

      // Verificar se conseguiu ambas coordenadas
      if (_startPoint == null || _endPoint == null) {
        setState(() {
          _errorMessage = 'Não foi possível obter as coordenadas dos locais';
          _isLoading = false;
        });
        return;
      }

      // Calcular rota via OSRM
      final routePoints = await _routeService.getRoute(_startPoint!, _endPoint!);

      if (routePoints.isEmpty) {
        setState(() {
          _errorMessage = 'Não foi possível calcular a rota';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _routePoints = routePoints;
        _isLoading = false;
      });

      // Ajustar mapa para mostrar a rota completa
      _fitBounds();
    } catch (e) {
      setState(() {
        _errorMessage = 'Erro ao carregar rota: $e';
        _isLoading = false;
      });
    }
  }

  /// Ajusta o zoom para mostrar toda a rota
  void _fitBounds() {
    if (_startPoint == null || _endPoint == null) return;

    final bounds = LatLngBounds.fromPoints([
      _startPoint!,
      _endPoint!,
      ..._routePoints,
    ]);

    _mapController.move(bounds.center, _mapController.camera.zoom);
    _mapController.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)));
  }

  /// Centraliza o mapa na posição atual do motorista
  void _centerOnCurrentPosition() {
    final pos = widget.currentPosition;
    if (pos != null) {
      _mapController.move(LatLng(pos.latitude, pos.longitude), 16.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.currentTrip;

    if (trip == null) {
      return const Center(
        child: Text('Nenhuma trip disponível'),
      );
    }

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _startPoint ?? const LatLng(-14.235, -51.9253),
            initialZoom: 5.0,
          ),
          children: [
            // Tile layer OpenStreetMap
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'detalhes',
            ),

            // Polyline da rota
            if (_routePoints.isNotEmpty)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _routePoints,
                    color: Colors.blue,
                    strokeWidth: 5.0,
                  ),
                ],
              ),

            // Markers: ponto de partida, chegada e motorista
            MarkerLayer(
              markers: [
                // Ponto de partida (verde)
                if (_startPoint != null)
                  Marker(
                    point: _startPoint!,
                    child: const Icon(
                      Icons.location_on,
                      color: Colors.green,
                      size: 40,
                    ),
                  ),

                // Ponto de chegada (vermelho)
                if (_endPoint != null)
                  Marker(
                    point: _endPoint!,
                    child: const Icon(
                      Icons.location_on,
                      color: Colors.red,
                      size: 40,
                    ),
                  ),

                // Posição atual do motorista (azul)
                if (widget.currentPosition != null)
                  Marker(
                    point: LatLng(
                      widget.currentPosition!.latitude,
                      widget.currentPosition!.longitude,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.directions_car,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),

        // Loading overlay
        if (_isLoading)
          Container(
            color: Colors.black.withValues(alpha: 0.3),
            child: const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Carregando rota...'),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // Mensagem de erro
        if (_errorMessage != null && !_isLoading)
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      onPressed: _loadRoute,
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Botão de centralizar na posição atual
        if (widget.currentPosition != null)
          Positioned(
            right: 16,
            bottom: 100,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: Colors.white,
              onPressed: _centerOnCurrentPosition,
              child: const Icon(Icons.my_location, color: Colors.blue),
            ),
          ),

        // Legenda
        Positioned(
          left: 16,
          bottom: 100,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLegendItem(Colors.green, 'Partida'),
                  _buildLegendItem(Colors.red, 'Chegada'),
                  _buildLegendItem(Colors.blue, 'Sua posição'),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(Icons.location_on, color: color, size: 20),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }
}
