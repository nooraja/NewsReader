# NewsReader

NewsReader is a UIKit iPhone app for browsing NewsAPI categories, publishers, and articles. Search sources within a category or search articles from a selected publisher. Tap an article to read the publisher's page in the app.

## Run in Xcode

1. Open `NewsReader.xcodeproj` in Xcode 27.2 or later.
2. Select an iPhone simulator and the **Offline Demo** scheme, then press **⌘R**. The demo includes enough sources and articles to exercise search and endless scrolling.
3. For live data, duplicate the **NewsReader** scheme, leave the duplicate unshared, and set `NEWSAPI_KEY` under **Edit Scheme → Run → Arguments → Environment Variables**. Run the local scheme.

The deployment target is iOS 17. The app has no package dependencies. Keep your NewsAPI key in the unshared scheme. NewsAPI's Developer plan is for development and testing. [NewsAPI pricing](https://newsapi.org/pricing)

## Architecture

The four VIPER modules are Categories, Sources, Articles, and Article Detail. View controllers forward user actions and render state. Presenters decide what the view shows, interactors retrieve and process data, and routers assemble the modules and navigate between them. The app injects either the live NewsAPI client or the deterministic demo client at launch.

Sources arrive as a single response. The app filters the whole category and reveals matching sources in batches of 20. Articles use the Everything endpoint for keyword search and pagination. A retry on a failed article page keeps the current rows visible. [Sources endpoint](https://newsapi.org/docs/endpoints/sources) · [Everything endpoint](https://newsapi.org/docs/endpoints/everything)

## Tests

Choose **NewsReader** and press **⌘U**. Unit tests cover requests, decoding, errors, search, and pagination. UI tests exercise the category-to-article flow with offline data. Tests do not require an API key.

The generated Xcode project is included. After adding or moving Swift files, regenerate it locally with `xcodegen generate`.
