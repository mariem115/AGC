# AGC Flutter - Contrôle Qualité

Application mobile cross-platform de contrôle qualité développée avec Flutter.

## Description

AGC (Appareil Gestion de Contrôle) est une application de contrôle qualité utilisée dans le secteur manufacturier. Elle permet aux inspecteurs qualité de :

- Se connecter avec les identifiants de l'entreprise
- Parcourir les références produits (composants, semi-finis, produits finis)
- Capturer des photos/vidéos des produits
- Annoter les images avec des marqueurs qualité (OK/NOK/Neutre)
- Télécharger les médias vers un serveur central
- Visualiser les médias existants pour chaque référence

## Fonctionnalités

- **Authentification** : Connexion sécurisée avec email, société et mot de passe
- **Capture de médias** : Prise de photos et vidéos avec la caméra
- **Annotation d'images** : Dessin sur les images avec codes couleur (Vert=OK, Rouge=NOK, Bleu=Neutre)
- **Filtrage des références** : Recherche et filtres par type de produit
- **Galerie locale** : Visualisation des images sauvegardées localement
- **Galerie serveur** : Accès aux médias stockés sur le serveur
- **Navigation complète** : Retour arrière entre les écrans
- **Déconnexion** : Possibilité de se déconnecter de l'application

## Prérequis

- Flutter SDK 3.8.0 ou supérieur
- Android Studio ou VS Code avec extensions Flutter
- Appareil Android ou iOS / Émulateur

## Installation

1. Cloner le projet :
```bash
git clone [repository-url]
cd agc_flutter
```

2. Installer les dépendances :
```bash
flutter pub get
```

3. Lancer l'application :
```bash
flutter run
```

## Structure du projet

```
lib/
├── main.dart              # Point d'entrée
├── app.dart               # Configuration MaterialApp
├── config/                # Configuration
│   ├── constants.dart     # Constantes API
│   ├── routes.dart        # Routes navigation
│   └── theme.dart         # Thème visuel
├── models/                # Modèles de données
├── providers/             # État de l'application
├── screens/               # Écrans UI
├── services/              # Services API
├── utils/                 # Utilitaires
└── widgets/               # Composants réutilisables
```

## Configuration API

L'URL de base de l'API peut être modifiée dans `lib/config/constants.dart` :

```dart
static const String baseUrl = 'https://www.quali-one.com/QualiOne/WorksSession/AGC/AGC.aspx';
```

## Build

### Android
```bash
flutter build apk --release
```

### iOS
```bash
flutter build ios --release
```

## Développé par

QualiFour - 2026

## Licence

Propriétaire - Tous droits réservés
