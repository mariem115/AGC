import 'package:flutter/material.dart';
import '../screens/splash/splash_screen.dart';
import '../screens/login/login_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/capture/capture_screen.dart';
import '../screens/edit/edit_screen.dart';
import '../screens/gallery/gallery_screen.dart';
import '../screens/gallery/server_gallery_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/review/photo_review_screen.dart';
import '../screens/brouillon/brouillon_screen.dart';

/// Route names
class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String home = '/home';
  static const String capture = '/capture';
  static const String edit = '/edit';
  static const String gallery = '/gallery';
  static const String serverGallery = '/server-gallery';
  static const String settings = '/settings';
  static const String photoReview = '/photo-review';
  static const String brouillon = '/brouillon';
}

/// Route generator
class AppRouter {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.splash:
        return _buildRoute(const SplashScreen(), settings);
      
      case AppRoutes.login:
        return _buildRoute(const LoginScreen(), settings);
      
      case AppRoutes.home:
        return _buildRoute(const HomeScreen(), settings);
      
      case AppRoutes.capture:
        final args = settings.arguments as Map<String, dynamic>?;
        final isVideo = args?['isVideo'] ?? false;
        return _buildRoute(CaptureScreen(isVideo: isVideo), settings);
      
      case AppRoutes.edit:
        final args = settings.arguments as Map<String, dynamic>;
        return _buildRoute(
          EditScreen(
            imagePath: args['imagePath'],
            imageId: args['imageId'],
          ),
          settings,
        );
      
      case AppRoutes.gallery:
        return _buildRoute(const GalleryScreen(), settings);
      
      case AppRoutes.serverGallery:
        final args = settings.arguments as Map<String, dynamic>;
        return _buildRoute(
          ServerGalleryScreen(
            referenceId: args['referenceId'],
            referenceName: args['referenceName'],
          ),
          settings,
        );
      
      case AppRoutes.settings:
        return _buildRoute(const SettingsScreen(), settings);
      
      case AppRoutes.photoReview:
        final args = settings.arguments as Map<String, dynamic>;
        return _buildRoute(
          PhotoReviewScreen(
            imagePath: args['imagePath'],
            isVideo: args['isVideo'] ?? false,
            draftId: args['draftId'],
          ),
          settings,
        );
      
      case AppRoutes.brouillon:
        return _buildRoute(const BrouillonScreen(), settings);
      
      default:
        return _buildRoute(const SplashScreen(), settings);
    }
  }
  
  static PageRouteBuilder _buildRoute(Widget page, RouteSettings settings) {
    return PageRouteBuilder(
      settings: settings,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(1.0, 0.0);
        const end = Offset.zero;
        const curve = Curves.easeInOutCubic;
        
        var tween = Tween(begin: begin, end: end).chain(
          CurveTween(curve: curve),
        );
        
        return SlideTransition(
          position: animation.drive(tween),
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 300),
    );
  }
}
