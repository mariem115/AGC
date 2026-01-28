/// API and app constants
class AppConstants {
  // API Configuration
  // Dev environment
  static const String baseUrl ='https://dev.quali-one.com/QualiOne/WorksSession/AGC/AGC.aspx';

  // For production:
  // static const String baseUrl =
  //     'https://www.quali-one.com/QualiOne/WorksSession/AGC/AGC.aspx';
  
  // API Actions
  static const String actionLogin = 'login';
  static const String actionGetAllReferences = 'getAllReferencesByCompany';
  static const String actionUploadImage = 'uploadImage';
  static const String actionGetImage = 'getImage';
  static const String actionGetThumb = 'getThumb';
  static const String actionGetIds = 'getIds';
  
  // Reference Types
  static const int referenceTypeComponent = 1;
  static const int referenceTypeSemiFinal = 2;
  static const int referenceTypeFinal = 3;
  
  // Media Types (base types)
  static const int mediaTypePhoto = 1;
  static const int mediaTypeVideo = 2;
  
  // Quality Status (used as mediaType for upload)
  static const int mediaTypeOK = 4;      // Bonne qualité
  static const int mediaTypeNOK = 5;     // Mauvaise qualité
  static const int mediaTypeNeutral = 6; // Neutre
  
  // Storage Keys
  static const String keyIsLoggedIn = 'is_logged_in';
  static const String keyUserEmail = 'user_email';
  static const String keyCompanyName = 'company_name';
  static const String keyCompanyId = 'company_id';
  static const String keyProductsList = 'products_list';
  
  // Timeouts
  static const int connectionTimeout = 30; // seconds
  static const int uploadTimeout = 120; // seconds
  
  // App Info
  static const String appName = 'AGC';
  static const String appVersion = '2.0.0';
}
