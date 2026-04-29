# AI Wardrobe Master - Flutter Architecture

## Overview
This document defines the Flutter application architecture for AI Wardrobe Master, including project structure, state management, navigation, and recommended packages.

---

## Current Project Status

**Framework:** Flutter 3.10.7+  
**Language:** Dart 3.x  
**Platforms:** iOS, Android (primary), Web (optional for demo)  
**Current State:** Fresh Flutter project with default template

---

## Recommended Project Structure

```
ai_wardrobe_app/
├── lib/
│   ├── main.dart                          # App entry point
│   │
│   ├── core/                              # Core utilities and constants
│   │   ├── constants/
│   │   │   ├── app_constants.dart         # App-wide constants
│   │   │   ├── api_constants.dart         # API endpoints
│   │   │   └── asset_constants.dart       # Asset paths
│   │   ├── theme/
│   │   │   ├── app_theme.dart             # Theme configuration
│   │   │   ├── app_colors.dart            # Color palette
│   │   │   └── app_text_styles.dart       # Text styles
│   │   ├── utils/
│   │   │   ├── logger.dart                # Logging utility
│   │   │   ├── validators.dart            # Input validators
│   │   │   └── date_formatter.dart        # Date formatting
│   │   └── errors/
│   │       ├── exceptions.dart            # Custom exceptions
│   │       └── failures.dart              # Error handling
│   │
│   ├── data/                              # Data layer
│   │   ├── models/                        # Data models
│   │   │   ├── clothing_item.dart
│   │   │   ├── wardrobe.dart
│   │   │   ├── outfit.dart
│   │   │   ├── card_pack.dart
│   │   │   └── user.dart
│   │   ├── repositories/                  # Repository implementations
│   │   │   ├── clothing_repository.dart
│   │   │   ├── wardrobe_repository.dart
│   │   │   ├── outfit_repository.dart
│   │   │   └── auth_repository.dart
│   │   ├── datasources/                   # Data sources
│   │   │   ├── local/
│   │   │   │   ├── database_helper.dart   # SQLite helper
│   │   │   │   └── shared_prefs_helper.dart
│   │   │   └── remote/
│   │   │       ├── api_client.dart        # HTTP client
│   │   │       └── api_service.dart       # API endpoints
│   │   └── providers/                     # Data providers (if using Provider)
│   │
│   ├── domain/                            # Business logic layer
│   │   ├── entities/                      # Business entities
│   │   │   ├── clothing_item_entity.dart
│   │   │   ├── wardrobe_entity.dart
│   │   │   └── outfit_entity.dart
│   │   ├── repositories/                  # Repository interfaces
│   │   │   └── i_clothing_repository.dart
│   │   └── usecases/                      # Use cases
│   │       ├── clothing/
│   │       │   ├── add_clothing_item.dart
│   │       │   ├── get_clothing_items.dart
│   │       │   └── search_clothing.dart
│   │       ├── wardrobe/
│   │       │   ├── create_wardrobe.dart
│   │       │   └── add_item_to_wardrobe.dart
│   │       └── outfit/
│   │           ├── create_outfit.dart
│   │           └── save_outfit.dart
│   │
│   ├── presentation/                      # UI layer
│   │   ├── screens/                       # Full screens
│   │   │   ├── auth/
│   │   │   │   ├── login_screen.dart
│   │   │   │   └── register_screen.dart
│   │   │   ├── home/
│   │   │   │   └── home_screen.dart
│   │   │   ├── clothing/
│   │   │   │   ├── add_clothing_screen.dart
│   │   │   │   ├── clothing_detail_screen.dart
│   │   │   │   └── clothing_list_screen.dart
│   │   │   ├── wardrobe/
│   │   │   │   ├── wardrobe_list_screen.dart
│   │   │   │   └── wardrobe_detail_screen.dart
│   │   │   ├── outfit/
│   │   │   │   ├── outfit_creator_screen.dart
│   │   │   │   └── outfit_list_screen.dart
│   │   │   ├── creator/
│   │   │   │   ├── creator_profile_screen.dart
│   │   │   │   └── card_pack_screen.dart
│   │   │   └── search/
│   │   │       └── search_screen.dart
│   │   │
│   │   ├── widgets/                       # Reusable widgets
│   │   │   ├── common/
│   │   │   │   ├── app_button.dart
│   │   │   │   ├── app_text_field.dart
│   │   │   │   ├── loading_indicator.dart
│   │   │   │   └── error_widget.dart
│   │   │   ├── clothing/
│   │   │   │   ├── clothing_card.dart
│   │   │   │   ├── clothing_grid.dart
│   │   │   │   └── angle_viewer.dart
│   │   │   ├── wardrobe/
│   │   │   │   └── wardrobe_card.dart
│   │   │   └── outfit/
│   │   │       ├── outfit_canvas.dart
│   │   │       └── outfit_item_widget.dart
│   │   │
│   │   └── state/                         # State management
│   │       ├── providers/                 # Provider/Riverpod providers
│   │       │   ├── auth_provider.dart
│   │       │   ├── clothing_provider.dart
│   │       │   ├── wardrobe_provider.dart
│   │       │   └── outfit_provider.dart
│   │       └── blocs/                     # BLoC (if using BLoC pattern)
│   │           ├── auth/
│   │           ├── clothing/
│   │           └── wardrobe/
│   │
│   └── services/                          # Services
│       ├── camera_service.dart            # Camera integration
│       ├── image_processing_service.dart  # Image processing
│       ├── clothing_api_service.dart      # Upload, processing status, tag/detail retrieval
│       ├── storage_service.dart           # File storage
│       └── notification_service.dart      # Notifications
│
├── assets/                                # Static assets
│   ├── images/
│   │   ├── logo.png
│   │   └── placeholder.png
│   ├── icons/
│   └── fonts/
│
├── test/                                  # Tests
│   ├── unit/
│   ├── widget/
│   └── integration/
│
└── pubspec.yaml                           # Dependencies
```

---

## Recommended Packages

### Core Dependencies

```yaml
dependencies:
  flutter:
    sdk: flutter
  
  # State Management
  provider: ^6.1.1              # Simple state management
  # OR
  flutter_riverpod: ^2.4.9      # Advanced state management
  # OR
  flutter_bloc: ^8.1.3          # BLoC pattern
  
  # Navigation
  go_router: ^13.0.0            # Declarative routing
  
  # Network
  dio: ^5.4.0                   # HTTP client
  retrofit: ^4.0.3              # Type-safe API client
  pretty_dio_logger: ^1.3.1     # Network logging
  
  # Local Storage
  sqflite: ^2.3.0               # SQLite database
  shared_preferences: ^2.2.2    # Key-value storage
  hive: ^2.2.3                  # NoSQL database (alternative)
  hive_flutter: ^1.1.0
  
  # Image Handling
  image_picker: ^1.0.7          # Camera/gallery access
  camera: ^0.10.5+9             # Camera control
  image: ^4.1.3                 # Image manipulation
  cached_network_image: ^3.3.1  # Image caching
  
  # UI Components
  flutter_svg: ^2.0.9           # SVG support
  shimmer: ^3.0.0               # Loading shimmer effect
  flutter_staggered_grid_view: ^0.7.0  # Grid layouts
  
  # Utilities
  intl: ^0.19.0                 # Internationalization
  uuid: ^4.3.3                  # UUID generation
  path_provider: ^2.1.2         # File paths
  permission_handler: ^11.2.0   # Permissions
  
  # Dependency Injection
  get_it: ^7.6.7                # Service locator
  injectable: ^2.3.2            # Code generation for DI
  
  # JSON Serialization
  json_annotation: ^4.8.1       # JSON annotations
  freezed_annotation: ^2.4.1    # Immutable models
  
  # Error Handling
  dartz: ^0.10.1                # Functional programming (Either)
  
  # Icons
  cupertino_icons: ^1.0.8

dev_dependencies:
  flutter_test:
    sdk: flutter
  
  # Linting
  flutter_lints: ^6.0.0
  
  # Code Generation
  build_runner: ^2.4.8
  json_serializable: ^6.7.1
  freezed: ^2.4.6
  injectable_generator: ^2.4.1
  retrofit_generator: ^8.0.6
  
  # Testing
  mockito: ^5.4.4
  bloc_test: ^9.1.5             # If using BLoC
```

---

## Architecture Pattern: Clean Architecture + MVVM

### Layers

1. **Presentation Layer** (`presentation/`)
   - UI components (Screens, Widgets)
   - State management (Providers/BLoCs)
   - User interaction handling

2. **Domain Layer** (`domain/`)
   - Business entities
   - Use cases (business logic)
   - Repository interfaces

3. **Data Layer** (`data/`)
   - Repository implementations
   - Data sources (local/remote)
   - Data models with JSON serialization

### Data Flow

```
User Interaction
      ↓
  UI Widget
      ↓
State Manager (Provider/BLoC)
      ↓
   Use Case
      ↓
  Repository Interface
      ↓
Repository Implementation
      ↓
Data Source (Local/Remote)
      ↓
   Database/API
```

---

## State Management Recommendation

### Option 1: Provider (Recommended for Phase 1)

**Pros:**
- Simple and lightweight
- Official Flutter recommendation
- Easy to learn
- Good for small to medium apps

**Example:**
```dart
// clothing_provider.dart
class ClothingProvider extends ChangeNotifier {
  final ClothingRepository _repository;
  List<ClothingItem> _items = [];
  bool _isLoading = false;
  
  List<ClothingItem> get items => _items;
  bool get isLoading => _isLoading;
  
  Future<void> loadItems() async {
    _isLoading = true;
    notifyListeners();
    
    _items = await _repository.getItems();
    _isLoading = false;
    notifyListeners();
  }
}
```

### Option 2: Riverpod (Recommended for scaling)

**Pros:**
- Compile-time safety
- Better testability
- No BuildContext needed
- Excellent for complex apps

**Example:**
```dart
// clothing_provider.dart
final clothingProvider = StateNotifierProvider<ClothingNotifier, ClothingState>(
  (ref) => ClothingNotifier(ref.read(clothingRepositoryProvider)),
);

class ClothingNotifier extends StateNotifier<ClothingState> {
  final ClothingRepository _repository;
  
  ClothingNotifier(this._repository) : super(ClothingState.initial());
  
  Future<void> loadItems() async {
    state = state.copyWith(isLoading: true);
    final items = await _repository.getItems();
    state = state.copyWith(items: items, isLoading: false);
  }
}
```

---

## Navigation Strategy

### Using go_router

```dart
// app_router.dart
final appRouter = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(
      path: '/splash',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/home',
      builder: (context, state) => const HomeScreen(),
      routes: [
        GoRoute(
          path: 'clothing/:id',
          builder: (context, state) {
            final id = state.pathParameters['id']!;
            return ClothingDetailScreen(id: id);
          },
        ),
      ],
    ),
    GoRoute(
      path: '/wardrobe/:id',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return WardrobeDetailScreen(id: id);
      },
    ),
    GoRoute(
      path: '/outfit/create',
      builder: (context, state) => const OutfitCreatorScreen(),
    ),
  ],
);
```

---

### Web vs Mobile Shell Layout

For this project, we want **bottom navigation on mobile** and a **left-side navigation on web/large screens** while sharing the same core pages (`WardrobeScreen`, `DiscoverScreen`, `OutfitCanvasScreen`, `ProfileScreen`).

Implementation sketch:

```dart
// root_shell.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

class RootShell extends StatelessWidget {
  const RootShell({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900; // treat wide screens as desktop/web
        if (kIsWeb || isWide) {
          return const _WebRootShell();    // Left navigation + content
        }
        return const _MobileRootShell();   // Bottom nav bar
      },
    );
  }
}
```

- **`kIsWeb`**: true when running in the browser; false on iOS/Android/desktop.
- **`constraints.maxWidth`**: lets us treat very wide windows as \"desktop\" even on non-web platforms.

Patterns:

- `_MobileRootShell` uses a `BottomNavigationBar` with 4 items: `Wardrobe / Discover / Outfit / Profile`.
- `_WebRootShell` uses `Row + NavigationRail + IndexedStack`:
  - Left: `NavigationRail` with `Wardrobe / Discover / Outfit / Profile`.
  - Secondary creation actions such as `Add clothes`, `Create pack`, and `Start preview` should live inside page-level CTA areas rather than a fifth global tab.
  - Right: main content area with the same page widgets as mobile.

This keeps:

- **Business logic & pages shared** across platforms.
- **Shell layout swapped** automatically based on **platform + screen width**.

---

## Unified Role IA

The app should keep a single shell for all signed-in users and reveal creator functionality by capability, not by branching into separate apps.

### Navigation Rules

- Keep four top-level destinations: `Wardrobe / Discover / Outfit / Profile`
- Do not add a dedicated `Creator` tab at this stage
- Creator entry points belong in page sections, especially `Discover` and `Profile`

### Capability-Driven User States

Frontend should distinguish at least four creator-related display states:

- `State A`: normal consumer, no creator profile yet
- `State B`: creator profile exists but status is `PENDING`
- `State C`: creator profile exists and status is `ACTIVE`
- `State D`: creator profile exists and status is `SUSPENDED`

These states should be derived from `GET /me` plus creator profile status rather than inferred from a coarse user type alone.

### Page-Level IA

`Wardrobe`
- Keep owned and imported wardrobe management unified
- Surface the virtual wardrobe entry, but do not mix creator catalog management into this page

`Discover`
- Public content area: recommended creators, card packs, and share-link import
- Import area: recently imported packs and quick entry to virtual wardrobe
- Creator work area: only visible when capabilities allow publish / pack management
- Status guidance area: onboarding, pending review, or suspended-state messaging

`Outfit`
- Entry point for selecting owned and imported items
- Hosts preview-task creation, preview history, and saved outfit browsing
- Should not assume a fully manual canvas editor as the only interaction model

`Profile`
- User profile and settings for everyone
- Creator status card for all users
- Creator center only when capability allows it

### Creator Entry Strategy

- Primary creator work entry: `Discover -> 我的内容`
- Secondary creator settings entry: `Profile -> 创作者中心`
- `我的内容` should group creator upload, pack management, and creator stats in one place
- `创作者中心` should focus on profile state, application status, and account-level creator settings
- The app should not add a dedicated top-level creator tab before these two entry points are proven insufficient

### Required User Context Endpoints

- `GET /me` for shell gating and capability-driven visibility
- `GET /creators/me/profile` for full creator settings
- `GET /creators/me/dashboard` for Discover/Profile creator modules

### Recommended Shared Components

- `CapabilityGate` for capability and status-based visibility
- `CreatorStatusCard` for `NOT_ENABLED / PENDING / ACTIVE / SUSPENDED`
- `EntryCard` for secondary destinations such as Creator Center and Virtual Wardrobe
- `PreviewTaskCard` for displaying outfit preview task status and generated images

### Outfit Preview Frontend Flow

1. User selects one selfie and one or more referenced clothing items
2. Frontend validates allowed combinations before hitting backend
3. App submits `POST /outfit-preview-tasks`
4. App polls `GET /outfit-preview-tasks/:id` or refreshes task list
5. Completed preview can be saved through `POST /outfit-preview-tasks/:id/save`
6. Saved outfits are then managed through the `/outfits` endpoints

### Key User Flows

Upgrade creator:
- Open `Profile`
- Tap `开通发布能力`
- Fill creator profile
- Enter `PENDING`
- Surface creator UI only after `ACTIVE`

Creator publish flow:
- Open `Discover`
- Enter `我的内容`
- Upload creator items
- Create and publish card packs
- Return to `我的内容` for management

Consumer import flow:
- Open `Discover`
- Browse creators or open a share link
- Preview a published pack
- Import into the virtual wardrobe
- Open `Wardrobe` to inspect imported items

## Database Schema (SQLite)

### Tables

```sql
-- users table
CREATE TABLE users (
  id TEXT PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  email TEXT UNIQUE NOT NULL,
  type TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

-- clothing_items table
CREATE TABLE clothing_items (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  source TEXT NOT NULL,
  
  -- Tag-based classification (stored as JSON strings)
  predicted_tags TEXT NOT NULL DEFAULT '[]',  -- Immutable AI predictions
  final_tags TEXT NOT NULL DEFAULT '[]',      -- User-confirmed tags (used for search)
  is_confirmed INTEGER NOT NULL DEFAULT 0,
  
  -- Metadata
  name TEXT,
  description TEXT,
  custom_tags TEXT,  -- JSON array of strings
  
  -- Timestamps
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id)
);

-- Example tag structure in JSON:
-- predicted_tags: '[{"key":"category","value":"T_SHIRT"},{"key":"color","value":"blue"}]'
-- final_tags: '[{"key":"category","value":"SHIRT"},{"key":"color","value":"blue"}]'

-- images table
CREATE TABLE images (
  id TEXT PRIMARY KEY,
  clothing_item_id TEXT NOT NULL,
  type TEXT NOT NULL,
  url TEXT NOT NULL,
  angle INTEGER,
  FOREIGN KEY (clothing_item_id) REFERENCES clothing_items(id) ON DELETE CASCADE
);

-- provenance is no longer modeled as a standalone table.
-- Imported-item origin fields are stored on clothing_items and related import history records.

-- wardrobes table
CREATE TABLE wardrobes (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  name TEXT NOT NULL,
  type TEXT NOT NULL,
  description TEXT,
  item_count INTEGER DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id)
);

-- wardrobe_items junction table
CREATE TABLE wardrobe_items (
  id TEXT PRIMARY KEY,
  wardrobe_id TEXT NOT NULL,
  clothing_item_id TEXT NOT NULL,
  added_at INTEGER NOT NULL,
  display_order INTEGER,
  UNIQUE(wardrobe_id, clothing_item_id),
  FOREIGN KEY (wardrobe_id) REFERENCES wardrobes(id) ON DELETE CASCADE,
  FOREIGN KEY (clothing_item_id) REFERENCES clothing_items(id) ON DELETE CASCADE
);

-- outfits table
CREATE TABLE outfits (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  thumbnail_url TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id)
);

-- outfit_items table
CREATE TABLE outfit_items (
  id TEXT PRIMARY KEY,
  outfit_id TEXT NOT NULL,
  clothing_item_id TEXT NOT NULL,
  layer INTEGER NOT NULL,
  position_x REAL NOT NULL,
  position_y REAL NOT NULL,
  scale REAL NOT NULL,
  rotation INTEGER NOT NULL,
  FOREIGN KEY (outfit_id) REFERENCES outfits(id) ON DELETE CASCADE,
  FOREIGN KEY (clothing_item_id) REFERENCES clothing_items(id)
);

-- Indexes for performance
CREATE INDEX idx_clothing_user ON clothing_items(user_id);
CREATE INDEX idx_clothing_source ON clothing_items(source);
-- Note: SQLite doesn't support GIN indexes like PostgreSQL
-- For JSON search, use json_extract() in queries
CREATE INDEX idx_wardrobe_user ON wardrobes(user_id);
CREATE INDEX idx_wardrobe_items_wardrobe ON wardrobe_items(wardrobe_id);
CREATE INDEX idx_wardrobe_items_clothing ON wardrobe_items(clothing_item_id);
CREATE INDEX idx_outfit_user ON outfits(user_id);
```

---

## Data Models with Freezed

```dart
// clothing_item.dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'clothing_item.freezed.dart';
part 'clothing_item.g.dart';

@freezed
class ClothingItem with _$ClothingItem {
  const factory ClothingItem({
    required String id,
    required String userId,
    required ItemSource source,
    Provenance? provenance,
    required ImageSet images,
    @Default([]) List<Tag> predictedTags,  // Immutable AI predictions
    @Default([]) List<Tag> finalTags,      // User-confirmed tags
    @Default(false) bool isConfirmed,
    String? name,
    String? description,
    @Default([]) List<String> customTags,  // User-defined freeform tags
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _ClothingItem;

  factory ClothingItem.fromJson(Map<String, dynamic> json) =>
      _$ClothingItemFromJson(json);
}

/// Tag structure: {key: string, value: string}
@freezed
class Tag with _$Tag {
  const factory Tag({
    required String key,    // e.g., "category", "color", "pattern"
    required String value,  // e.g., "T_SHIRT", "blue", "striped"
  }) = _Tag;

  factory Tag.fromJson(Map<String, dynamic> json) => _$TagFromJson(json);
}

enum ItemSource {
  @JsonValue('OWNED')
  owned,
  @JsonValue('IMPORTED')
  imported,
}

enum ClothingType {
  // Tops
  @JsonValue('T_SHIRT')
  tShirt,
  @JsonValue('SHIRT')
  shirt,
  @JsonValue('BLOUSE')
  blouse,
  @JsonValue('POLO')
  polo,
  @JsonValue('TANK_TOP')
  tankTop,
  @JsonValue('SWEATER')
  sweater,
  @JsonValue('HOODIE')
  hoodie,
  @JsonValue('SWEATSHIRT')
  sweatshirt,
  @JsonValue('CARDIGAN')
  cardigan,
  
  // Bottoms
  @JsonValue('JEANS')
  jeans,
  @JsonValue('TROUSERS')
  trousers,
  @JsonValue('SHORTS')
  shorts,
  @JsonValue('SKIRT')
  skirt,
  @JsonValue('LEGGINGS')
  leggings,
  @JsonValue('SWEATPANTS')
  sweatpants,
  
  // Outerwear
  @JsonValue('JACKET')
  jacket,
  @JsonValue('COAT')
  coat,
  @JsonValue('BLAZER')
  blazer,
  @JsonValue('PUFFER')
  puffer,
  @JsonValue('WIND_BREAKER')
  windBreaker,
  @JsonValue('VEST')
  vest,
  
  // Full Body
  @JsonValue('DRESS')
  dress,
  @JsonValue('JUMPSUIT')
  jumpsuit,
  @JsonValue('ROMPER')
  romper,
  
  // Footwear
  @JsonValue('SNEAKERS')
  sneakers,
  @JsonValue('BOOTS')
  boots,
  @JsonValue('SANDALS')
  sandals,
  @JsonValue('DRESS_SHOES')
  dressShoes,
  @JsonValue('HEELS')
  heels,
  @JsonValue('SLIPPERS')
  slippers,
  
  // Accessories
  @JsonValue('HAT')
  hat,
  @JsonValue('SCARF')
  scarf,
  @JsonValue('BELT')
  belt,
  
  // Fallback
  @JsonValue('OTHER')
  other,
}
```

---

## Service Layer Example

```dart
// camera_service.dart
class CameraService {
  final ImagePicker _picker = ImagePicker();
  
  Future<XFile?> captureImage({
    required CameraDevice device,
  }) async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: device,
        imageQuality: 85,
      );
      return image;
    } catch (e) {
      throw CameraException('Failed to capture image: $e');
    }
  }
  
  Future<List<XFile>> captureFrontAndBack() async {
    final front = await captureImage(device: CameraDevice.rear);
    if (front == null) throw CameraException('Front capture cancelled');
    
    final back = await captureImage(device: CameraDevice.rear);
    if (back == null) throw CameraException('Back capture cancelled');
    
    return [front, back];
  }
}
```

---

## Dependency Injection Setup

```dart
// injection.dart
import 'package:get_it/get_it.dart';

final getIt = GetIt.instance;

void setupDependencies() {
  // Services
  getIt.registerLazySingleton(() => CameraService());
  getIt.registerLazySingleton(() => ImageProcessingService());
  getIt.registerLazySingleton(() => StorageService());
  
  // Data sources
  getIt.registerLazySingleton(() => DatabaseHelper());
  getIt.registerLazySingleton(() => ApiClient());
  
  // Repositories
  getIt.registerLazySingleton<ClothingRepository>(
    () => ClothingRepositoryImpl(
      localDataSource: getIt(),
      remoteDataSource: getIt(),
    ),
  );
  
  // Use cases
  getIt.registerLazySingleton(() => AddClothingItem(getIt()));
  getIt.registerLazySingleton(() => GetClothingItems(getIt()));
}
```

---

## Error Handling Pattern

```dart
// failures.dart
abstract class Failure {
  final String message;
  const Failure(this.message);
}

class ServerFailure extends Failure {
  const ServerFailure(super.message);
}

class CacheFailure extends Failure {
  const CacheFailure(super.message);
}

class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

// Using Either from dartz
import 'package:dartz/dartz.dart';

abstract class ClothingRepository {
  Future<Either<Failure, List<ClothingItem>>> getItems();
  Future<Either<Failure, ClothingItem>> addItem(ClothingItem item);
}
```

---

## Testing Strategy

### Unit Tests
```dart
// clothing_repository_test.dart
void main() {
  late ClothingRepository repository;
  late MockDatabaseHelper mockDb;
  
  setUp(() {
    mockDb = MockDatabaseHelper();
    repository = ClothingRepositoryImpl(localDataSource: mockDb);
  });
  
  test('should return list of clothing items', () async {
    // Arrange
    when(mockDb.getClothingItems()).thenAnswer((_) async => mockItems);
    
    // Act
    final result = await repository.getItems();
    
    // Assert
    expect(result.isRight(), true);
    result.fold(
      (failure) => fail('Should not fail'),
      (items) => expect(items.length, 3),
    );
  });
}
```

### Widget Tests
```dart
// clothing_card_test.dart
void main() {
  testWidgets('ClothingCard displays item name', (tester) async {
    final item = ClothingItem(/* ... */);
    
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClothingCard(item: item),
        ),
      ),
    );
    
    expect(find.text(item.name!), findsOneWidget);
  });
}
```

---

## Performance Optimization

### Image Caching
```dart
CachedNetworkImage(
  imageUrl: item.images.processedFrontUrl,
  placeholder: (context, url) => const ShimmerPlaceholder(),
  errorWidget: (context, url, error) => const Icon(Icons.error),
  memCacheWidth: 500,
  maxWidthDiskCache: 1000,
)
```

### Lazy Loading
```dart
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, index) {
    return ClothingCard(item: items[index]);
  },
)
```

### Database Optimization
- Use indexes on frequently queried columns
- Batch inserts for multiple items
- Use transactions for related operations
- Implement pagination for large datasets

---

## Security Considerations

1. **Secure Storage**
   - Use `flutter_secure_storage` for sensitive data (tokens, passwords)
   - Encrypt local database if storing sensitive information

2. **API Security**
   - Implement JWT token refresh mechanism
   - Use HTTPS only
   - Validate all user inputs

3. **Permissions**
   - Request camera permission before use
   - Request storage permission for image saving
   - Handle permission denial gracefully

---

## Next Steps for Implementation

1. **Phase 1.1: Setup**
   - Update `pubspec.yaml` with recommended packages
   - Create folder structure
   - Setup dependency injection
   - Configure routing

2. **Phase 1.2: Core Features**
   - Implement authentication
   - Create clothing item capture flow
   - Build wardrobe management
   - Implement search functionality

3. **Phase 1.3: Advanced Features**
   - Add outfit visualization
   - Implement creator features
   - Add import functionality

4. **Phase 1.4: Polish**
   - Add animations and transitions
   - Optimize performance
   - Write tests
   - Handle edge cases
