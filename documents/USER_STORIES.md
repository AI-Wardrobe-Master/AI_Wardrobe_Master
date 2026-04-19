# AI Wardrobe Master - User Stories

## Overview
This document contains user stories for the AI Wardrobe Master application Phase 1, organized by module and user type.

---

## User Types

### Consumer (普通用户)
End users who manage their personal clothing items, import creator content, and create outfit combinations.

### Creator (内容创作者/主播)
Content creators who upload clothing assets, create outfit collections, and share them with consumers.

---

## Module 1: Clothing Digitalization and Registration

### US-1.1: Capture Clothing Images
**As a** Consumer  
**I want to** capture front and back view images of my clothing using my mobile device camera  
**So that** I can digitize my physical wardrobe items into the app

**Acceptance Criteria:**
- User can access device camera from within the app
- User can capture front view image of clothing item
- User can capture back view image of clothing item
- System provides visual guidance for optimal photo capture
- Captured images are temporarily stored for processing

---

### US-1.2: Background Removal
**As a** Consumer  
**I want to** have backgrounds automatically removed from my clothing photos  
**So that** my clothing items appear as clean, isolated assets

**Acceptance Criteria:**
- System automatically processes captured images to remove background
- Both original and processed (background-removed) images are stored
- User can view the processed result
- Processing completes within reasonable time (<10 seconds per image)

---

### US-1.3: Multi-Angle View Generation
**As a** Consumer  
**I want to** see my clothing items from multiple angles (every 45 degrees)  
**So that** I can better visualize how items look from different perspectives

**Acceptance Criteria:**
- System generates 8 angle views (0°, 45°, 90°, 135°, 180°, 225°, 270°, 315°)
- Generated images maintain consistent quality across all angles
- All angle-specific images are stored with the clothing record
- User can browse through different angle views in the UI

---

### US-1.4: Persistent Storage
**As a** Consumer  
**I want to** have my clothing items permanently saved in the app  
**So that** I can access them anytime, even after closing and reopening the app

**Acceptance Criteria:**
- Clothing records are stored in persistent local database
- All associated images (original, processed, multi-angle) are linked to the record
- Data persists across app restarts
- Data integrity is maintained (no corruption or loss)

---

## Module 2: Automated Classification and Search Support

### US-2.1: Automatic Classification
**As a** Consumer  
**I want to** have my clothing items automatically classified with tags  
**So that** I don't have to manually categorize each item

**Acceptance Criteria:**
- System uses AI/ML to classify clothing and return Tag[] (e.g., category)
- Tags are returned as `{key: string, value: string}` pairs
- No confidence scores are displayed to the user
- Classification happens synchronously during image upload, before 3D generation starts
- Predicted tags are stored separately from user-confirmed tags
- **Phase 1**: Only `category` tag is auto-predicted (9 basic types: t-shirt, shirt, longsleeve, pants, shorts, outwear, dress, shoes, hat)
- **Future phases**: Additional attributes (color, pattern, style) will be auto-predicted

---

### US-2.2: Color and Pattern Detection
**As a** Consumer  
**I want to** have colors and patterns automatically detected for my clothing  
**So that** I can search and filter by these attributes

**Acceptance Criteria:**
- System detects primary and secondary colors from clothing images
- System identifies patterns (solid, striped, floral, geometric, etc.)
- Color and pattern attributes are stored with the clothing record
- User can manually edit detected colors and patterns if incorrect

---

### US-2.3: Additional Attributes
**As a** Consumer  
**I want to** assign additional attributes like style, season, and target audience to my clothing  
**So that** I can organize and search my wardrobe more effectively

**Acceptance Criteria:**
- System provides predefined categories for: style, season, target audience
- User can select/edit these attributes for each clothing item
- Attributes are stored with the clothing record
- UI provides intuitive selection interface (dropdowns, chips, etc.)

---

### US-2.4: Manual Correction
**As a** Consumer  
**I want to** review and correct automatic classification results  
**So that** my clothing database is accurate

**Acceptance Criteria:**
- User can view all predicted tags (predictedTags)
- User can edit tags to create final confirmed tags (finalTags)
- Manual corrections are stored separately from predicted tags
- Predicted tags remain immutable for reference
- Changes are immediately reflected in search results (which use finalTags only)

---

### US-2.5: Fast Search
**As a** Consumer  
**I want to** search my clothing items by tags and keywords in under 1 second  
**So that** I can quickly find what I'm looking for

**Acceptance Criteria:**
- Search returns results in <1 second for databases up to 1000 items
- Search uses finalTags only (not predictedTags)
- Search supports filtering by tag key-value pairs (e.g., category=T_SHIRT, color=blue)
- Search supports multiple filters simultaneously
- Search results can be filtered by source (Owned vs Imported)

---

## Module 3: Wardrobe Management

### US-3.1: Create Wardrobe
**As a** Consumer  
**I want to** create multiple wardrobes (e.g., "Summer", "Work", "Casual")  
**So that** I can organize my clothing into logical collections

**Acceptance Criteria:**
- User can create new wardrobe with custom name
- User can rename existing wardrobe
- User can delete wardrobe (without deleting clothing items)
- System supports unlimited number of wardrobes

---

### US-3.2: Manage Wardrobe Items
**As a** Consumer  
**I want to** add and remove clothing items from my wardrobes  
**So that** I can organize items across different collections

**Acceptance Criteria:**
- User can add existing clothing item to any wardrobe
- Same clothing item can exist in multiple wardrobes simultaneously
- User can remove item from wardrobe (item still exists in database)
- Removing item from all wardrobes doesn't delete the item entity

---

### US-3.3: Virtual Wardrobe
**As a** Consumer  
**I want to** have a separate virtual wardrobe for imported creator content  
**So that** I can keep platform content separate from my owned items

**Acceptance Criteria:**
- System automatically creates "Virtual Wardrobe" for imported items
- Virtual wardrobe is visually distinguished from owned wardrobes
- Items in virtual wardrobe are marked as "not owned"
- User can browse virtual wardrobe like regular wardrobes

---

## Module 4: Platform Content and Outfit Collections

### US-4.0: Capability-Driven Unified Role Experience
**As a** signed-in user  
**I want** the app to expose creator capabilities based on my current status  
**So that** the same shell can support consumers, creators under review, active creators, and restricted creators without splitting the product

**Acceptance Criteria:**
- App keeps a unified `Wardrobe / Discover / Outfit / Profile` shell for all users
- User state is driven by capability and creator profile status, not only by a coarse `type`
- Profile shows the correct creator state card: not enabled, pending, active, or suspended
- Discover and Profile reveal or disable creator entry points based on capability
- Frontend can derive display state from a lightweight user context endpoint

---

### US-4.1: Creator Upload
**As a** Creator  
**I want to** upload clothing items to the platform  
**So that** I can share my fashion content with consumers

**Acceptance Criteria:**
- Creator can upload clothing images (same process as consumer)
- Creator can add detailed descriptions and tags
- Uploaded items are stored with creator attribution
- Creator can edit or delete their uploaded items

---

### US-4.2: Create Card Pack
**As a** Creator  
**I want to** create and publish outfit collections (Card Packs)  
**So that** I can share curated clothing combinations with my audience

**Acceptance Criteria:**
- Creator can select multiple clothing items to create a pack
- Creator can name and describe the pack
- Creator can generate shareable link for the pack
- Pack includes all selected items and metadata

---

### US-4.3: Browse Creator Content
**As a** Consumer  
**I want to** browse available creator content and outfit collections  
**So that** I can discover new fashion inspiration

**Acceptance Criteria:**
- User can view list of available creators
- User can browse creator's published card packs
- User can preview items in a pack before importing
- User can see pack metadata (name, description, item count)

---

### US-4.4: Import Card Pack
**As a** Consumer  
**I want to** import creator card packs with one click  
**So that** I can quickly add curated content to my virtual wardrobe

**Acceptance Criteria:**
- User can import pack via shareable link
- All items in pack are added to virtual wardrobe
- Items are marked with source/provenance information (creator, date)
- Imported items are kept separate from owned items
- Import process completes in <5 seconds for packs up to 20 items

---

## Module 5: Outfit Visualization

### US-5.1: Start Outfit Preview Task
**As a** Consumer  
**I want to** submit a selfie and selected clothing items for outfit preview  
**So that** I can generate a preview before deciding whether to save the look

**Acceptance Criteria:**
- User can browse both owned and virtual wardrobes
- User can submit one selfie plus one item or a supported full outfit combination
- Frontend validates supported combinations before calling backend
- Preview request is created as an asynchronous task
- The task keeps references to the selected wardrobe items instead of detached uploads

---

### US-5.2: Track Outfit Preview Progress
**As a** Consumer  
**I want to** see the status of my preview generation request  
**So that** I know whether the preview is pending, processing, completed, or failed

**Acceptance Criteria:**
- System returns preview task status and timestamps
- Completed tasks expose a generated preview image
- Failed tasks expose a readable error message
- User can review past preview tasks from the app

---

### US-5.3: Save Successful Preview as Outfit
**As a** Consumer  
**I want to** save a successful preview as an outfit  
**So that** I can quickly access my favorite looks later

**Acceptance Criteria:**
- Only completed preview tasks can be saved as outfits
- Saved outfit keeps a reference to the source preview task
- Saved outfit stores the final preview image and related clothing items
- Saved outfit can optionally be named by the user

---

### US-5.4: Manage Saved Outfits
**As a** Consumer  
**I want to** view, rename, and delete my saved outfits  
**So that** I can manage my outfit collection

**Acceptance Criteria:**
- User can view thumbnail previews of all saved outfits
- User can rename saved outfit
- User can delete saved outfit
- Deleting outfit doesn't delete the clothing items
- Saved outfit management is separate from preview task execution

---

## Cross-Cutting User Stories

### US-X.1: Data Integrity
**As a** Consumer  
**I want to** have my clothing items remain intact regardless of wardrobe operations  
**So that** I never lose my digitized clothing data

**Acceptance Criteria:**
- Deleting wardrobe doesn't delete clothing items
- Removing item from wardrobe doesn't delete the item
- Clothing entity is stored once, referenced by multiple wardrobes
- System prevents orphaned or corrupted data

---

### US-X.2: Source Isolation
**As a** Consumer  
**I want to** keep imported creator content separate from my owned items  
**So that** I can distinguish between what I own and what is virtual

**Acceptance Criteria:**
- Every clothing item has source attribute (Owned/Imported)
- Imported items include provenance metadata (creator, import date)
- UI clearly distinguishes owned vs imported items
- Search and filter can separate by source

---

### US-X.3: Provenance Tracking
**As a** Consumer  
**I want to** see the origin information for imported items  
**So that** I can credit creators and track where content came from

**Acceptance Criteria:**
- Imported items store creator ID and name
- Imported items store import timestamp
- Imported items store original pack ID/name
- User can view provenance information in item details

---

## Priority Matrix

### P0 (Must Have - Phase 1 MVP)
- US-1.1, US-1.2, US-1.4 (Basic digitalization)
- US-2.1, US-2.4 (Classification with manual correction)
- US-2.5 (Search)
- US-3.1, US-3.2 (Basic wardrobe management)
- US-4.4 (Import capability)
- US-5.1, US-5.2, US-5.3 (Basic visualization)
- US-X.1, US-X.2, US-X.3 (Data integrity and isolation)

### P1 (Should Have - Phase 1)
- US-1.3 (Multi-angle views)
- US-2.2, US-2.3 (Enhanced attributes)
- US-3.3 (Virtual wardrobe)
- US-4.1, US-4.2, US-4.3 (Creator features)
- US-5.4 (Outfit management)

### P2 (Nice to Have - Future Phases)
- Advanced search filters
- Social sharing features
- Outfit recommendations
- Weather-based suggestions
