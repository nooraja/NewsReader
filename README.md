# NewsReader

NewsReader is a UIKit iPhone app for browsing news sources and articles from NewsAPI.

## What to install

- Install Xcode on a Mac. The project was tested with Xcode 27.2. [Download Xcode](https://developer.apple.com/xcode/)
- Install an iOS simulator runtime from **Xcode → Settings → Components**. The app targets iOS 17 and later. [Install an iOS simulator runtime](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components)

The repository includes `NewsReader.xcodeproj`. Build and run it directly in Xcode with no third-party dependencies. Install XcodeGen only if you need to regenerate the project after adding or moving Swift files. Run `xcodegen generate` from the repository root.

## Run the offline demo

1. Download the repository using **Code → Download ZIP** on GitHub and extract it, or clone it locally.
2. Open `NewsReader.xcodeproj` in Xcode.
3. Select the **Offline Demo** scheme and an iPhone simulator in the toolbar.
4. Press **⌘R**. The app opens on **Categories**. The demo uses sample data and runs without an API key.

## Run with live news

Each user must use their own NewsAPI key to run the app with live news.

1. Register for your own key or use a key from your existing NewsAPI account. [Register for a NewsAPI key](https://newsapi.org/register)
2. In Xcode, open **Product → Scheme → Manage Schemes**. Duplicate **NewsReader** as **NewsReader Local**, then clear **Shared** for the copy.
3. Select **NewsReader Local** and open **Product → Scheme → Edit Scheme**.
4. In **Run → Arguments → Environment Variables**, add `NEWSAPI_KEY` with your key as its value. Keep the scheme local to your Mac.
5. Select an iPhone simulator and press **⌘R**. Open a category to load live sources. NewsAPI's Developer plan is for development and testing. [NewsAPI pricing](https://newsapi.org/pricing)

## Use the app

1. Tap a category such as **General** to see its news sources.
2. Use **Search sources** to find a publisher, or scroll down to load more sources. In the demo, try **General Desk 30**.
3. Tap a source to see its articles. Use **Search articles** or scroll down to load more. In the demo, try **Field Notes**.
4. Tap an article to open its detail in the in-app web view.

## Architecture

The four VIPER modules are Categories, Sources, Articles, and Article Detail. View controllers forward user actions and render state. Presenters decide what the view shows, interactors retrieve and process data, and routers assemble the modules and navigate between them. The app injects either the live NewsAPI client or the deterministic demo client at launch.

Sources arrive as a single response. The app filters the whole category and reveals matching sources in batches of 20. Articles use the Everything endpoint for keyword search and pagination. A retry on a failed article page keeps the current rows visible. [Sources endpoint](https://newsapi.org/docs/endpoints/sources) · [Everything endpoint](https://newsapi.org/docs/endpoints/everything)

## Tests

Choose **NewsReader** and an iPhone simulator, then press **⌘U**. Unit tests cover requests, decoding, errors, search, and pagination. UI tests exercise the category-to-article flow with offline data. Tests run without an API key.
