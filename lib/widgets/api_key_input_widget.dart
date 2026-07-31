import 'package:flutter/material.dart';

class ApiKeyInputWidget extends StatefulWidget {
  final String? currentApiKey;
  final ValueChanged<String> onApiKeySaved;

  const ApiKeyInputWidget({
    super.key,
    this.currentApiKey,
    required this.onApiKeySaved,
  });

  @override
  State<ApiKeyInputWidget> createState() => _ApiKeyInputWidgetState();
}

class _ApiKeyInputWidgetState extends State<ApiKeyInputWidget> {
  final TextEditingController _controller = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.currentApiKey != null && widget.currentApiKey!.isNotEmpty) {
      _controller.text = widget.currentApiKey!;
    }
  }

  @override
  void didUpdateWidget(ApiKeyInputWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentApiKey != oldWidget.currentApiKey) {
      _controller.text = widget.currentApiKey ?? '';
    }
  }

  Future<void> _saveApiKey() async {
    final apiKey = _controller.text.trim();

    if (apiKey.isEmpty) {
      _showErrorAlert('Digite a API key do cliente.');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    widget.onApiKeySaved(apiKey);

    if (!mounted) return;
    setState(() {
      _isSaving = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('API key salva com sucesso.')),
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
              Icons.lock_outline,
              size: 64,
              color: Colors.blue,
            ),
            const SizedBox(height: 24),
            const Text(
              'Configurar cliente',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Informe a API key do cliente para liberar o app.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'API key do cliente',
                hintText: 'Cole a chave recebida do backend',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.key),
              ),
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              onSubmitted: (_) => _saveApiKey(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveApiKey,
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Salvar API key'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
