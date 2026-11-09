# Bookplate

Bookplate is a SwiftUI app for tracking the books you read. Your collection is drawn as a bookcase: each shelf is a row of book spines, and a spine's thickness depends on the book's page count.

## Current state

| Area | Status |
|---|---|
| Login / sign-up | Supabase email/password accounts (see [Signing in](#signing-in)) |
| Library tab | Bookcase drawn from bundled sample JSON, search by title or author |
| Add book | Manual entry of title, author, page count and shelf, with a duplicate warning |
| Lists, Stats, Settings tabs | Empty placeholders |
| Persistence | Signed-in libraries save every change to Supabase. Custom covers and note photos stay on the device. Dev skip uses in-memory sample data |
| Backend | Supabase: auth, and each user's books, details, shelves and lists (see [Backend](#backend)) |
| Tests | None yet |

## Getting started

Requirements:

- macOS with Xcode 27 or newer. The deployment target is iOS 27.
- [supabase-swift](https://github.com/supabase/supabase-swift), added through Swift Package Manager. Xcode fetches it on first open.

```sh
git clone https://github.com/hussains-ha/bookplate.git
cd bookplate
open Bookplate/Bookplate.xcodeproj
```

Before the first run, set up the Supabase key (see [Backend setup](#backend-setup)). Then choose an iPhone simulator and run with ⌘R. To run on a device, set your own team under Signing & Capabilities. The bundle identifier is still a placeholder.

### Signing in

Accounts use Supabase Auth with email and password (`Services/AuthService.swift`). Create one from **Create account**; the session is kept in the Keychain, so you stay signed in across launches. Sign out from the Settings tab.

Email confirmation is on: after **Create account**, confirm from the email Supabase sends, then sign in. (The link's redirect page may not load on a phone yet; the account is confirmed anyway.) **Skip to library (dev)** still opens the app without an account.

## Project structure

```
Bookplate/
├── Bookplate.xcodeproj
└── Bookplate/
    ├── MyApp.swift              Entry point; creates the LibraryStore
    ├── Models/                  Book, BookMeta, Shelf, Bookshelf
    ├── Stores/
    │   └── LibraryStore.swift   In-memory state and library operations
    ├── Views/
    │   ├── RootView.swift       Switches between auth screens and the app
    │   ├── MainTabView.swift    Tab bar
    │   ├── Auth/                Login, sign-up, shared form components
    │   └── Library/             LibraryView, ShelfView, SpineView, AddBookView
    ├── Theme/
    │   └── Theme.swift          Colors, fonts, spine palette
    └── Resources/               Sample JSON data
docs/
└── architecture/                Architecture diagram (Mermaid source, PNG, SVG)
```

## How the app works

### State

`MyApp` creates one `LibraryStore` and passes it down with `.environment(store)`. Views read it with `@Environment(LibraryStore.self)`. The store is `@Observable` and `@MainActor`, and its properties are `private(set)`, so changes go through store methods:

- `books(on:matching:)` returns a shelf's books in order, filtered by a title/author query. Matching ignores case and accents.
- `findDuplicate(title:author:)` finds an existing book with the same title and author.
- `addBook(title:author:pageCount:shelfId:)` creates a `Book` and its `BookMeta` (status `want`) and puts the book at the front of the chosen shelf. If the bookcase has no shelves, it creates a "Recently Added" shelf.

`RootView` handles navigation between login, sign-up and the main app with a local `@State` enum. It doesn't use a real session.

### Data model

| Type | Holds |
|---|---|
| `Book` | Facts that are the same for anyone: title, authors, page count, cover URL, ISBN-13 |
| `BookMeta` | One user's data for a book, matched by `bookId`: status, rating (1–5), notes, tags, custom cover, dates |
| `Shelf` | A name and an ordered list of book IDs. A book can be on more than one shelf. |
| `Bookshelf` | A named set of shelves plus an appearance (`classic`, `maple`, `modern`) |

`BookMeta.status` is a `String` so custom statuses can be added later. The defaults (`want`, `reading`, `read`) are in `BookMeta.Status`.

`BookMeta` and `Bookshelf.appearance` are loaded but nothing in the UI shows them yet.

### Sample data

`LibraryStore.sample()` loads `books.json`, `bookmeta.json` and `bookshelves.json` from `Resources/` and uses the first bookshelf. If a file is missing or fails to decode, it falls back to the `mocks` defined in that model's file. `shelves.json` is bundled but the store doesn't read it, because shelves come from `bookshelves.json`. Dates in `bookmeta.json` are ISO 8601.

## Backend

The app talks to Supabase (Postgres with row-level security, Auth and Storage) through the Supabase Swift SDK. The diagram in `docs/architecture/` shows the planned setup. The client is `SupabaseService.client` in `Services/SupabaseService.swift`.

- **Schema:** `supabase/migrations/` holds the SQL applied to the project: `books`, `book_meta`, `shelves`, `shelf_books`, `lists`, `list_books`, and the `set_shelf_books` / `set_list_books` functions. Every table is owned per user (`user_id` defaults to the session) with row-level security.
- **Loading:** after sign-in, `SignedInLibraryView` loads the library through `SupabaseLibraryRepository`. New accounts start empty.
- **Saving:** every `LibraryStore` change is queued in `LibrarySync` and saved in order. A failed save shows a banner and retries with backoff; a change the database refuses is dropped and reported.
- **On the device only (until #36):** custom covers and note photos, recorded per user in Application Support.
- **Integration test:** `SupabaseIntegrationTests` runs only with credentials for a confirmed throwaway account: `TEST_RUNNER_BOOKPLATE_E2E_EMAIL=… TEST_RUNNER_BOOKPLATE_E2E_PASSWORD=… xcodebuild test …`.

### Backend setup

The project URL is committed in `Bookplate/Config.xcconfig`. The key is not:

1. Copy `Bookplate/Secrets.example.xcconfig` to `Bookplate/Secrets.xcconfig`. The copy is gitignored.
2. Set `SUPABASE_KEY` to the project's publishable key. It's in the Supabase dashboard under Project Settings → API Keys, or ask a teammate.

The values reach the app through `Bookplate-Info.plist`. Without a key the app still builds, but it stops the first time it uses Supabase, with a message pointing to these steps.

## Contributing

Branch off `main` and open a pull request. Branches so far have been named `<name>-<feature>`, for example `tringuyen-manual-book-import`. Keep each PR to one feature, and don't commit your changes under `xcuserdata/`.

## Team

Hussain Hassan, Krystal Le, Tri Nguyen, Vuong Nguyen
