# AI Wardrobe Master - User Stories

## Overview

本文档保留 Phase 1 用户故事视角，但已同步当前实际落地的共享、Discover、个人页与可视化补充能力。

## User Types

### Consumer

管理自己的衣物、子衣柜、共享内容与可视化预览。

### Creator

发布可公开浏览的衣物与 card pack，并在 Discover 中被其他用户发现。

## Legacy Phase-1 Scope

本文件仍然保留原有五大模块视角，只是在这些模块之上补充本轮真正落地的共享和个人页能力：

1. 衣物数字化与录入
2. 自动分类与搜索
3. 衣柜管理
4. 平台内容与创作者内容
5. 搭配可视化

当前新增的用户故事主要落在模块 1、3、4、5 的交叉位置，例如：

- `/me` 驱动的个人页状态
- 公开子衣柜分享
- Discover 中公开共享内容的统一浏览
- 共享衣物只读详情
- `Face + Scene` demo 可视化入口

## Module 1: Authentication and User Context

### US-1.1 Register and bootstrap account

**As a** new user  
**I want to** register once and immediately enter a usable app state  
**So that** I do not need extra setup before seeing my wardrobe

**Acceptance Criteria**

- Register returns a valid login token
- System generates a stable `uid`
- System ensures the user has a main wardrobe
- User can enter the app shell immediately after registration

### US-1.2 Show correct signed-in profile

**As a** signed-in user  
**I want** my profile page to reflect my real account state  
**So that** I do not see `not signed in` after a successful login

**Acceptance Criteria**

- Profile reads current state from `/me`
- Profile shows `uid`, username, email, type
- Creator capability cards reflect current backend state

## Module 2: Wardrobe Management

### US-2.1 Manage main wardrobe vs sub wardrobe

**As a** user  
**I want** main wardrobe and sub wardrobe actions to behave differently  
**So that** delete does not accidentally mean the wrong thing

**Acceptance Criteria**

- Main wardrobe long-press delete removes the clothing entity
- Main wardrobe delete clears local cache
- Sub wardrobe long-press only removes wardrobe association
- Removing from a sub wardrobe does not delete the clothing entity

### US-2.2 Share a sub wardrobe publicly

**As a** user  
**I want** to share one sub wardrobe instead of my whole account  
**So that** I can publish a curated subset of my clothing cards

**Acceptance Criteria**

- User can see a share action while viewing a sub wardrobe
- If the sub wardrobe is not public yet, sharing makes it public first
- Shared wardrobe exposes a stable `wid`
- Other users can open the shared result by `wid`

### US-2.3 Search shared wardrobes

**As a** user  
**I want** to search shared wardrobes by publisher and wardrobe code  
**So that** I can find a specific public share quickly

**Acceptance Criteria**

- Discover supports searching by wardrobe name
- Discover supports searching by `wid`
- Discover supports searching by publisher `uid`
- Discover supports searching by publisher username

## Module 3: Discover and Public Content

### US-3.1 Merge packs and wardrobes in Discover

**As a** user  
**I want** public packs and shared wardrobes to appear in one wardrobe browse surface  
**So that** I do not need to understand backend source differences

**Acceptance Criteria**

- Discover has a `Wardrobes` tab for public shared wardrobes
- Published card packs also appear in the same public wardrobe list
- UI can distinguish `Card Pack` vs `Shared Wardrobe` by label
- Both items remain searchable through the same search box

### US-3.2 Open shared wardrobe details

**As a** user  
**I want** to open a shared wardrobe and browse its clothing cards  
**So that** I can inspect public content before deciding what to do next

**Acceptance Criteria**

- Tapping a public wardrobe opens a detail page
- Detail page shows wardrobe metadata including `wid`
- Detail page shows clothing cards belonging to that wardrobe

### US-3.3 Open shared clothing card details

**As a** user  
**I want** shared clothing cards to be tappable  
**So that** I can inspect the item instead of only seeing a grid preview

**Acceptance Criteria**

- Shared wardrobe item cards are tappable
- Tapping opens a read-only shared clothing detail screen
- Shared detail screen shows image, description, wardrobe WID and publisher UID
- Shared detail screen does not expose private delete/edit actions

### US-3.4 View shared images across accounts

**As a** second account viewing a public share  
**I want** to see the actual clothing images, not just names  
**So that** the public share is useful

**Acceptance Criteria**

- Public shared clothing image URLs are accessible cross-account
- Private clothing images remain inaccessible to unrelated users
- Cross-account shared wardrobe browsing works on a real device

## Module 4: Creator Content

### US-4.1 Publish card pack into public browse

**As a** creator  
**I want** a published card pack to appear in the same public discovery flow as other shared wardrobes  
**So that** consumers browse one unified public wardrobe surface

**Acceptance Criteria**

- Publishing a pack creates or reuses a public `SUB` wardrobe
- The mapped public wardrobe uses `source = CARD_PACK`
- Archiving the pack hides the mapped public wardrobe from Discover

### US-4.2 Capability-driven creator experience

**As a** signed-in user  
**I want** creator access to depend on backend capabilities  
**So that** the same app shell can support non-creators, pending creators and active creators

**Acceptance Criteria**

- `/me` returns creator profile summary and capabilities
- Profile UI uses capability flags to show creator-related entry points

## Module 5: Visualization

### US-5.1 Enter visualization from a unified hub

**As a** user  
**I want** visualization to provide both existing canvas workflow and the new face-plus-scene workflow  
**So that** I can choose the mode that fits my task

**Acceptance Criteria**

- `Visualize` opens a hub page
- Hub exposes `Canvas Studio`
- Hub exposes `Face + Scene`
- Header height aligns with other top-level pages such as `Discover`

### US-5.2 Run face plus scene demo flow

**As a** user  
**I want** to upload a face photo, choose a clothing card and add a scene description  
**So that** I can preview the intended second visualization path before the real model is deployed

**Acceptance Criteria**

- User can upload a face photo
- User can choose one clothing card
- User can input a scene description
- User can trigger `Generate Demo Preview`
- System returns a demo image and clearly behaves as a placeholder flow

## Priority Summary

### P0

- Correct signed-in profile state
- Public sub wardrobe sharing
- Discover search by `wid` and publisher `uid`
- Cross-account shared image visibility
- Shared clothing card tap-through
- Main wardrobe delete clears entity and cache

### P1

- Unified Discover browse for packs and wardrobes
- Capability-driven creator UI
- Visualize dual-mode hub
- Face plus scene demo flow

### P2

- Follow-up import actions from shared clothing detail
- Full production AI deployment for face plus scene generation
