# Bookplate

Bookplate is a SwiftUI app for tracking the books you read. Your collection is drawn as a bookcase: each shelf is a row of book spines, and a spine's thickness depends on the book's page count.

## Current state

| Area | Status |
|---|---|
| Login / sign-up | Screens only. No real accounts (see [Signing in](#signing-in)) |
| Library tab | Bookcase drawn from bundled sample JSON, search by title or author |
| Add book | Manual entry of title, author, page count and shelf, with a duplicate warning |
| Lists, Stats, Settings tabs | Empty placeholders |
| Persistence | None. Everything is in memory and resets on launch |
| Backend | None yet (see [Backend](#backend)) |
| Tests | None yet |

## Getting started

Requirements:

- macOS with Xcode 27 or newer. The deployment target is iOS 27.
- No third-party packages

```sh
git clone https://github.com/hussains-ha/bookplate.git
cd bookplate
open Bookplate/Bookplate.xcodeproj
```

Choose an iPhone simulator and run with ⌘R. To run on a device, set your own team under Signing & Capabilities. The bundle identifier is still a placeholder.

### Signing in

Login is hard-coded until there's an auth service (`LoginView.signIn()`):

- username `devuser`, password `pass`, or
- **Skip to library (dev)**, which appears on both the login and sign-up screens

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

There is no backend code in the repo yet. The diagram in `docs/architecture/` shows the planned setup: the app talks to Supabase (Postgres with row-level security, Auth and Storage) through the Supabase Swift SDK. None of that is wired up, and the SDK isn't a dependency yet.

## Contributing

Branch off `main` and open a pull request. Branches so far have been named `<name>-<feature>`, for example `tringuyen-manual-book-import`. Keep each PR to one feature, and don't commit your changes under `xcuserdata/`.

## Team

Hussain Hassan, Krystal Le, Tri Nguyen, Vuong Nguyen
