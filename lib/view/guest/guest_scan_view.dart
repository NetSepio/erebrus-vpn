import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';

import '../../theme/app_theme.dart';

/// Full-screen QR scanner that returns the first valid payload via Get.back.
class GuestScanView extends StatefulWidget {
  const GuestScanView({super.key});

  @override
  State<GuestScanView> createState() => _GuestScanViewState();
}

class _GuestScanViewState extends State<GuestScanView> {
  final GlobalKey _scannerKey = GlobalKey(debugLabel: 'guest-config-qr');
  bool _handled = false;

  void _onViewCreated(QRViewController controller) {
    controller.scannedDataStream.listen((scan) {
      if (_handled) return;
      final raw = scan.code;
      if (raw == null || raw.isEmpty) return;
      _handled = true;
      controller.pauseCamera();
      Get.back<String>(result: raw);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            QRView(
              key: _scannerKey,
              onQRViewCreated: _onViewCreated,
              overlay: QrScannerOverlayShape(
                borderColor: AppColors.accent,
                borderRadius: 14,
                borderLength: 30,
                borderWidth: 4,
                cutOutSize: MediaQuery.sizeOf(context).shortestSide * 0.72,
              ),
            ),
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: Get.back,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Scan VPN config QR',
                          style: grotesk(
                            size: 17,
                            weight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Container(
                  margin: const EdgeInsets.only(bottom: 34),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    'Position the QR code inside the frame',
                    style: grotesk(
                      size: 13,
                      weight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
