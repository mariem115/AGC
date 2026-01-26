import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/reference.dart';
import '../../providers/media_provider.dart';
import '../../providers/references_provider.dart';
import '../../utils/image_utils.dart';
import '../../widgets/common/loading_overlay.dart';

/// Image editing screen with annotations
class EditScreen extends StatefulWidget {
  final String? imagePath;
  final int? imageId;
  
  const EditScreen({
    super.key,
    this.imagePath,
    this.imageId,
  });

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  final GlobalKey _imageKey = GlobalKey();
  final _descriptionController = TextEditingController();
  
  Reference? _selectedReference;
  int _mediaType = 1; // 1=Photo, 4=OK, 5=NOK, 6=Neutral
  bool _showDate = false;
  bool _showReference = false;
  bool _isSaving = false;
  
  // Drawing state
  final List<_DrawingPath> _paths = [];
  _DrawingPath? _currentPath;
  Color _drawingColor = AppColors.statusOK;
  double _strokeWidth = 4.0;
  
  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Color _getMediaTypeColor() {
    switch (_mediaType) {
      case 4:
        return AppColors.statusOK;
      case 5:
        return AppColors.statusNOK;
      case 6:
        return AppColors.statusNeutral;
      default:
        return Colors.transparent;
    }
  }

  void _setMediaType(int type) {
    setState(() {
      _mediaType = type;
      if (type != 1) {
        _drawingColor = _getMediaTypeColor();
      }
    });
  }

  void _clearDrawings() {
    setState(() {
      _paths.clear();
    });
  }

  void _undoLastPath() {
    if (_paths.isNotEmpty) {
      setState(() {
        _paths.removeLast();
      });
    }
  }

  Future<File?> _captureImage() async {
    try {
      final boundary = _imageKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;
      
      final bytes = byteData.buffer.asUint8List();
      final fileName = 'AGC_${ImageUtils.getTimestamp()}.png';
      
      return await ImageUtils.saveToFile(bytes, fileName);
    } catch (e) {
      debugPrint('Error capturing image: $e');
      return null;
    }
  }

  Future<void> _saveLocally() async {
    if (_isSaving) return;
    
    setState(() => _isSaving = true);
    
    try {
      final file = await _captureImage();
      if (file == null) {
        _showError('Erreur lors de la capture de l\'image');
        return;
      }
      
      final mediaProvider = context.read<MediaProvider>();
      final name = _selectedReference?.name ?? 'Image';
      final path = await mediaProvider.saveImageLocally(file, name);
      
      if (path != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Image sauvegardée localement'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      } else {
        _showError('Erreur lors de la sauvegarde');
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _uploadImage() async {
    if (_selectedReference == null) {
      _showError('Veuillez sélectionner une référence');
      return;
    }
    
    if (_isSaving) return;
    
    setState(() => _isSaving = true);
    
    try {
      final file = await _captureImage();
      if (file == null) {
        _showError('Erreur lors de la capture de l\'image');
        return;
      }
      
      final mediaProvider = context.read<MediaProvider>();
      final imageName = '${_selectedReference!.name}_${ImageUtils.getTimestamp()}.png';
      
      final success = await mediaProvider.uploadImage(
        file: file,
        referenceId: _selectedReference!.id,
        referenceType: _selectedReference!.referenceType,
        mediaType: _mediaType,
        imageName: imageName,
      );
      
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Image téléchargée avec succès'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
        
        // Delete local file after successful upload
        if (widget.imagePath != null) {
          try {
            File(widget.imagePath!).deleteSync();
          } catch (_) {}
        }
        
        Navigator.pop(context);
      } else {
        _showError(mediaProvider.error ?? 'Erreur lors du téléchargement');
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LoadingOverlay(
      isLoading: _isSaving,
      message: 'Traitement en cours...',
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.white,
          title: const Text('Éditer l\'image'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            // Undo button
            if (_paths.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.undo_rounded),
                onPressed: _undoLastPath,
                tooltip: 'Annuler',
              ),
            // Clear button
            if (_paths.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.clear_all_rounded),
                onPressed: _clearDrawings,
                tooltip: 'Effacer tout',
              ),
          ],
        ),
        body: Column(
          children: [
            // Image with annotations
            Expanded(
              flex: 5,
              child: _buildImageSection(),
            ),
            
            // Controls panel
            Expanded(
              flex: 4,
              child: _buildControlsPanel(),
            ),
          ],
        ),
        
        // Bottom action buttons
        bottomNavigationBar: _buildBottomBar(),
      ),
    );
  }

  Widget _buildImageSection() {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: RepaintBoundary(
          key: _imageKey,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Base image
              if (widget.imagePath != null)
                kIsWeb
                    ? Image.network(
                        widget.imagePath!,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const Center(
                            child: Icon(
                              Icons.broken_image_outlined,
                              size: 64,
                              color: AppColors.textLight,
                            ),
                          );
                        },
                      )
                    : Image.file(
                        File(widget.imagePath!),
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const Center(
                            child: Icon(
                              Icons.broken_image_outlined,
                              size: 64,
                              color: AppColors.textLight,
                            ),
                          );
                        },
                      )
              else if (widget.imageId != null)
                Image.network(
                  context.read<MediaProvider>().getImageUrl(widget.imageId!),
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const Center(child: CircularProgressIndicator());
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return const Center(
                      child: Icon(
                        Icons.error_outline,
                        size: 64,
                        color: AppColors.error,
                      ),
                    );
                  },
                )
              else
                const Center(
                  child: Text('Aucune image'),
                ),
              
              // Drawing canvas
              GestureDetector(
                onPanStart: (details) {
                  setState(() {
                    _currentPath = _DrawingPath(
                      color: _drawingColor,
                      strokeWidth: _strokeWidth,
                    );
                    _currentPath!.points.add(details.localPosition);
                  });
                },
                onPanUpdate: (details) {
                  if (_currentPath != null) {
                    setState(() {
                      _currentPath!.points.add(details.localPosition);
                    });
                  }
                },
                onPanEnd: (details) {
                  if (_currentPath != null && _currentPath!.points.length > 1) {
                    setState(() {
                      _paths.add(_currentPath!);
                      _currentPath = null;
                    });
                  }
                },
                child: CustomPaint(
                  painter: _DrawingPainter(
                    paths: _paths,
                    currentPath: _currentPath,
                  ),
                  size: Size.infinite,
                ),
              ),
              
              // Overlays (date, reference)
              if (_showDate || _showReference)
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_showReference && _selectedReference != null)
                          Text(
                            _selectedReference!.name,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        if (_showDate)
                          Text(
                            ImageUtils.getFormattedDate(),
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              
              // Media type indicator
              if (_mediaType != 1)
                Positioned(
                  right: 12,
                  top: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _getMediaTypeColor(),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _mediaType == 4 ? 'OK' : (_mediaType == 5 ? 'NOK' : 'NEUTRE'),
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlsPanel() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Reference selector
            _buildReferenceSelector(),
            
            const SizedBox(height: 16),
            
            // Description field
            TextField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: 'Description',
                hintText: 'Ajouter une description...',
                filled: true,
                fillColor: AppColors.surfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              maxLines: 2,
            ),
            
            const SizedBox(height: 16),
            
            // Media type buttons
            const Text(
              'Type de média',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _MediaTypeButton(
                  label: 'OK',
                  color: AppColors.statusOK,
                  isSelected: _mediaType == 4,
                  onTap: () => _setMediaType(4),
                ),
                const SizedBox(width: 8),
                _MediaTypeButton(
                  label: 'NOK',
                  color: AppColors.statusNOK,
                  isSelected: _mediaType == 5,
                  onTap: () => _setMediaType(5),
                ),
                const SizedBox(width: 8),
                _MediaTypeButton(
                  label: 'Neutre',
                  color: AppColors.statusNeutral,
                  isSelected: _mediaType == 6,
                  onTap: () => _setMediaType(6),
                ),
                const SizedBox(width: 8),
                _MediaTypeButton(
                  label: 'Photo',
                  color: AppColors.textSecondary,
                  isSelected: _mediaType == 1,
                  onTap: () => _setMediaType(1),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Display options
            Row(
              children: [
                Expanded(
                  child: CheckboxListTile(
                    value: _showDate,
                    onChanged: (value) => setState(() => _showDate = value ?? false),
                    title: const Text(
                      'Afficher date',
                      style: TextStyle(fontSize: 13, fontFamily: 'Poppins'),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                Expanded(
                  child: CheckboxListTile(
                    value: _showReference,
                    onChanged: (value) => setState(() => _showReference = value ?? false),
                    title: const Text(
                      'Afficher réf.',
                      style: TextStyle(fontSize: 13, fontFamily: 'Poppins'),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReferenceSelector() {
    final refs = context.watch<ReferencesProvider>().allReferences;
    
    return DropdownButtonFormField<Reference>(
      value: _selectedReference,
      decoration: InputDecoration(
        labelText: 'Référence',
        filled: true,
        fillColor: AppColors.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      items: [
        const DropdownMenuItem<Reference>(
          value: null,
          child: Text('- Choisir référence -'),
        ),
        ...refs.map((ref) => DropdownMenuItem<Reference>(
          value: ref,
          child: Text(
            ref.name,
            overflow: TextOverflow.ellipsis,
          ),
        )),
      ],
      onChanged: (value) {
        setState(() => _selectedReference = value);
      },
      isExpanded: true,
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _saveLocally,
                icon: const Icon(Icons.save_alt_rounded),
                label: const Text('Sauvegarder'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _uploadImage,
                icon: const Icon(Icons.cloud_upload_rounded),
                label: const Text('Télécharger'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaTypeButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;
  
  const _MediaTypeButton({
    required this.label,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? color : color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? color : Colors.transparent,
              width: 2,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : color,
            ),
          ),
        ),
      ),
    );
  }
}

class _DrawingPath {
  final List<Offset> points = [];
  final Color color;
  final double strokeWidth;
  
  _DrawingPath({
    required this.color,
    required this.strokeWidth,
  });
}

class _DrawingPainter extends CustomPainter {
  final List<_DrawingPath> paths;
  final _DrawingPath? currentPath;
  
  _DrawingPainter({
    required this.paths,
    this.currentPath,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final path in paths) {
      _drawPath(canvas, path);
    }
    
    if (currentPath != null) {
      _drawPath(canvas, currentPath!);
    }
  }

  void _drawPath(Canvas canvas, _DrawingPath drawingPath) {
    if (drawingPath.points.isEmpty) return;
    
    final paint = Paint()
      ..color = drawingPath.color
      ..strokeWidth = drawingPath.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    
    final path = Path();
    path.moveTo(drawingPath.points.first.dx, drawingPath.points.first.dy);
    
    for (int i = 1; i < drawingPath.points.length; i++) {
      path.lineTo(drawingPath.points[i].dx, drawingPath.points[i].dy);
    }
    
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _DrawingPainter oldDelegate) {
    return true;
  }
}
