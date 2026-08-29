import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/config/environment.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../providers/receipt_provider.dart';
import '../widgets/receipt_review_form.dart';

class ScanReceiptScreen extends ConsumerStatefulWidget {
  const ScanReceiptScreen({super.key});

  @override
  ConsumerState<ScanReceiptScreen> createState() => _ScanReceiptScreenState();
}

class _ScanReceiptScreenState extends ConsumerState<ScanReceiptScreen> {
  XFile? _selectedImage;
  Uint8List? _selectedImageBytes;
  final _picker = ImagePicker();

  @override
  Widget build(BuildContext context) {
    final scanState = ref.watch(scanProvider);

    ref.listen(scanProvider, (_, next) {
      if (next is ScanSaved) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ticket guardado'),
            backgroundColor: AppColors.success,
          ),
        );
        ref.read(scanProvider.notifier).reset();
        _clearImage();
        context.go('/receipts');
      }
      if (next is ScanFailed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.message),
            backgroundColor: AppColors.error,
          ),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(scanState is ScanReviewing || scanState is ScanSaving
            ? 'Revisar ticket'
            : 'Escanear ticket'),
        leading: scanState is ScanReviewing
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Descartar',
                onPressed: () {
                  ref.read(scanProvider.notifier).reset();
                  _clearImage();
                },
              )
            : null,
      ),
      body: SafeArea(child: _buildBody(scanState)),
    );
  }

  Widget _buildBody(ScanState state) {
    return switch (state) {
      // El paso que faltaba: corregir antes de guardar, no despues.
      ScanReviewing(:final draft) => ReceiptReviewForm(
          draft: draft,
          imageBytes: _selectedImageBytes,
          isSaving: false,
          onCancel: () {
            ref.read(scanProvider.notifier).reset();
            _clearImage();
          },
          onConfirm: (corrected) =>
              ref.read(scanProvider.notifier).confirm(corrected),
        ),
      ScanSaving(:final draft) => ReceiptReviewForm(
          draft: draft,
          imageBytes: _selectedImageBytes,
          isSaving: true,
          onCancel: () {},
          onConfirm: (_) {},
        ),
      _ => _buildPicker(state),
    };
  }

  Widget _buildPicker(ScanState state) {
    final analyzing = state is ScanAnalyzing;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Expanded(child: _buildImageArea(analyzing)),
          const SizedBox(height: 24),
          _buildActions(analyzing),
        ],
      ),
    );
  }

  Widget _buildImageArea(bool analyzing) {
    if (analyzing) return const _AnalyzingState();

    if (_selectedImageBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(
              _selectedImageBytes!,
              fit: BoxFit.cover,
              // Sin cacheWidth, un JPEG de 12 MP decodifica ~48 MB en memoria
              // solo para mostrar una miniatura.
              cacheWidth: 1080,
            ),
            Positioned(
              top: 12,
              right: 12,
              child: IconButton.filled(
                icon: const Icon(Icons.close),
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                onPressed: _clearImage,
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () => _pickImage(ImageSource.gallery),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.3),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.receipt_long,
                  color: AppColors.primary, size: 48),
            ),
            const SizedBox(height: 20),
            Text('Tocá para elegir un ticket',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('o usá la cámara',
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(bool analyzing) {
    return Column(
      children: [
        if (_selectedImage != null)
          AppButton(
            label: 'Leer ticket',
            isLoading: analyzing,
            width: double.infinity,
            icon: Icons.auto_awesome,
            onPressed: analyzing
                ? null
                : () => ref
                    .read(scanProvider.notifier)
                    .analyze(_selectedImage!),
          )
        else ...[
          AppButton(
            label: 'Sacar foto',
            width: double.infinity,
            icon: Icons.camera_alt,
            onPressed: analyzing ? null : () => _pickImage(ImageSource.camera),
          ),
          const SizedBox(height: 12),
          AppButton(
            label: 'Elegir de la galería',
            outlined: true,
            width: double.infinity,
            icon: Icons.photo_library_outlined,
            onPressed: analyzing ? null : () => _pickImage(ImageSource.gallery),
          ),
        ],
      ],
    );
  }

  void _clearImage() {
    if (!mounted) return;
    setState(() {
      _selectedImage = null;
      _selectedImageBytes = null;
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 90,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _selectedImage = file;
        _selectedImageBytes = bytes;
      });
    } catch (e) {
      // Permiso denegado o cámara no disponible: antes esto era una excepción
      // sin capturar que dejaba la pantalla trabada.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo abrir la imagen: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
}

/// Los pasos ya no mienten: se muestra el motor real de OCR que corre.
class _AnalyzingState extends StatelessWidget {
  const _AnalyzingState();

  @override
  Widget build(BuildContext context) {
    final motor = Environment.ocrProvider == 'ollama'
        ? 'modelo de visión'
        : 'OCR del dispositivo';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: AppColors.primary),
          const SizedBox(height: 24),
          Text('Leyendo el ticket...',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('Usando $motor',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Nada se guarda todavía: vas a poder corregir lo que lea.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
