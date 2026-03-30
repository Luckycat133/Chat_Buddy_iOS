# T17 — Feature Parity Completion

This document covers all features implemented in this iteration to close the remaining gaps between the web and iOS versions.

---

## 1. RAG Pipeline (`Services/RAG/RAGService.swift`)

**Purpose**: On-device Retrieval-Augmented Generation for knowledge base documents.

**Algorithm**: Hybrid search combining:
- **BM25** (50% weight): Term-frequency scoring with k1=1.5, b=0.75
- **Jaccard** (30% weight): Set similarity between query and chunk keywords
- **Cosine** (20% weight): 256-dim hash bag-of-words embeddings

**Core API**:
| Function | Description |
|---|---|
| `chunkText(_:chunkSize:overlap:)` | Split text into overlapping chunks respecting paragraph/sentence boundaries |
| `extractKeywords(_:topN:)` | TF-based keyword extraction with en/zh stop word filtering |
| `buildEmbedding(_:dim:)` | Hash bag-of-words → L2-normalized vector |
| `indexDocument(id:name:content:)` | Full pipeline: chunk → keywords → embed |
| `searchDocuments(query:indexedChunks:topK:)` | Hybrid search returning ranked results |
| `buildRAGContext(query:indexedChunks:topK:)` | Format search results for system prompt injection |

**Integration**: KnowledgeBaseView indexes on import, removes on delete. AIPipeline injects RAG context when ragEnabled.

---

## 2. Context Compressor (`Services/Chat/ContextCompressor.swift`)

**Purpose**: Compress long conversations by summarizing older messages and preserving recent ones.

**Parameters**: threshold=15 messages, recent window=8 messages.

**API**:
| Function | Description |
|---|---|
| `compress(messages:personas:)` | Returns `CompressionResult` with summary + recent messages |
| `compressedContext(messages:personas:)` | Returns ready-to-use message array with summary as system message |

**Algorithm**: Extracts participant names and topic keywords (by frequency) from older messages, produces a bracketed summary.

---

## 3. Notification Service (`Services/Notification/NotificationService.swift`)

**Purpose**: In-app notification sounds, unread badge counts, and DND mode.

**Features**:
- AudioToolbox system sound (ID 1007)
- Per-chat unread counts with persistence
- Settings: soundEnabled, doNotDisturb, soundVolume
- `notify(chatId:)` — increments unread + plays sound unless DND

---

## 4. Presence Service (`Services/Presence/PresenceService.swift`)

**Purpose**: Simulate online/offline/busy/away status for AI personas based on timezone schedules.

**Status enum**: online, offline, busy, away, doNotDisturb — each with icon, hex color, SwiftUI color, and localized label.

**Schedules**: 13 persona-specific schedules with timezone-aware hour calculation.

**Integration**: Status indicators displayed on friend avatars (FriendsView) and agent avatars (AgentsView).

---

## 5. Greeting Service (`Services/Presence/GreetingService.swift`)

**Purpose**: Proactive greetings when reopening a chat after idle time.

**Features**:
- Time-slot templates (morning/afternoon/evening/night + re-engagement)
- Per-persona cooldown (12h) + global cooldown (4h)
- Active only when persona status is online
- Persisted cooldown timestamps via StorageService

**Integration**: ChatView `.onAppear` checks for greeting and appends as assistant message.

---

## 6. Agent Skills Store (`Models/AgentSkillStore.swift`)

**Purpose**: 20 skill definitions across 6 categories for task-specialist agents.

**Categories**: programming, writing, research, education, emotional, creative.

**API**:
| Function | Description |
|---|---|
| `getSkillsByCategory(_:)` | Filter skills by category |
| `getSkillById(_:)` | Lookup by ID |
| `combineSkillPrompts(_:)` | Merge prompt enhancements for multiple skills |
| `getRequiredTools(_:)` | Unique tool list for skill set |
| `getSkillsForAgent(agentId:)` | Map agent ID keywords to relevant skills |

**Integration**: AgentsView shows skill badges per agent. AgentWorkspaceView shows skill section with category labels.

---

## 7. Sticker System

### StickerService (`Services/Chat/StickerService.swift`)
- 4 preset packs (12 stickers each): Emotions, Actions, Animals, Food
- 6 AI persona-specific sticker sets (6 each)
- Favorites (max 50) with toggle
- Recents (max 20) with auto-dedup
- Persisted via StorageService

### StickerPickerView (`Features/Chats/Components/StickerPickerView.swift`)
- Tab-based picker: Recent, Favorites, AI Persona, Packs
- 6-column LazyVGrid
- Long-press context menu for favorite toggle

**Integration**: Sticker button in MessageInputView. Sheet in ChatView inserts selected sticker into input.

---

## 8. Translation Service & UI

### TranslationService (`Services/Chat/TranslationService.swift`)
- Domain detection: technical (3+ pattern matches), literary (3+), general (fallback)
- 36 technical glossary entries, 6 literary entries
- Two-step reflective translation: step1 (direct) → step2 (refined)
- Domain-specific expert prompts
- Response parser handles step1/step2 markers with fallback

### TranslationCompareView (`Features/Chats/Components/TranslationCompareView.swift`)
- Auto-detect source language (Chinese vs English)
- Domain badge display
- Refined translation card + collapsible direct translation
- Calls AIClient for actual translation

**Integration**: "Translate" context menu on message bubbles → sheet with comparison view.

---

## 9. Rich Message Views (`Features/Chats/Components/RichMessageViews.swift`)

| View | Features |
|---|---|
| `ImageMessageView` | Base64→UIImage, fullscreen lightbox, MagnifyGesture (0.5x–3x) |
| `FileMessageView` | Extension-based icons, size formatting, preview text |
| `VoiceMessageView` | 16 random waveform bars, simulated playback with Timer, progress highlighting |

---

## 10. Markdown Content View (`Features/Chats/Components/MarkdownContentView.swift`)

**Features**:
- Fenced code blocks with language-specific keyword highlighting (Swift, JS/TS, Python)
- Copy button for code blocks
- Inline code detection with backtick styling
- Bold text with `**` markers
- String and comment highlighting via colored spans

**Integration**: MessageBubble detects markdown markers (``` ** `) and renders with MarkdownContentView.

---

## 11. Link Preview (`Features/Chats/Components/LinkPreviewView.swift`)

**Features**:
- URL extraction via regex (`https?://` patterns)
- Google favicon API for site icons
- Domain display
- Open-in-browser button

**Integration**: MessageBubble appends LinkPreviewView when URLs detected in plain text.

---

## 12. Avatar Upload (`Features/Settings/AvatarUploadSheet.swift`)

**Features**:
- PhotosPicker integration
- MagnifyGesture for zoom (0.5x–2x) + DragGesture for offset
- UIGraphicsImageRenderer crop to 256×256 circle
- JPEG 0.9 quality, base64 output
- 5MB file size limit check

**Integration**: UserProfileView "Upload Photo Avatar" button → sheet → saves to UserProfile.photoAvatarBase64.

---

## 13. Knowledge Graph Edges (`Features/Settings/Advanced/KnowledgeGraphView.swift`)

**Additions**:
- `KnowledgeEdge` model (id, sourceId, targetId, label, labelZh)
- Persisted at `knowledgeGraph.edges` via StorageService
- 3 builtin edges connecting existing nodes
- "Relationships" section in list view
- "Add Relationship" sheet with Picker-based source/target selection

---

## 14. Help View (`Features/Settings/HelpView.swift`)

**Features**:
- 5 FAQ items: API config, language, personas, affinity, export/import
- 3 quick tips
- DisclosureGroup accordion
- Version info section
- Bilingual (en/zh)

---

## Test Coverage

7 test files with 60+ test cases covering:
- **RAGServiceTests**: chunking, keywords, embedding, indexing, search, RAG context
- **ContextCompressorTests**: threshold, compression, ordering, system message filtering
- **TranslationServiceTests**: domain detection, glossary, response parsing, prompt building
- **PresenceServiceTests**: status enum, schedule resolution, presence map
- **AgentSkillStoreTests**: data integrity, categories, lookup, combined prompts, agent mapping
- **NotificationServiceTests**: unread counts, settings, DND mode
- **LinkPreviewTests**: URL extraction edge cases
- **GreetingServiceTests**: cooldown, nil cases, idle detection
