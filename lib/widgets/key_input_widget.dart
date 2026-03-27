import 'package:flutter/material.dart';
import 'package:detalhes/models/trip.dart';
import 'package:detalhes/services/api_service.dart';

/// Widget responsável por gerenciar a entrada e validação da key
class KeyInputWidget extends StatefulWidget {
  final Trip? currentTrip;
  final ValueChanged<Trip?> onTripChanged;

  const KeyInputWidget({
    super.key,
    this.currentTrip,
    required this.onTripChanged,
  });

  @override
  State<KeyInputWidget> createState() => _KeyInputWidgetState();
}

class _KeyInputWidgetState extends State<KeyInputWidget> {
  final TextEditingController _controller = TextEditingController();
  bool _isValidating = false;

  @override
  void initState() {
    super.initState();
    if (widget.currentTrip != null) {
      _controller.text = widget.currentTrip!.key;
    }
  }

  @override
  void didUpdateWidget(KeyInputWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentTrip != null && oldWidget.currentTrip == null) {
      _controller.text = widget.currentTrip!.key;
    } else if (widget.currentTrip == null && oldWidget.currentTrip != null) {
      _controller.clear();
    }
  }

  Future<void> _validateAndSave() async {
    final keyToSave = _controller.text.trim();

    if (keyToSave.isEmpty) {
      _showErrorAlert('Digite uma key válida');
      return;
    }

    setState(() {
      _isValidating = true;
    });

    // Valida a key na API
    final trip = await ApiService.validateKey(keyToSave);

    if (!mounted) return;

    setState(() {
      _isValidating = false;
    });

    if (trip == null) {
      _showErrorAlert('Key inválida. Verifique e tente novamente.');
      return;
    }

    // Key válida, notifica o pai
    widget.onTripChanged(trip);

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Key validada e salva com sucesso!')));
    }
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
    _controller.dispose();
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
              Icons.vpn_key,
              size: 64,
              color: Colors.orange,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Key',
                hintText: 'Digite a key do log',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.key),
              ),
              onSubmitted: (_) => _validateAndSave(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isValidating ? null : _validateAndSave,
                child: _isValidating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Validar e Salvar Key'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
