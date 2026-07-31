import 'package:flutter/material.dart';

import '../models/trip.dart';
import '../services/api_service.dart';

class SetupCredentialsWidget extends StatefulWidget {
  final String? currentApiKey;
  final Trip? currentTrip;
  final Future<void> Function(String apiKey, Trip trip) onSetupCompleted;
  final VoidCallback onApiKeyInvalid;

  const SetupCredentialsWidget({
    super.key,
    this.currentApiKey,
    this.currentTrip,
    required this.onSetupCompleted,
    required this.onApiKeyInvalid,
  });

  @override
  State<SetupCredentialsWidget> createState() => _SetupCredentialsWidgetState();
}

class _SetupCredentialsWidgetState extends State<SetupCredentialsWidget> {
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _tripKeyController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.currentApiKey != null && widget.currentApiKey!.isNotEmpty) {
      _apiKeyController.text = widget.currentApiKey!;
    }
    if (widget.currentTrip != null) {
      _tripKeyController.text = widget.currentTrip!.key;
    }
  }

  @override
  void didUpdateWidget(SetupCredentialsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.currentApiKey != oldWidget.currentApiKey) {
      _apiKeyController.text = widget.currentApiKey ?? '';
    }

    if (widget.currentTrip?.key != oldWidget.currentTrip?.key) {
      _tripKeyController.text = widget.currentTrip?.key ?? '';
    }
  }

  Future<void> _saveAndValidate() async {
    final apiKey = _apiKeyController.text.trim();
    final tripKey = _tripKeyController.text.trim();

    if (apiKey.isEmpty) {
      _showErrorAlert('Digite a API key do cliente.');
      return;
    }

    if (tripKey.isEmpty) {
      _showErrorAlert('Digite a key da viagem.');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final result = await ApiService.validateKey(
      tripKey,
      apiKey: apiKey,
    );

    if (!mounted) return;

    setState(() {
      _isSaving = false;
    });

    if (!result.isSuccess) {
      if (result.status == TripLookupStatus.invalidApiKey) {
        widget.onApiKeyInvalid();
        _showErrorAlert(
          'A API key do cliente foi rejeitada. Reconfigure o dispositivo.',
        );
        return;
      }

      _showErrorAlert(
        result.message ?? 'Key inválida. Verifique e tente novamente.',
      );
      return;
    }

    await widget.onSetupCompleted(apiKey, result.trip!);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('API key e key da viagem salvas com sucesso.'),
      ),
    );
  }

  void _showErrorAlert(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Erro'),
        content: Text(message),
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
    _apiKeyController.dispose();
    _tripKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.lock_outline,
              size: 64,
              color: Colors.blue,
            ),
            const SizedBox(height: 24),
            const Text(
              'Configuração do cliente',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Informe a API key do cliente e a key da viagem na mesma tela.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _apiKeyController,
              decoration: const InputDecoration(
                labelText: 'API key do cliente',
                hintText: 'Cole a chave recebida do backend',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.vpn_key),
              ),
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              onSubmitted: (_) => _saveAndValidate(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _tripKeyController,
              decoration: const InputDecoration(
                labelText: 'Key da viagem',
                hintText: 'Digite a key da viagem',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.route),
              ),
              onSubmitted: (_) => _saveAndValidate(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveAndValidate,
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Salvar e validar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
