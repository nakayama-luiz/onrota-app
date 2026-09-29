import 'package:flutter/material.dart';
import 'package:detalhes/models/trip.dart';
import 'package:detalhes/services/api_service.dart';

/// Login do motorista: CPF + placa. Devolve as corridas abertas encontradas.
class CpfInputWidget extends StatefulWidget {
  final String? currentCpf;
  final void Function(String cpf, List<Trip> trips) onLogin;

  const CpfInputWidget({
    super.key,
    this.currentCpf,
    required this.onLogin,
  });

  @override
  State<CpfInputWidget> createState() => _CpfInputWidgetState();
}

class _CpfInputWidgetState extends State<CpfInputWidget> {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _placaController = TextEditingController();
  String _formattedCpf = '';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.currentCpf != null && widget.currentCpf!.isNotEmpty) {
      _controller.text = _formatCpf(widget.currentCpf!);
    }
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final text = _controller.text.replaceAll(RegExp(r'\D'), '');
    setState(() {
      _formattedCpf = _formatCpf(text);
    });
    _controller.value = TextEditingValue(
      text: _formattedCpf,
      selection: TextSelection.collapsed(offset: _formattedCpf.length),
    );
  }

  String _formatCpf(String cpf) {
    final digits = cpf.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 11) return digits.substring(0, 11);
    
    if (digits.length <= 3) return digits;
    if (digits.length <= 6) return '${digits.substring(0, 3)}.${digits.substring(3)}';
    if (digits.length <= 9) return '${digits.substring(0, 3)}.${digits.substring(3, 6)}.${digits.substring(6)}';
    return '${digits.substring(0, 3)}.${digits.substring(3, 6)}.${digits.substring(6, 9)}-${digits.substring(9)}';
  }

  bool _isValidCpf(String cpf) {
    final digits = cpf.replaceAll(RegExp(r'\D'), '');
    return digits.length == 11;
  }

  Future<void> _submit() async {
    final cpf = _controller.text.replaceAll(RegExp(r'\D'), '');
    final placa = _placaController.text.trim();

    if (!_isValidCpf(cpf)) {
      _showErrorAlert('Digite um CPF válido (11 dígitos)');
      return;
    }

    if (placa.isEmpty) {
      _showErrorAlert('Digite a placa do veículo');
      return;
    }

    setState(() => _loading = true);
    try {
      final trips = await ApiService.login(cpf, placa);
      widget.onLogin(cpf, trips);
    } catch (e) {
      _showErrorAlert(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
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
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _placaController.dispose();
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
              Icons.person_outline,
              size: 64,
              color: Colors.blue,
            ),
            const SizedBox(height: 24),
            const Text(
              'Bem-vindo!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Entre com seu CPF e a placa do veículo',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              maxLength: 14,
              decoration: const InputDecoration(
                labelText: 'CPF',
                hintText: '000.000.000-00',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.badge),
                counterText: '',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _placaController,
              textCapitalization: TextCapitalization.characters,
              maxLength: 8,
              decoration: const InputDecoration(
                labelText: 'Placa',
                hintText: 'ABC1D23',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.local_shipping),
                counterText: '',
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Entrar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
