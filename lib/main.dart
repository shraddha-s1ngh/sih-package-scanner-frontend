import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const PackageScannerApp());
}

class PackageScannerApp extends StatelessWidget {
  const PackageScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Package Scanner',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  XFile? selectedImage;
  bool isScanning = false;

  final ImagePicker picker = ImagePicker();

  // ============================================================
  // IMAGE PICKER
  // ============================================================

  Future<void> pickImage(ImageSource source) async {
    final XFile? image = await picker.pickImage(
      source: source,

      // Reduce large camera/gallery images
      imageQuality: 60,

      // Prevent very large images from being uploaded
      maxWidth: 1600,
      maxHeight: 1600,
    );

    if (image != null) {
      setState(() {
        selectedImage = image;
      });
    }
  }

  // ============================================================
  // SCAN PACKAGE
  // ============================================================

  Future<void> scanPackage() async {
    if (selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a package image first!'),
        ),
      );
      return;
    }

    setState(() {
      isScanning = true;
    });

    try {
      final bytes = await selectedImage!.readAsBytes();

      final request = http.MultipartRequest(
        'POST',
        Uri.parse(
          'https://sih-package-scanner-backend.onrender.com/scan',
        ),
      );

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: selectedImage!.name,
        ),
      );

      final response = await request.send();

      final responseBody =
      await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final data = jsonDecode(responseBody);

        if (!mounted) return;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ResultPage(
              data: data,
            ),
          ),
        );
      } else {
        throw Exception(
          'Server error: ${response.statusCode}',
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connection error: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isScanning = false;
        });
      }
    }
  }

  // ============================================================
  // IMAGE PREVIEW
  // ============================================================

  Widget imagePreview() {
    if (selectedImage == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.image_outlined,
              size: 70,
              color: Colors.grey,
            ),
            SizedBox(height: 10),
            Text(
              'No package image selected',
              style: TextStyle(
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    if (kIsWeb) {
      return Image.network(
        selectedImage!.path,
        fit: BoxFit.contain,
      );
    }

    return Image.file(
      File(selectedImage!.path),
      fit: BoxFit.contain,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Package Scanner',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text(
              'Scan Food Package',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),

            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.grey,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: imagePreview(),
                ),
              ),
            ),

            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      pickImage(ImageSource.camera);
                    },
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Camera'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      pickImage(ImageSource.gallery);
                    },
                    icon: const Icon(Icons.photo),
                    label: const Text('Gallery'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            if (selectedImage != null)
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    selectedImage = null;
                  });
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove Image'),
              ),

            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                onPressed: isScanning ? null : scanPackage,
                icon: isScanning
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
                    : const Icon(Icons.qr_code_scanner),
                label: Text(
                  isScanning
                      ? 'Scanning Package...'
                      : 'Scan Package',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// RESULT PAGE
// ============================================================

class ResultPage extends StatelessWidget {
  final Map<String, dynamic> data;

  const ResultPage({
    super.key,
    required this.data,
  });

  Color getStatusColor(String status) {
    if (status == 'PASS') {
      return Colors.green;
    }

    if (status == 'FAIL') {
      return Colors.red;
    }

    return Colors.orange;
  }

  IconData getStatusIcon(String status) {
    if (status == 'PASS') {
      return Icons.check_circle;
    }

    if (status == 'FAIL') {
      return Icons.cancel;
    }

    return Icons.warning_amber;
  }

  @override
  Widget build(BuildContext context) {
    final compliance =
    data['compliance'] as Map<String, dynamic>;

    final overallStatus =
        compliance['status']?.toString() ?? 'REVIEW';

    final rules =
    compliance['rules_checked'] as Map<String, dynamic>;

    final summary =
    compliance['summary'] as Map<String, dynamic>;

    final passed = summary['passed'] ?? 0;
    final failed = summary['failed'] ?? 0;
    final review = summary['review'] ?? 0;

    final bool isCompliant =
        overallStatus == 'COMPLIANT';

    final bool isNonCompliant =
        overallStatus == 'NON-COMPLIANT';

    Color overallColor;

    if (isCompliant) {
      overallColor = Colors.green;
    } else if (isNonCompliant) {
      overallColor = Colors.red;
    } else {
      overallColor = Colors.orange;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Scan Result',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // OVERALL RESULT
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: overallColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: overallColor,
                  width: 2,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    isCompliant
                        ? Icons.check_circle
                        : isNonCompliant
                        ? Icons.cancel
                        : Icons.warning_amber,
                    size: 70,
                    color: overallColor,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    overallStatus,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: overallColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Package Compliance Result',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // SUMMARY
            Row(
              children: [
                Expanded(
                  child: summaryCard(
                    'Passed',
                    passed,
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: summaryCard(
                    'Failed',
                    failed,
                    Colors.red,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: summaryCard(
                    'Review',
                    review,
                    Colors.orange,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 25),

            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Declaration Checks',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // RULES
            ...rules.values.map(
                  (rule) {
                final ruleData =
                rule as Map<String, dynamic>;

                final status =
                    ruleData['status']?.toString() ??
                        'REVIEW';

                final name =
                    ruleData['name']?.toString() ??
                        'Unknown Rule';

                final reason =
                    ruleData['reason']?.toString() ?? '';

                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(
                    bottom: 10,
                  ),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius:
                    BorderRadius.circular(14),
                    border: Border.all(
                      color: getStatusColor(status)
                          .withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Icon(
                        getStatusIcon(status),
                        color:
                        getStatusColor(status),
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                          CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontWeight:
                                FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              reason,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              status,
                              style: TextStyle(
                                color:
                                getStatusColor(
                                  status,
                                ),
                                fontWeight:
                                FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 10),

            // BACK BUTTON
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                },
                icon: const Icon(
                  Icons.arrow_back,
                ),
                label: const Text(
                  'Scan Another Package',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget summaryCard(
      String title,
      dynamic value,
      Color color,
      ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: 16,
        horizontal: 8,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        color: color.withValues(alpha: 0.1),
        border: Border.all(
          color: color.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          Text(
            value.toString(),
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}