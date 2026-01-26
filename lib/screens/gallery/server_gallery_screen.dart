import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../providers/media_provider.dart';

/// Server gallery screen showing images from the server
class ServerGalleryScreen extends StatefulWidget {
  final int referenceId;
  final String referenceName;
  
  const ServerGalleryScreen({
    super.key,
    required this.referenceId,
    required this.referenceName,
  });

  @override
  State<ServerGalleryScreen> createState() => _ServerGalleryScreenState();
}

class _ServerGalleryScreenState extends State<ServerGalleryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MediaProvider>().loadServerMedia(widget.referenceId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text('Médias serveur'),
            Text(
              widget.referenceName,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                color: AppColors.textSecondary.withValues(alpha: 0.7),
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => context.read<MediaProvider>().loadServerMedia(widget.referenceId),
          ),
        ],
      ),
      body: Consumer<MediaProvider>(
        builder: (context, mediaProvider, child) {
          if (mediaProvider.isLoading) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }
          
          if (mediaProvider.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 64,
                    color: AppColors.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    mediaProvider.error!,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => mediaProvider.loadServerMedia(widget.referenceId),
                    child: const Text('Réessayer'),
                  ),
                ],
              ),
            );
          }
          
          if (mediaProvider.serverMediaIds.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.cloud_off_outlined,
                    size: 80,
                    color: AppColors.textLight.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Aucun média disponible',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Aucune image n\'a été trouvée pour cette référence',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      color: AppColors.textLight.withValues(alpha: 0.7),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }
          
          return RefreshIndicator(
            onRefresh: () => mediaProvider.loadServerMedia(widget.referenceId),
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: mediaProvider.serverMediaIds.length,
              itemBuilder: (context, index) {
                final imageId = int.tryParse(mediaProvider.serverMediaIds[index]) ?? 0;
                final thumbnailUrl = mediaProvider.getImageUrl(imageId, thumbnail: true);
                
                return _ServerImageTile(
                  imageId: imageId,
                  thumbnailUrl: thumbnailUrl,
                  onTap: () {
                    Navigator.pushNamed(
                      context,
                      AppRoutes.edit,
                      arguments: {
                        'imagePath': null,
                        'imageId': imageId,
                      },
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _ServerImageTile extends StatelessWidget {
  final int imageId;
  final String thumbnailUrl;
  final VoidCallback onTap;
  
  const _ServerImageTile({
    required this.imageId,
    required this.thumbnailUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CachedNetworkImage(
            imageUrl: thumbnailUrl,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(
              color: AppColors.surfaceVariant,
              child: const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            errorWidget: (context, url, error) => Container(
              color: AppColors.surfaceVariant,
              child: const Icon(
                Icons.broken_image_outlined,
                color: AppColors.textLight,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
