<div align="center">
  <img src="visionspark/assets/logo.png" alt="Visionspark Logo" width="150"/>
  <h1>Visionspark</h1>
  <p>✨ AI-Powered Image Generation & Gallery 🎨</p>
</div>

<div align="center">
  <img src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Supabase-3FCF8E?style=for-the-badge&logo=supabase&logoColor=white" alt="Supabase" />
  <img src="https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/license-MIT-blue.svg?style=for-the-badge" alt="License">
  <img src="https://img.shields.io/badge/contributions-welcome-brightgreen.svg?style=for-the-badge" alt="Contributions Welcome">
</div>

Welcome to Visionspark, a cutting-edge cross-platform application built with Flutter and powered by a robust Supabase backend. Visionspark offers a seamless and intuitive experience for generating stunning AI-driven images and exploring a vibrant community gallery.

---

## 📜 Table of Contents

- [🌟 Features at a Glance](#-features-at-a-glance)
- [📸 App Showcase](#-app-showcase)
- [🏗️ Project Architecture](#️-project-architecture)
- [🚀 Getting Started](#-getting-started)
- [🛠️ Supabase Backend Deep Dive](#️-supabase-backend-deep-dive)
- [🤝 Contributing](#-contributing)
- [📄 License](#-license)

---

## 🌟 Features at a Glance

-   👤 **Comprehensive User Management**:
    -   Secure authentication (Google Sign-In, password reset via deep links).
    -   Account management: Editable usernames, profile picture uploads (gallery/camera), join date tracking.
    -   Full account deletion capability.
-   🤖 **Advanced AI Image Generation (DALL-E 3)**:
    -   Generate stunning images with DALL-E 3 via Supabase Edge Functions.
    -   **Advanced Controls**: Specify aspect ratios (square, landscape, portrait), negative prompts, and styles (vivid, natural).
    -   **AI Prompt Assistance**:
        -   Improve your prompts with GPT-4o-mini.
        -   Get random prompt suggestions for inspiration.
    -   **Smart Generation Limits**: Daily limits reset based on user's local timezone. Monthly cycles and limits for subscribers.
-   ✨ **AI Image Enhancement (DALL-E 2)**: **NEW**
    -   Upload existing images or capture new ones for enhancement.
    -   **Modes**: `Enhance` (general improvement), `Edit` (modify based on prompt), `Variation` (create variations).
    -   Adjustable enhancement strength.
    -   Utilizes the same generation limit and prompt assistance features.
-   🖼️ **Dynamic Image Gallery**:
    -   Explore a public showcase ("Discover" tab) of AI-generated masterpieces.
    -   View your personal creations in "My Gallery" tab.
    -   Engage with content through likes.
    -   Optimized loading with cached images and thumbnails.
    -   Detailed image view with options to save to device, copy prompt, and share.
-   💳 **Full Subscription System (Google Play)**:
    -   Explore and purchase subscription tiers (`monthly_30`, `monthly_unlimited`).
    -   Secure server-side validation of Google Play purchases.
    *   Automatic profile updates with subscription status, tier, and expiry.
    *   Link to manage subscriptions directly in Google Play settings.
-   ⚙️ **Customizable Settings**:
    *   Seamlessly switch between Dark and Light themes (Material 3).
    *   Toggle auto-upload for generated/enhanced images to the public gallery.
    *   Option to clear local image cache.
-   🆘 **Database-Backed Support System**:
    *   In-app reporting for support issues or feedback.
    *   Tickets are stored and managed in the backend database.
-   📱 **Cross-Platform Excellence**: A consistent Material 3 themed experience across Android, iOS, and future platforms, built with Flutter.
-   🌐 **Offline Resilience**: A user-friendly offline screen with a retry option ensures a smooth experience without an internet connection.

---

## 📸 App Showcase

*(Coming Soon!)*

| Auth Screen                                     | Image Generator                               | Gallery                                       |
| ----------------------------------------------- | --------------------------------------------- | --------------------------------------------- |
| ![Auth Screen](link-to-your-screenshot.png)     | ![Generator](link-to-your-screenshot.png)     | ![Gallery](link-to-your-screenshot.png)       |

---

## 🏗️ Project Architecture

Visionspark's codebase is thoughtfully organized into the Flutter front-end and the Supabase back-end.

```
Visionspark/
├── visionspark/           # Main Flutter app source code
│   ├── lib/               # Dart source code
│   ├── android/           # Native Android code
│   ├── ios/               # Native iOS code
│   └── pubspec.yaml       # Dependencies
├── supabase/              # Supabase backend resources
│   ├── functions/         # Edge Functions (serverless logic)
│   ├── migrations/        # SQL migration scripts
│   └── config.toml        # Supabase CLI configuration
├── .cursor/               # Cursor navigation rules
├── .gitignore             # Git ignore rules
└── README.md              # This file
```

### 📱 `visionspark/lib` (Flutter/Dart Files)

This directory houses the core Flutter application logic and UI components, structured for modularity:

-   `auth/`: Screens and logic for user authentication (Google Sign-In, Auth Gate).
-   `features/`: Distinct feature modules:
    -   `account/`: User profile management, profile picture upload, username editing, account deletion.
    -   `gallery/`: Public and user-specific image galleries, image detail view, liking system.
    -   `image_enhancement/`: **New** screen for DALL-E 2 based image enhancement, editing, and variations.
    -   `image_generator/`: DALL-E 3 based image generation with advanced controls (negative prompts, styles, aspect ratios) and prompt assistance.
    -   `settings/`: Theme control, auto-upload toggle, cache clearing, subscription management links.
    -   `subscriptions/`: **New** screen for viewing and purchasing Google Play subscriptions.
    -   `support/`: **New** screen for submitting database-backed support tickets.
-   `shared/`: Common widgets (e.g., `MainScaffold`), utilities (snackbar, connectivity), and notifiers (theme, subscription status).
-   `main.dart`: The application's entry point, theme setup, Supabase initialization, and deep link handling.

### 🚀 `supabase/` (Supabase Backend)

This folder contains all files to manage the Supabase backend:

-   `functions/`: TypeScript Edge Functions for server-side operations:
    -   `delete-account`: Handles full user account deletion.
    -   `enhance-image-proxy`: **New** DALL-E 2 image enhancement, editing, and variations.
    -   `generate-image-proxy`: DALL-E 3 image generation with advanced limit logic.
    -   `get-gallery-feed`: Fetches gallery images with signed URLs and like status.
    -   `get-generation-status`: **New** Provides detailed generation limit/subscription status to the client.
    -   `get-random-prompt`: **New** Returns a random prompt for image generation.
    -   `improve-prompt-proxy`: **New** Enhances user prompts using GPT-4o-mini.
    -   `report-support-issue`: **Updated** Submits user support tickets to the database.
    -   `validate-purchase-and-update-profile`: **New** Securely validates Google Play purchases and updates user profiles.
-   `migrations/`: Version-controlled SQL scripts that define and evolve the database schema (e.g., `profiles` enhancements, `gallery_images`, `gallery_likes`, `support_tickets`, `webhook_rate_limits`).
-   `config.toml`: Configuration for the Supabase CLI.
-   `SECURITY_GUIDANCE.md`: Important security best practices.

---

## 🚀 Getting Started

Follow these steps to set up and run Visionspark locally.

### Prerequisites

-   **Flutter SDK**: Latest stable release recommended.
-   **Dart SDK**: Bundled with Flutter.
-   **Supabase CLI**: For managing the backend.
-   **Node.js & npm**: For Supabase Edge Functions development.
-   An active **Supabase account**.

### Setup Guide

1.  **Clone the Repository**:
    ```bash
    git clone https://github.com/RustyCMD/Visionspark.git
    cd Visionspark
    ```

2.  **Set up Your Supabase Project**:
    -   Create a new project on [Supabase.com](https://supabase.com).
    -   Retrieve your **Project URL** and **Anon Key**.
    -   Configure these **Environment Variables** in your Supabase project dashboard (Project Settings > Edge Functions):
        -   `SUPABASE_SERVICE_ROLE_KEY`: Found in your project's API Settings. (Required by most functions)
        -   `OPENAI_API_KEY`: Your OpenAI API key. (Required for `generate-image-proxy`, `enhance-image-proxy`, `improve-prompt-proxy`)
        -   `GOOGLE_SERVICE_ACCOUNT_EMAIL`: Your Google Service Account email. (Required for `validate-purchase-and-update-profile`)
        -   `GOOGLE_PRIVATE_KEY_PEM`: Your Google Service Account private key PEM string (ensure newlines are escaped as `\n` or handled correctly when setting). (Required for `validate-purchase-and-update-profile`)
        -   `DISCORD_WEBHOOK`: (Optional) Your Discord webhook URL if you plan to integrate Discord notifications for support or other events. The current `report-support-issue` function saves to the database directly, but the `webhook_rate_limits` table exists for potential webhook usage.

3.  **Configure the Flutter Application**:
    -   Navigate to the Flutter app directory:
        ```bash
        cd visionspark
        ```
    -   Create a `.env` file (`visionspark/.env`) and add your credentials:
        ```
        SUPABASE_URL=YOUR_SUPABASE_PROJECT_URL
        SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY
        ```
    -   **Security Note**: Ensure `.env` is listed in your root `.gitignore`.

4.  **Install Dependencies**:
    ```bash
    flutter pub get
    ```

5.  **Set up Local Supabase Environment**:
    -   Navigate to the Supabase directory:
        ```bash
        cd ../supabase
        ```
    -   Log in and link your project:
        ```bash
        supabase login
        supabase link --project-ref YOUR_PROJECT_REF
        ```
    -   To run services locally:
        ```bash
        supabase start
        ```

6.  **Deploy Supabase Migrations & Functions**:
    -   Push database migrations:
        ```bash
        supabase db push
        ```
    -   Deploy Edge Functions:
        ```bash
        # Deploy specific functions
        supabase functions deploy --project-ref YOUR_PROJECT_REF [FUNCTION_NAME]

        # Or deploy all functions
        supabase functions deploy --project-ref YOUR_PROJECT_REF --all
        ```

7.  **Run the Flutter App**:
    -   Return to the Flutter app directory:
        ```bash
        cd ../visionspark
        ```
    -   Launch the app:
        ```bash
        flutter run
        ```

---

## 🛠️ Supabase Backend Deep Dive

The Supabase backend powers Visionspark's data, authentication, and serverless logic.

-   **Edge Functions**: Low-latency TypeScript functions handling critical operations:
    -   **AI Operations**: `generate-image-proxy` (DALL-E 3), `enhance-image-proxy` (DALL-E 2), `improve-prompt-proxy` (GPT-4o-mini), `get-random-prompt`.
    -   **User & Data Management**: `delete-account`, `get-gallery-feed`, `get-generation-status`.
    -   **Monetization**: `validate-purchase-and-update-profile` for Google Play in-app purchases.
    -   **Support**: `report-support-issue` (saves to database).
    -   Ensure all required environment variables (see "Getting Started") are correctly set, especially `OPENAI_API_KEY`, `GOOGLE_SERVICE_ACCOUNT_EMAIL`, and `GOOGLE_PRIVATE_KEY_PEM`.
-   **Database Migrations**: Version-controlled SQL scripts in `supabase/migrations/` define the database schema. Key tables include:
    -   `profiles`: Stores extended user data like usernames, generation limits, timezone, and subscription details.
    -   `gallery_images`: Contains metadata for images in the public gallery, including prompts and like counts.
    -   `gallery_likes`: Tracks user likes on gallery images.
    -   `support_tickets`: Stores user-submitted support issues.
    -   `webhook_rate_limits`: Manages rate limiting for outgoing webhooks (e.g., for potential future Discord notifications).
    -   Triggers and functions are used for tasks like automatic profile creation and like count updates.

---

## 🤝 Contributing

We warmly welcome contributions to Visionspark! If you're interested in improving the app or adding new features, please follow these guidelines:

1.  **Fork** the repository.
2.  Create a new feature branch: `git checkout -b feature/your-awesome-feature`.
3.  Implement your changes and ensure tests pass.
4.  Commit your changes with a clear message: `git commit -m 'Feat: Add a new awesome feature'`.
5.  Push to your branch and open a **Pull Request**.

---

## 📄 License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

---
<div align="center">
  <p>Made with ❤️ and a bit of ✨</p>
</div>
