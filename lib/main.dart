import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'data/database_helper.dart';
import 'models/trip.dart';
import 'services/api_service.dart';
import 'widgets/info_row_widget.dart';

/// Obtém a key armazenada nas preferências
Future<String> getStoredKey() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('log_key') ?? '';
}

/// Salva a key nas preferências
Future<void> saveStoredKey(String key) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('log_key', key);
}

/// Obtém a Trip armazenada nas preferências
Future<Trip?> getStoredTrip() async {
  final prefs = await SharedPreferences.getInstance();
  final tripJson = prefs.getString('trip_data');
  if (tripJson == null || tripJson.isEmpty) {
    return null;
  }
  return Trip.fromJson(jsonDecode(tripJson));
}

/// Salva a Trip nas preferências
Future<void> saveStoredTrip(Trip trip) async {
  final prefs = await SharedPreferences.getInstance();
  final tripJson = jsonEncode({
    'id': trip.id,
    'label': trip.label,
    'description': trip.description,
    'status': trip.status,
    'starting_point_id': trip.startingPointId,
    'ending_point_id': trip.endingPointId,
    'key': trip.key,
    'driver_id': trip.driverId,
    'driver_name': trip.driverName,
    'starting_point_name': trip.startingPointName,
    'ending_point_name': trip.endingPointName,
  });
  await prefs.setString('trip_data', tripJson);
}

/// Remove a Trip das preferências
Future<void> removeStoredTrip() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('trip_data');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    // Arquivo .env não encontrado, continuando sem variáveis de ambiente
    print('Aviso: .env não encontrado. Usando valores padrão.');
  }
  await initializeService();
  runApp(const MyApp());
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  // Configurar notificações primeiro
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  await flutterLocalNotificationsPlugin.initialize(
    const InitializationSettings(android: initializationSettingsAndroid),
  );

  // Criar canal de notificação com importância alta para foreground service
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'location_channel',
    'Location Service',
    description: 'Canal para serviço de localização em background',
    importance: Importance.high,
    playSound: false,
    enableVibration: false,
    showBadge: false,
  );

  final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
      flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

  await androidImplementation?.createNotificationChannel(channel);

  // Solicitar permissão de notificação para Android 13+
  await androidImplementation?.requestNotificationsPermission();

  // Configurar o serviço
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'location_channel',
      initialNotificationTitle: 'Monitoramento de Localização',
      initialNotificationContent: 'Serviço em execução',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

/// Envia localizações não enviadas para o endpoint
/// Retorna (true, null) se sucesso, (false, mensagemDeErro) se falhou
Future<(bool, String?)> sendUnsendedLocations() async {
  try {
    final dbHelper = DatabaseHelper.instance;
    final unsendedLocations = await dbHelper.getUnsendedLocations();

    if (unsendedLocations.isEmpty) {
      return (true, null);
    }

    final key = await getStoredKey();

    // Prepara a lista de eventos como JSON
    final events = unsendedLocations.map((location) {
      final locationKey = location['key'];
      final effectiveKey = (locationKey == null || locationKey == '')
          ? key
          : locationKey;
      return {
        'id': location['id'],
        'key': effectiveKey,
        'latitude': location['latitude'],
        'longitude': location['longitude'],
        'timestamp': location['timestamp'],
      };
    }).toList();

    final payload = jsonEncode(events);

    // Envia para o endpoint usando variáveis de ambiente
    final url = 'https://api.nakafest.site/log';

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'x-api-key': '123',
    };

    // Envia para o endpoint
    final response = await http.post(
      Uri.parse(url),
      headers: headers,
      body: payload,
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      // Marca como enviadas
      final ids = unsendedLocations.map((l) => l['id'] as int).toList();
      await dbHelper.markLocationsAsSended(ids);
      print('Localizações enviadas com sucesso: ${ids.length} registros');
      return (true, null);
    } else {
      final errorMsg = 'Erro ${response.statusCode}: ${response.body}';
      print('Erro ao enviar localizações: $errorMsg');
      return (false, errorMsg);
    }
  } on http.ClientException catch (e) {
    final errorMsg =
        'Sem conexão com a internet. Verifique sua rede e tente novamente.';
    print('Erro de conexão ao enviar localizações: $e');
    return (false, errorMsg);
  } catch (e) {
    final errorMsg = 'Erro ao enviar: ${e.toString()}';
    print('Erro ao enviar localizações: $errorMsg');
    return (false, errorMsg);
  }
}

@pragma('vm:entry-point')
void onStart(ServiceInstance? service) async {
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service?.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Envia localizações não enviadas a cada 30 segundos
  Timer.periodic(const Duration(seconds: 30), (timer) async {
    await sendUnsendedLocations();
  });

  // Atualiza localização a cada 10 segundos
  Timer.periodic(const Duration(seconds: 10), (timer) async {
    if (service == null) return;

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final timestamp = DateTime.now().toIso8601String();
      final key = await getStoredKey();

      // Envia atualização via stream
      service.invoke('update_location', {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'timestamp': timestamp,
        'key': key,
        'speed': position.speed
      });

      // Salva no banco de dados
      final dbHelper = DatabaseHelper.instance;
      await dbHelper.insertLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        key: key,
        timestamp: timestamp,
      );
    } catch (e) {
      print('Erro ao obter localização: $e');
      service.invoke('location_error', {
        'error': 'Não foi possível obter a localização: ${e.toString()}',
      });
    }
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: LocationPage());
  }
}

class LocationPage extends StatefulWidget {
  const LocationPage({super.key});

  @override
  State<LocationPage> createState() => _LocationPageState();
}

class _LocationPageState extends State<LocationPage> {
  final FlutterBackgroundService _service = FlutterBackgroundService();
  Position? _currentPosition;
  String? facts;
  String _currentKey = '';
  Trip? _currentTrip;
  bool _isRunning = false;
  bool _isValidatingKey = false;
  String? _errorMessage;
  StreamSubscription? _locationSubscription;
  final TextEditingController _keyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _setupLocationUpdates();
    _loadKey();

    // Solicita permissão ao abrir o app
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndRequestLocationPermission();
    });
  }

  Future<void> _loadKey() async {
    final key = await getStoredKey();
    final trip = await getStoredTrip();
    if (mounted) {
      setState(() {
        _currentKey = key;
        _keyController.text = key;
        _currentTrip = trip;
      });
    }
  }

  Future<void> _saveKey() async {
    final keyToSave = _keyController.text.trim();
    
    if (keyToSave.isEmpty) {
      _showErrorAlert('Digite uma key válida');
      return;
    }

    setState(() {
      _isValidatingKey = true;
    });

    // Valida a key na API
    final trip = await ApiService.validateKey(keyToSave);

    if (!mounted) return;

    setState(() {
      _isValidatingKey = false;
    });

    if (trip == null) {
      _showErrorAlert('Key inválida. Verifique e tente novamente.');
      return;
    }

    // Key válida, salva a key e a trip
    await saveStoredKey(keyToSave);
    await saveStoredTrip(trip);
    
    if (mounted) {
      setState(() {
        _currentKey = keyToSave;
        _currentTrip = trip;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Key validada e salva com sucesso!')));
    }
  }

  void _setupLocationUpdates() {
    _locationSubscription = _service.on('update_location').listen((data) {
      if (data != null) {
        setState(() {
          _currentPosition = Position(
            latitude: data['latitude'],
            longitude: data['longitude'],
            accuracy: data['accuracy'],
            timestamp: DateTime.parse(data['timestamp']),
            altitude: 0,
            altitudeAccuracy: 0,
            heading: 0,
            headingAccuracy: 0,
            speed: data['speed'],
            speedAccuracy: 0,
          );
          facts = data['key'] ?? _currentKey;
          _errorMessage = null;
        });
      }
    });

    _service.on('location_error').listen((data) {
      if (data != null && data['error'] != null) {
        setState(() {
          _errorMessage = data['error'];
        });
        _showErrorAlert();
      }
    });
  }

  void _showErrorAlert([String? message]) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: message == null ? const Text('Erro de Localização') : const Text('Erro'),
        content: Text(message ?? _errorMessage ?? 'Não foi possível obter a localização.'),
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

  Future<void> _startService() async {
    // Verifica se há uma key válida antes de iniciar
    if (_currentTrip == null) {
      _showErrorAlert('É necessário validar uma key antes de iniciar o serviço.');
      return;
    }
    
    await _service.startService();
    setState(() {
      _isRunning = true;
    });
  }

  Future<void> _stopService() async {
    _service.invoke('stopService');
    setState(() {
      _isRunning = false;
      _currentPosition = null;
    });
  }

  Future<void> _syncLocations() async {
    final (success, errorMessage) = await sendUnsendedLocations();
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          success ? 'Sucesso' : 'Erro de Sincronização',
          style: TextStyle(color: success ? Colors.green : Colors.red),
        ),
        content: Text(
          success
              ? 'Localizações sincronizadas com sucesso!'
              : errorMessage ?? 'Não foi possível sincronizar as localizações.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _keyController.dispose();
    _locationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monitor de Localização'),
        backgroundColor: _isRunning ? Colors.green : null,
      ),
      body: Column(
        children: [
          // Painel de status atual
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Status da Key
                  _buildKeyStatusCard(),
                  const SizedBox(height: 16),
                  // Input de Key
                  TextField(
                    controller: _keyController,
                    decoration: const InputDecoration(
                      labelText: 'Key',
                      hintText: 'Digite a key do log',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.key),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _currentKey = value;
                      });
                    },
                    onSubmitted: (_) => _saveKey(),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _isValidatingKey
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : TextButton(
                            onPressed: _saveKey,
                            child: const Text('Validar e Salvar Key'),
                          ),
                  ),
                  // Seção de compartilhamento de localização (só aparece com key válida)
                  if (_currentTrip != null) ...[
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: _syncLocations,
                      child: Icon(
                        _isRunning ? Icons.location_on : Icons.location_off,
                        size: 60,
                        color: _isRunning ? Colors.green : Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_currentPosition != null) ...[
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
                      InfoRow(label: 'Trip', value: _currentTrip!.label),
                    ] else ...[
                      Text(
                        _isRunning
                            ? 'Aguardando localização...'
                            : 'Serviço parado',
                        style: TextStyle(
                          fontSize: 16,
                          color: _isRunning ? Colors.orange : Colors.grey,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _isRunning ? null : _startService,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Iniciar'),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton.icon(
                          onPressed: _isRunning ? _stopService : null,
                          icon: const Icon(Icons.stop),
                          label: const Text('Parar'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_currentTrip != null) ...[
                    Text(
                      _isRunning ? 'Serviço em execução' : 'Serviço parado',
                      style: TextStyle(
                        fontSize: 18,
                        color: _isRunning ? Colors.green : Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Mensagem com nome do motorista
                    Text(
                      'Motorista: ${_currentTrip!.driverName}',
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
                            _currentTrip!.startingPointName,
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
                            _currentTrip!.endingPointName,
                            style: const TextStyle(fontSize: 14),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Key: ${_currentTrip!.key}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ] else ...[
                    const Text(
                      'Valide uma key para começar a compartilhar sua localização',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyStatusCard() {
    if (_currentTrip != null) {
      return Card(
        color: Colors.green.shade50,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Key Válida',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      _currentTrip!.label,
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.clear, color: Colors.red),
                onPressed: () async {
                  await removeStoredTrip();
                  setState(() {
                    _currentTrip = null;
                    _currentKey = '';
                    _keyController.text = '';
                  });
                },
                tooltip: 'Remover key',
              ),
            ],
          ),
        ),
      );
    } else {
      return Card(
        color: Colors.orange.shade50,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.warning, color: Colors.orange, size: 32),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Nenhuma key válida',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  String _formatDate(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
  }

  Future<void> _checkAndRequestLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ative o serviço de localização do dispositivo.'),
        ),
      );
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permissão de localização negada.')),
      );
      return;
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Permissão negada permanentemente. Ative nas configurações.',
          ),
        ),
      );
      await Geolocator.openAppSettings();
      return;
    }
  }
}
