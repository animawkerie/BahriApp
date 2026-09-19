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
  late final ExportController _exportController;

  bool _isExporting = false;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();

    // Provide the path to your service account file
    final serviceAccountPath = File(
            "E:/PhD Cyber/BahriApp/bahri_admin/bahri-app-firebase-adminsdk-omjuu-4bb40cce49.json")
        .absolute
        .path;
    _exportController = ExportController(serviceAccountPath);
  }

  void _handleExport(String exportType) async {
    setState(() {
      _isExporting = true;
      _statusMessage = 'Exporting $exportType...';
    });

    try {
      String result = await _exportController.exportData(exportType);
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
