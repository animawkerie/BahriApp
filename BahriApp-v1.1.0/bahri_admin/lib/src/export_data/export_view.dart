// export_view.dart
import 'package:bahri_admin/src/export_data/export_controller.dart';
import 'package:flutter/material.dart';
import 'dart:io';

class ExportView extends StatefulWidget {
  static const String routeName = '/export';

  const ExportView({super.key});

  @override
  State<StatefulWidget> createState() => _ExportViewState();
}

class _ExportViewState extends State<ExportView> {
  ExportController? _exportController;

  /// Set when credentials are missing or unreadable; surfaced in the UI
  /// instead of crashing on a hard-coded path that does not exist.
  String? _configError;

  bool _isExporting = false;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();

    // v1.1: credentials come from the environment, never a hard-coded
    // developer path. The v1.0 absolute path made the dashboard impossible
    // for anyone else to run (R1-16) and risked committing a credential
    // location alongside the source (R1-6). See .env.example.
    final serviceAccountPath =
        Platform.environment['GOOGLE_APPLICATION_CREDENTIALS'] ??
            Platform.environment['BAHRI_SERVICE_ACCOUNT'];

    if (serviceAccountPath == null || serviceAccountPath.isEmpty) {
      _configError =
          'Set GOOGLE_APPLICATION_CREDENTIALS (or BAHRI_SERVICE_ACCOUNT) to the '
          'path of your service-account JSON before starting the dashboard. '
          'See .env.example.';
      return;
    }
    if (!File(serviceAccountPath).existsSync()) {
      _configError = 'Service-account file not found at: $serviceAccountPath';
      return;
    }
    _exportController = ExportController(File(serviceAccountPath).absolute.path);
  }

  void _handleExport(String exportType) async {
    final controller = _exportController;
    if (controller == null) {
      setState(() => _statusMessage = _configError ?? 'Export is not configured.');
      return;
    }

    setState(() {
      _isExporting = true;
      _statusMessage = 'Exporting $exportType...';
    });

    try {
      String result = await controller.exportData(exportType);
      setState(() {
        _statusMessage = result;
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: $e';
      });
    } finally {
      setState(() {
        _isExporting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Export Data'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ElevatedButton(
              onPressed:
                  _isExporting ? null : () => _handleExport('Keystroke Data'),
              child: const Text('Export Fixed Keystroke Data'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isExporting
                  ? null
                  : () => _handleExport('Keystroke FreeText Data'),
              child: const Text('Export Free Flow Keystroke Data'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isExporting
                  ? null
                  : () => _handleExport('Keystroke PasswordText Data'),
              child: const Text('Export Password Keystroke Data'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed:
                  _isExporting ? null : () => _handleExport('Swipe Data'),
              child: const Text('Export Swipe Data'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isExporting ? null : () => _handleExport('Tap Data'),
              child: const Text('Export Tap Data'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed:
                  _isExporting ? null : () => _handleExport('Handwriting Data'),
              child: const Text('Export Handwriting Data'),
            ),
            const SizedBox(height: 32),
            if (_isExporting)
              const CircularProgressIndicator()
            else
              Text(
                _statusMessage,
                style: const TextStyle(fontSize: 16),
              ),
          ],
        ),
      ),
    );
  }
}
