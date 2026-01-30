import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../utils/validators.dart';
import '../../widgets/common/custom_button.dart';
import '../../widgets/common/custom_text_field.dart';
import '../../widgets/common/loading_overlay.dart';

/// Login screen with email, company, and password fields
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _companyController = TextEditingController();
  final _passwordController = TextEditingController();
  
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  
  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOut));
    
    _animationController.forward();
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    _emailController.dispose();
    _companyController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
  
  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    
    final authProvider = context.read<AuthProvider>();
    
    final success = await authProvider.login(
      _emailController.text.trim(),
      _companyController.text.trim(),
      _passwordController.text,
    );
    
    if (!mounted) return;
    
    if (success) {
      Navigator.pushReplacementNamed(context, AppRoutes.home);
    } else {
      _showErrorSnackbar(authProvider.error ?? 'Erreur de connexion');
    }
  }
  
  void _showErrorSnackbar(String message) {
    // Suppressed for demo - error handling logic remains
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        return LoadingOverlay(
          isLoading: authProvider.isLoading,
          message: 'Connexion en cours...',
          child: Scaffold(
            body: Container(
              decoration: const BoxDecoration(
                gradient: AppColors.backgroundGradient,
              ),
              child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Center content vertically on larger screens
                    final isLargeScreen = constraints.maxHeight > 700;
                    
                    return SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: FadeTransition(
                          opacity: _fadeAnimation,
                          child: SlideTransition(
                            position: _slideAnimation,
                            child: Column(
                              mainAxisAlignment: isLargeScreen 
                                  ? MainAxisAlignment.center 
                                  : MainAxisAlignment.start,
                              children: [
                                SizedBox(height: isLargeScreen ? 0 : 32),
                                
                                // Logo section - prominent placement
                                _buildLogoSection(),
                                
                                const SizedBox(height: 32),
                                
                                // Login form
                                _buildLoginForm(),
                                
                                const SizedBox(height: 32),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildLogoSection() {
    return Column(
      children: [
        // Logo container - prominent size for login
        Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.all(14),
          child: Image.asset(
            'assets/images/qualifour_logo.png',
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              // Try alternate logo file
              return Image.asset(
                'assets/images/logo.png',
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return _buildTextLogo();
                },
              );
            },
          ),
        ),
        
        const SizedBox(height: 24),
        
        // Welcome text
        const Text(
          'Bienvenue',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        
        const SizedBox(height: 6),
        
        Text(
          'Connectez-vous pour continuer',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14,
            color: AppColors.textSecondary.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
  
  Widget _buildTextLogo() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'Q',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 52,
                fontWeight: FontWeight.bold,
                color: AppColors.dark,
                height: 0.9,
              ),
            ),
            Text(
              '4',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 40,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
                height: 1.1,
              ),
            ),
          ],
        ),
      ],
    );
  }
  
  Widget _buildLoginForm() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Company field
            CustomTextField(
              label: 'Société',
              hint: 'Nom de votre société',
              controller: _companyController,
              validator: Validators.company,
              prefixIcon: Icons.business_outlined,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.next,
            ),
            
            const SizedBox(height: 16),
            
            // Email field
            CustomTextField(
              label: 'Email',
              hint: 'votre@email.com',
              controller: _emailController,
              validator: Validators.required,
              prefixIcon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
            ),
            
            const SizedBox(height: 16),
            
            // Password field
            CustomTextField(
              label: 'Mot de passe',
              hint: '••••••••',
              controller: _passwordController,
              validator: Validators.password,
              obscureText: true,
              prefixIcon: Icons.lock_outlined,
              textInputAction: TextInputAction.done,
              onEditingComplete: _handleLogin,
            ),
            
            const SizedBox(height: 24),
            
            // Login button
            GradientButton(
              text: 'Se connecter',
              onPressed: _handleLogin,
              icon: Icons.login_rounded,
            ),
          ],
        ),
      ),
    );
  }
}
