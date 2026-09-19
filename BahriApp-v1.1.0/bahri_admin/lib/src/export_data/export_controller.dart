import 'dart:convert';
import 'dart:io';
import 'package:googleapis/firestore/v1.dart' as firestore_api;
import 'package:googleapis_auth/auth_io.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';

class ExportController {
  final String serviceAccountPath;

  ExportController(this.serviceAccountPath);

  late final firestore_api.FirestoreApi _firestoreApi;

  /// Initialize Firestore API
  Future<void> initializeFirestore() async {
    final serviceAccountJson = File(serviceAccountPath).readAsStringSync();
    final credentials =
        ServiceAccountCredentials.fromJson(json.decode(serviceAccountJson));

    final client = await clientViaServiceAccount(
      credentials,
      [firestore_api.FirestoreApi.datastoreScope],
    );

    _firestoreApi = firestore_api.FirestoreApi(client);
  }

  /// Export Firestore data to CSV
  Future<String> exportData(String exportType) async {
    try {
      await initializeFirestore();

      // Define main collection and subcollection map
      const mainCollection = 'users';
      const subcollectionMap = {
        'Keystroke Data': 'keyStrokeData',
        'Keystroke FreeText Data': 'keyStrokeFreeTextData',
        'Keystroke PasswordText Data': 'keyStrokePasswordTextData',
        'Swipe Data': 'swipeData',
        'Tap Data': 'tapData',
        'Handwriting Data': 'handwritingData',
      };

      final subcollection = subcollectionMap[exportType];
      if (subcollection == null) {
        return 'Invalid export type: $exportType';
      }

      // Fetch user documents
      const userDocPath =
          'projects/bahri-app/databases/(default)/documents/$mainCollection';
      final userResponse =
          await _firestoreApi.projects.databases.documents.list(
        userDocPath,
        '',
      );

      // Function to extract value from firestore_api.Value
      dynamic _extractValue(firestore_api.Value value) {
        if (value.stringValue != null) {
          return value.stringValue!;
        } else if (value.integerValue != null) {
          return int.parse(value.integerValue!);
        } else if (value.doubleValue != null) {
          return value.doubleValue!;
        } else if (value.booleanValue != null) {
          return value.booleanValue!;
        } else if (value.mapValue != null) {
          // Convert the map to a Map<String, dynamic>
          final map = value.mapValue!.fields?.map((key, subValue) {
            return MapEntry(key, _extractValue(subValue));
          });
          return map ?? {};
        } else if (value.arrayValue != null) {
          // Recursively extract each element in the array
          final list = value.arrayValue!.values
              ?.map((element) => _extractValue(element))
              .toList();
          return list ?? [];
        }
        return null; // Return null for unsupported or null types
      }

      final List<Map<String, dynamic>> data = [];

      // Loop through each user document
      for (final userDoc in userResponse.documents ?? []) {
        final userId = userDoc.name?.split('/').last ?? '';
        final userFields = userDoc.fields ?? {};
        print('Processing user: $userId');

        // Fetch subcollection documents
        final subDocPath =
            'projects/bahri-app/databases/(default)/documents/$mainCollection/$userId/$subcollection';
        final subDocsResponse = await _firestoreApi.projects.databases.documents
            .list(subDocPath, '');

        // Loop through subcollection documents
        for (final subDoc in subDocsResponse.documents ?? []) {
          final subFields = subDoc.fields ?? {};

          if (subcollection == subcollectionMap["Keystroke Data"]) {
            final keystrokeDataList = subFields['keystrokeData']
                ?.arrayValue
                ?.values
                ?.map((value) => _extractValue(value))
                .toList();

            // Serialize the list into a JSON string
            String keystrokeDataJson =
                keystrokeDataList != null ? jsonEncode(keystrokeDataList) : '';

            data.add({
              'id': userId,
              'Date of Birth': userFields['dateOfBirth']?.stringValue ?? '',
              'skillLevel': userFields['skillLevel']?.stringValue ?? '',
              'gender': userFields['gender']?.stringValue ?? '',
              'Sentence': subFields['Sentence']?.stringValue ?? '',
              'completeUserInput':
                  subFields['completeUserInput']?.stringValue ?? '',
              'keystrokeData': keystrokeDataJson,
            });
          } else if (subcollection ==
              subcollectionMap["Keystroke FreeText Data"]) {
            final keystrokeDataList = subFields['keystrokeFreeTextData']
                ?.arrayValue
                ?.values
                ?.map((value) => _extractValue(value))
                .toList();

            // Serialize the list into a JSON string
            String keystrokeDataJson =
                keystrokeDataList != null ? jsonEncode(keystrokeDataList) : '';

            data.add({
              'id': userId,
              'Date of Birth': userFields['dateOfBirth']?.stringValue ?? '',
              'skillLevel': userFields['skillLevel']?.stringValue ?? '',
              'gender': userFields['gender']?.stringValue ?? '',
              'completeUserInput':
                  subFields['completeUserInput']?.stringValue ?? '',
              'keystrokeFreeTextData': keystrokeDataJson,
            });
          } else if (subcollection ==
              subcollectionMap["Keystroke PasswordText Data"]) {
            final keystrokeDataList = subFields['keystrokePasswordTextData']
                ?.arrayValue
                ?.values
                ?.map((value) => _extractValue(value))
                .toList();

            // Serialize the list into a JSON string
            String keystrokeDataJson =
                keystrokeDataList != null ? jsonEncode(keystrokeDataList) : '';

            data.add({
              'id': userId,
              'Date of Birth': userFields['dateOfBirth']?.stringValue ?? '',
              'skillLevel': userFields['skillLevel']?.stringValue ?? '',
              'gender': userFields['gender']?.stringValue ?? '',
              'completeUserInput':
                  subFields['completeUserInput']?.stringValue ?? '',
              'keystrokePasswordTextData': keystrokeDataJson,
            });
          } else if (subcollection == subcollectionMap["Handwriting Data"]) {
            // Serialize the list into a JSON string

            data.add({
              'id': userId,
              'Date of Birth': userFields['dateOfBirth']?.stringValue ?? '',
              'skillLevel': userFields['skillLevel']?.stringValue ?? '',
              'gender': userFields['gender']?.stringValue ?? '',
              'Letter': subFields['Letter']?.stringValue ?? '',
              'language': subFields['language']?.stringValue ?? '',
              'endTime': subFields['endTime']?.stringValue ?? '',
              'startTime': subFields['startTime']?.stringValue ?? '',
              'HandwritingData':
                  subFields['HandwritingData']?.stringValue ?? '',
            });
          } else if (subcollection == subcollectionMap["Swipe Data"]) {
            final swipeDataList = subFields['swipeData']
                ?.arrayValue
                ?.values
                ?.map((value) => _extractValue(value))
                .toList();

            // Serialize the list into a JSON string
            String swipeDataJson =
                swipeDataList != null ? jsonEncode(swipeDataList) : '';

            data.add({
              'id': userId,
              'Date of Birth': userFields['dateOfBirth']?.stringValue ?? '',
              'skillLevel': userFields['skillLevel']?.stringValue ?? '',
              'gender': userFields['gender']?.stringValue ?? '',
              'swipeData': swipeDataJson,
            });
          } else if (subcollection == subcollectionMap["Tap Data"]) {
            final tapDataList = subFields['tap_Data']
                ?.arrayValue
                ?.values
                ?.map((value) => _extractValue(value))
                .toList();

            // Serialize the list into a JSON string
            String tapDataJson =
                tapDataList != null ? jsonEncode(tapDataList) : '';

            data.add({
              'id': userId,
              'Date of Birth': userFields['dateOfBirth']?.stringValue ?? '',
              'skillLevel': userFields['skillLevel']?.stringValue ?? '',
              'gender': userFields['gender']?.stringValue ?? '',
              'tapData': tapDataJson,
            });
          }
        }
      }

      if (data.isEmpty) {
        print('No data found to export.');
        return 'No data to export.';
      }

      // Create CSV data
      final csvData = [
        data.first.keys.toList(), // Header row
        ...data.map((row) => row.values.toList()),
      ];

      // Configure the CSV converter
      const csvConverter = ListToCsvConverter(
        fieldDelimiter: ',',
        textDelimiter: '"',
        textEndDelimiter: '"',
        eol: '\n',
        delimitAllFields: true,
      );

      final csvString = csvConverter.convert(csvData);

      // Add UTF-8 BOM
      final bom = utf8.encode('\uFEFF');

      // Save CSV to file with BOM
      final tempDir = await getApplicationDocumentsDirectory();
      final csvFile = File('${tempDir.path}/$exportType.csv');
      await csvFile.writeAsBytes(bom + utf8.encode(csvString));

      print('Export successful: ${csvFile.path}');
      return 'Exported $exportType to ${csvFile.path} successfully.';
    } catch (e) {
      print('Error during export: $e');
      return 'Error exporting data: $e';
    }
  }
}
