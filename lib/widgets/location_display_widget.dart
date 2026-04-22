import 'dart:async';

import 'package:detalhes/models/trip.dart';
import 'package:detalhes/widgets/info_row_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';

/// Widget responsável por exibir e gerenciar a exibição da localização atual
class LocationDisplayWidget extends StatefulWidget {
  final Trip? currentTrip;
  final bool isRunning;
  final VoidCallback? onStartService;
  final VoidCallback? onSyncLocations;

  const LocationDisplayWidget({
    super.key,
    this.currentTrip,
    this.isRunning = false,
    this.onStartService,
    this.onSyncLocations,
  });

  @override
  State<LocationDisplayWidget> createState() => _LocationDisplayWidgetState();
}

class _LocationDisplayWidgetState extends State<LocationDisplayWidget> {
  final FlutterBackgroundService _service = FlutterBackgroundService();
  Position? _currentPosition;
  String? _errorMessage;
  StreamSubscription? _locationSubscription;

  @override
  void initState() {
    super.initState();
    _setupLocationUpdates();
  }

  void _setupLocationUpdates() {
    _locationSubscription = _service.on('update_location').listen((data) {
      if (data != null && mounted) {
        setState(() {
          _currentPosition = Position(
            latitude: data['latitude'],
            longitude: data['longitude'],
            accuracy: data['accuracy'],
            timestamp: DateTime.parse(data['timestamp']).toLocal(),
            altitude: 0,
            altitudeAccuracy: 0,
            heading: 0,
            headingAccuracy: 0,
            speed: data['speed'],
            speedAccuracy: 0,
          );
          _errorMessage = null;
        });
      }
    });

    _service.on('location_error').listen((data) {
      if (data != null && data['error'] != null && mounted) {
        setState(() {
          _errorMessage = data['error'];
        });
        _showErrorAlert();
      }
    });
  }

  void _showErrorAlert() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Erro de Localização'),
        content: Text(_errorMessage ?? 'Não foi possível obter a localização.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() {
                _errorMessage = null;
              });
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.currentTrip == null) {
      return const Center(
        child: Text(
          'Valide uma key para começar a compartilhar sua localização',
          style: TextStyle(fontSize: 16, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          widget.isRunning ? 'Serviço em execução' : 'Serviço parado',
          style: TextStyle(
            fontSize: 18,
            color: widget.isRunning ? Colors.green : Colors.grey,
          ),
        ),
        const SizedBox(height: 16),
        // Mensagem com nome do motorista
        Text(
          'Motorista: ${widget.currentTrip!.driverName}',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        // Rota
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.location_on,
              size: 16,
              color: Colors.green,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                widget.currentTrip!.startingPointName,
                style: const TextStyle(fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Icon(
          Icons.arrow_downward,
          size: 16,
          color: Colors.grey,
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.location_on,
              size: 16,
              color: Colors.red,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                widget.currentTrip!.endingPointName,
                style: const TextStyle(fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Key: ${widget.currentTrip!.key}',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        // Ícone de status
        if (_currentPosition != null || widget.isRunning) ...[
          const SizedBox(height: 24),
          GestureDetector(
            onTap: widget.onSyncLocations,
            child: Icon(
              widget.isRunning ? Icons.location_on : Icons.location_off,
              size: 60,
              color: widget.isRunning ? Colors.green : Colors.grey,
            ),
          ),
        ],
        // Informações de localização
        if (_currentPosition != null) ...[
          const SizedBox(height: 16),
          InfoRow(
            label: 'Latitude',
            value: _currentPosition!.latitude.toStringAsFixed(6),
          ),
          InfoRow(
            label: 'Longitude',
            value: _currentPosition!.longitude.toStringAsFixed(6),
          ),
          InfoRow(
            label: 'Precisão',
            value: '${_currentPosition!.accuracy.toStringAsFixed(1)}m',
          ),
          InfoRow(
            label: 'Atualizado',
            value: _formatDate(_currentPosition!.timestamp),
          ),
          InfoRow(label: 'Trip', value: widget.currentTrip!.label),
        ] else if (widget.isRunning) ...[
          const SizedBox(height: 16),
          Text(
            'Aguardando localização...',
            style: TextStyle(
              fontSize: 16,
              color: Colors.orange,
            ),
          ),
        ] else ...[
          const SizedBox(height: 16),
          Text(
            'Serviço parado',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
        ],
        // Botão de controle
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: widget.isRunning ? null : widget.onStartService,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Iniciar'),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
  }
}
