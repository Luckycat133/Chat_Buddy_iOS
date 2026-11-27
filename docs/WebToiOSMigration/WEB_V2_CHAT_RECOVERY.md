# Open Web v2 chat text on iOS

In the cloud app, open **Me → Data → Read Web chat backup** and select the
JSON that Web exports from Settings. This is a local read-only recovery view
for user-authored and assistant text, including author IDs and message order.
It does not change the source file, write to cloud chats, restore an account,
or upload any content. Keep the original JSON: media, memories, agents,
preferences, and other records are not restored by this view. Existing iOS
backup imports and account exports are independent.

The fixture was generated with the Web app's actual exporter running in a
clean Chromium context. Two synthetic messages were seeded through
`ChatStorageService` in IndexedDB; Web exported the JSON, then restored it
after the chat store was cleared. iOS tests use that export as their input.
Malformed authoritative IndexedDB records fail closed instead of looking
for a stale localStorage mirror. Older Web v2 exports with only a valid
localStorage mirror are supported.

This is not lossless cross-platform migration and is not the Web archive
gate. Cloud account migration still requires a canonical mapping for identity,
conversations, messages, persona/media references, and other backup data,
and a transactional import/re-export path on both platforms.
